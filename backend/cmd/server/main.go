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

	// Initialize handlers
	healthHandler := handler.NewHealthHandler(db)

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
		r.Get("/health", healthHandler.Health)
	})

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
