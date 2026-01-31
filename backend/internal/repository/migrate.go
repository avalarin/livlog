package repository

import (
	"errors"
	"fmt"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"go.uber.org/zap"

	"github.com/avalarin/livlog/backend/internal/config"
)

func RunMigrations(cfg *config.DatabaseConfig, migrationsPath string, logger *zap.Logger) error {
	m, err := migrate.New(
		fmt.Sprintf("file://%s", migrationsPath),
		cfg.DSN(),
	)
	if err != nil {
		return fmt.Errorf("failed to create migrate instance: %w", err)
	}
	defer m.Close()

	if err := m.Up(); err != nil {
		if errors.Is(err, migrate.ErrNoChange) {
			logger.Info("no new migrations to apply")
			return nil
		}
		return fmt.Errorf("failed to apply migrations: %w", err)
	}

	version, dirty, err := m.Version()
	if err != nil && !errors.Is(err, migrate.ErrNilVersion) {
		return fmt.Errorf("failed to get migration version: %w", err)
	}

	logger.Info("migrations applied successfully",
		zap.Uint("version", version),
		zap.Bool("dirty", dirty),
	)

	return nil
}
