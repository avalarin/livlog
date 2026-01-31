package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoad_Defaults(t *testing.T) {
	// Create a temp directory without config file to test defaults
	tmpDir := t.TempDir()
	origDir, _ := os.Getwd()
	defer func() { _ = os.Chdir(origDir) }()
	_ = os.Chdir(tmpDir)

	cfg, err := Load("")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if cfg.Server.Host != "0.0.0.0" {
		t.Errorf("expected default host 0.0.0.0, got %s", cfg.Server.Host)
	}
	if cfg.Server.Port != 8080 {
		t.Errorf("expected default port 8080, got %d", cfg.Server.Port)
	}
	if cfg.Logging.Format != "console" {
		t.Errorf("expected default logging format console, got %s", cfg.Logging.Format)
	}
}

func TestLoad_FromFile(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")

	configContent := `
server:
  host: "127.0.0.1"
  port: 9090
database:
  host: "db.example.com"
  port: 5433
  name: "testdb"
  user: "testuser"
  password: "testpass"
  sslmode: "require"
logging:
  format: "json"
`
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("failed to write config file: %v", err)
	}

	cfg, err := Load(configPath)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if cfg.Server.Host != "127.0.0.1" {
		t.Errorf("expected host 127.0.0.1, got %s", cfg.Server.Host)
	}
	if cfg.Server.Port != 9090 {
		t.Errorf("expected port 9090, got %d", cfg.Server.Port)
	}
	if cfg.Database.Host != "db.example.com" {
		t.Errorf("expected db host db.example.com, got %s", cfg.Database.Host)
	}
	if cfg.Logging.Format != "json" {
		t.Errorf("expected logging format json, got %s", cfg.Logging.Format)
	}
}

func TestServerConfig_Address(t *testing.T) {
	cfg := ServerConfig{Host: "localhost", Port: 8080}
	expected := "localhost:8080"
	if cfg.Address() != expected {
		t.Errorf("expected %s, got %s", expected, cfg.Address())
	}
}

func TestDatabaseConfig_DSN(t *testing.T) {
	cfg := DatabaseConfig{
		Host:     "localhost",
		Port:     5432,
		Name:     "testdb",
		User:     "testuser",
		Password: "testpass",
		SSLMode:  "disable",
	}

	expected := "postgres://testuser:testpass@localhost:5432/testdb?sslmode=disable"
	if cfg.DSN() != expected {
		t.Errorf("expected %s, got %s", expected, cfg.DSN())
	}
}
