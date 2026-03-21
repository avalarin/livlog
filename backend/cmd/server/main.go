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
	"github.com/avalarin/livlog/backend/internal/version"
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
		zap.String("version", version.Full()),
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
	attemptRepo := repository.NewVerificationAttemptRepository(db.Pool)
	collectionRepo := repository.NewCollectionRepository(db.Pool)
	entryRepo := repository.NewEntryRepository(db.Pool)
	typeRepo := repository.NewTypeRepository(db.Pool)
	aiSearchUsageRepo := repository.NewAISearchUsageRepository(db.Pool)
	mcpRepo := repository.NewMCPRepository(db.Pool)
	tagRepo := repository.NewTagRepository(db.Pool)

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

	// Parse email duration config values
	resendCooldown, err := time.ParseDuration(cfg.Email.ResendCooldown)
	if err != nil {
		log.Fatal("failed to parse email.resend_cooldown", zap.Error(err))
	}

	perEmailCooldown, err := time.ParseDuration(cfg.Email.PerEmailCooldown)
	if err != nil {
		log.Fatal("failed to parse email.per_email_cooldown", zap.Error(err))
	}

	deviceWindow, err := time.ParseDuration(cfg.Email.DeviceWindow)
	if err != nil {
		log.Fatal("failed to parse email.device_window", zap.Error(err))
	}

	// Validate email config
	if cfg.Email.Enabled && cfg.Email.APIKey == "" {
		log.Fatal("email.enabled is true but email.api_key is not set")
	}

	// Initialize email sender
	emailSender := service.NewEmailSender(cfg.Email.Enabled, cfg.Email.APIKey, cfg.Email.FromName, cfg.Email.FromAddress, log)

	// Initialize email auth service
	emailAuthService := service.NewEmailAuthService(
		userRepo, codeRepo, attemptRepo, jwtService, emailSender,
		resendCooldown, cfg.Email.MaxCodesPerHour, cfg.Email.IPRateLimitEnabled,
		perEmailCooldown, cfg.Email.DeviceMaxEmails, deviceWindow,
	)

	// Initialize collection, entry, and type services
	collectionService := service.NewCollectionService(collectionRepo, userRepo)
	entryService := service.NewEntryService(entryRepo, collectionRepo, typeRepo)
	typeService := service.NewTypeService(typeRepo)

	// Initialize MCP service
	mcpService := service.NewMCPService(mcpRepo, cfg.Server.PublicURL())

	// Initialize AI search service
	aiSearchService, err := service.NewAISearchService(cfg, aiSearchUsageRepo, userRepo, log)
	if err != nil {
		log.Fatal("failed to initialize AI search service", zap.Error(err))
	}

	// Initialize onboarding service
	onboardingService := service.NewOnboardingService(userRepo, collectionRepo, entryRepo)

	// Initialize handlers
	healthHandler := handler.NewHealthHandler(db)
	authHandler := handler.NewAuthHandler(authService, emailAuthService, log)
	collectionHandler := handler.NewCollectionHandler(collectionService, log)
	entryHandler := handler.NewEntryHandler(entryService, log)
	typeHandler := handler.NewTypeHandler(typeService, log)
	aiSearchHandler := handler.NewAISearchHandler(aiSearchService, log)
	onboardingHandler := handler.NewOnboardingHandler(onboardingService, log)
	mcpHandler := handler.NewMCPHandler(mcpService, log)
	mcpProtocolHandler := handler.NewMCPProtocolHandler(mcpService, collectionService, entryService, typeService, tagRepo, log)

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

	// MCP protocol endpoint (no /api/v1 prefix, auth via unique_code)
	mcpProtocolHandler.RegisterRoutes(r)

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

			// Onboarding endpoint
			onboardingHandler.RegisterRoutes(r)

			// MCP management endpoint
			mcpHandler.RegisterRoutes(r)
		})
	})

	// Start cleanup goroutine for expired verification codes and old verification attempts
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				// Cleanup expired verification codes (older than 24 hours)
				deleted, err := codeRepo.CleanupExpiredCodes(ctx, 24*time.Hour)
				if err != nil {
					log.Error("failed to cleanup verification codes", zap.Error(err))
				} else if deleted > 0 {
					log.Info("cleaned up verification codes", zap.Int64("deleted", deleted))
				}

				// Cleanup old verification attempts (older than 24 hours)
				deletedAttempts, err := attemptRepo.CleanupOldAttempts(ctx, 24*time.Hour)
				if err != nil {
					log.Error("failed to cleanup verification attempts", zap.Error(err))
				} else if deletedAttempts > 0 {
					log.Info("cleaned up verification attempts", zap.Int64("deleted", deletedAttempts))
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
