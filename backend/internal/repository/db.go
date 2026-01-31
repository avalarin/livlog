package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"github.com/avalarin/livlog/backend/internal/config"
)

type DB struct {
	Pool   *pgxpool.Pool
	logger *zap.Logger
}

func NewDB(ctx context.Context, cfg *config.DatabaseConfig, logger *zap.Logger) (*DB, error) {
	poolConfig, err := pgxpool.ParseConfig(cfg.DSN())
	if err != nil {
		return nil, fmt.Errorf("failed to parse database config: %w", err)
	}

	poolConfig.MaxConns = 10
	poolConfig.MinConns = 2
	poolConfig.MaxConnLifetime = time.Hour
	poolConfig.MaxConnIdleTime = 30 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	logger.Info("connected to database",
		zap.String("host", cfg.Host),
		zap.Int("port", cfg.Port),
		zap.String("database", cfg.Name),
	)

	return &DB{
		Pool:   pool,
		logger: logger,
	}, nil
}

func (db *DB) Close() {
	db.Pool.Close()
	db.logger.Info("database connection closed")
}

func (db *DB) Ping(ctx context.Context) (time.Duration, error) {
	start := time.Now()
	err := db.Pool.Ping(ctx)
	return time.Since(start), err
}
