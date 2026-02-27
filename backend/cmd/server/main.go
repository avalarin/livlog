package main

import (
	"context"
	"flag"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"

	"github.com/avalarin/livlog/backend/internal/config"
	"github.com/avalarin/livlog/backend/internal/handler"
	"github.com/avalarin/livlog/backend/internal/logger"
	"github.com/avalarin/livlog/backend/internal/middleware"
	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/avalarin/livlog/backend/internal/seed"
	"github.com/avalarin/livlog/backend/internal/service"
)

func main() {
	configPath := flag.String("config", "", "path to config file")
	migrationsPath := flag.String("migrations", "migrations", "path to migrations directory")
	flag.Parse()

	// Load configuration
	cfg, err := config.Load(*configPath)
	if err != nil {
		panic("failed to load config: " + err.Error())
	}

	// Initialize logger
	log, err := logger.New(cfg.Logging.Format)
	if err != nil {
		panic("failed to initialize logger: " + err.Error())
	}
	defer func() {
		_ = log.Sync()
	}()

	log.Info("starting livlog backend",
		zap.String("version", handler.Version),
		zap.String("address", cfg.Server.Address()),
	)

	// Run migrations
	log.Info("running database migrations")
	if err := repository.RunMigrations(&cfg.Database, *migrationsPath, log); err != nil {
		log.Fatal("failed to run migrations", zap.Error(err))
	}

	// Connect to database
	ctx := context.Background()
	db, err := repository.NewDB(ctx, &cfg.Database, log)
	if err != nil {
		log.Fatal("failed to connect to database", zap.Error(err))
	}
	defer db.Close()

	// Initialize repositories
	userRepo := repository.NewUserRepository(db.Pool)
	codeRepo := repository.NewVerificationCodeRepository(db.Pool)
	collectionRepo := repository.NewCollectionRepository(db.Pool)
	entryRepo := repository.NewEntryRepository(db.Pool)
	typeRepo := repository.NewTypeRepository(db.Pool)
	aiSearchUsageRepo := repository.NewAISearchUsageRepository(db.Pool)

	// Seed cover images with fixed UUIDs
	log.Info("seeding cover images")
	if err := entryRepo.UpsertSeedImages(ctx, seed.Images); err != nil {
		log.Fatal("failed to seed images", zap.Error(err))
	}

	// Initialize services
	appleVerifier := service.NewAppleVerifier(cfg.Apple.BundleID)
	jwtService, err := service.NewJWTService(
		cfg.JWT.PrivateKeyPath,
		cfg.JWT.PublicKeyPath,
		cfg.JWT.AccessTokenLifetime,
		cfg.JWT.RefreshTokenLifetime,
		cfg.JWT.Issuer,
		cfg.JWT.Audience,
	)
	if err != nil {
		log.Fatal("failed to initialize JWT service", zap.Error(err))
	}

	authService := service.NewAuthService(userRepo, appleVerifier, jwtService)

	// Initialize rate limiter for email auth (60 second window)
	rateLimiter := service.NewRateLimiter(60 * time.Second)

	// Initialize email auth service
	emailAuthService := service.NewEmailAuthService(userRepo, codeRepo, jwtService, rateLimiter)

	// Initialize collection, entry, and type services
	collectionService := service.NewCollectionService(collectionRepo)
	entryService := service.NewEntryService(entryRepo, collectionRepo, typeRepo)
	typeService := service.NewTypeService(typeRepo)

	// Initialize AI search service
	aiSearchService, err := service.NewAISearchService(cfg, aiSearchUsageRepo, userRepo, log)
	if err != nil {
		log.Fatal("failed to initialize AI search service", zap.Error(err))
	}

	// Initialize handlers
	healthHandler := handler.NewHealthHandler(db)
	authHandler := handler.NewAuthHandler(authService, emailAuthService)
	collectionHandler := handler.NewCollectionHandler(collectionService)
	entryHandler := handler.NewEntryHandler(entryService)
	typeHandler := handler.NewTypeHandler(typeService)
	aiSearchHandler := handler.NewAISearchHandler(aiSearchService)

	// Setup router
	r := chi.NewRouter()

	// Global middleware
	r.Use(chimw.RequestID)
	r.Use(chimw.RealIP)
	r.Use(middleware.Logging(log))
	r.Use(middleware.Metrics)
	r.Use(chimw.Recoverer)

	// Metrics endpoint (no /api/v1 prefix)
	r.Handle("/metrics", promhttp.Handler())

	// API v1 routes
	r.Route("/api/v1", func(r chi.Router) {
		// Public routes
		r.Get("/health", healthHandler.Health)
		r.Post("/auth/apple", authHandler.AppleAuth)
		r.Post("/auth/email/send-code", authHandler.SendVerificationCode)
		r.Post("/auth/email/resend-code", authHandler.ResendVerificationCode)
		r.Post("/auth/email/verify", authHandler.VerifyEmailCode)
		r.Post("/auth/refresh", authHandler.RefreshToken)
		entryHandler.RegisterPublicRoutes(r)

		// Protected routes
		r.Group(func(r chi.Router) {
			r.Use(middleware.AuthMiddleware(jwtService))

			r.Get("/auth/me", authHandler.GetMe)
			r.Post("/auth/logout", authHandler.Logout)
			r.Delete("/auth/account", authHandler.DeleteAccount)

			// Collections, entries, and types endpoints
			collectionHandler.RegisterRoutes(r)
			entryHandler.RegisterRoutes(r)
			typeHandler.RegisterRoutes(r)

			// AI search endpoint
			aiSearchHandler.RegisterRoutes(r)
		})
	})

	// Start cleanup goroutine for expired verification codes and rate limiter
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				// Cleanup rate limiter
				rateLimiter.Cleanup()

				// Cleanup expired verification codes (older than 24 hours)
				deleted, err := codeRepo.CleanupExpiredCodes(ctx, 24*time.Hour)
				if err != nil {
					log.Error("failed to cleanup verification codes", zap.Error(err))
				} else if deleted > 0 {
					log.Info("cleaned up verification codes", zap.Int64("deleted", deleted))
				}
			case <-ctx.Done():
				return
			}
		}
	}()

	// Create HTTP server
	server := &http.Server{
		Addr:         cfg.Server.Address(),
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Info("http server listening", zap.String("address", cfg.Server.Address()))
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal("failed to start http server", zap.Error(err))
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Info("shutting down server...")

	// Graceful shutdown with timeout
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Error("server forced to shutdown", zap.Error(err))
	}

	log.Info("server stopped")
}
