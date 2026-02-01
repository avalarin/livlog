package config

import (
	"fmt"
	"strings"

	"github.com/spf13/viper"
)

type Config struct {
	Server     ServerConfig     `mapstructure:"server"`
	Database   DatabaseConfig   `mapstructure:"database"`
	Logging    LoggingConfig    `mapstructure:"logging"`
	JWT        JWTConfig        `mapstructure:"jwt"`
	Apple      AppleConfig      `mapstructure:"apple"`
	OpenRouter OpenRouterConfig `mapstructure:"openrouter"`
	RateLimit  RateLimitConfig  `mapstructure:"ratelimit"`
}

type ServerConfig struct {
	Host string `mapstructure:"host"`
	Port int    `mapstructure:"port"`
}

type DatabaseConfig struct {
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	Name     string `mapstructure:"name"`
	User     string `mapstructure:"user"`
	Password string `mapstructure:"password"`
	SSLMode  string `mapstructure:"sslmode"`
}

type LoggingConfig struct {
	Format string `mapstructure:"format"` // "json" or "console"
}

type JWTConfig struct {
	PrivateKeyPath       string `mapstructure:"private_key_path"`
	PublicKeyPath        string `mapstructure:"public_key_path"`
	AccessTokenLifetime  int    `mapstructure:"access_token_lifetime"`
	RefreshTokenLifetime int    `mapstructure:"refresh_token_lifetime"`
	Issuer               string `mapstructure:"issuer"`
	Audience             string `mapstructure:"audience"`
}

type AppleConfig struct {
	BundleID string `mapstructure:"bundle_id"`
}

type OpenRouterConfig struct {
	APIKey  string `mapstructure:"api_key"`
	BaseURL string `mapstructure:"base_url"`
	Model   string `mapstructure:"model"`
}

type RateLimitConfig struct {
	AISearchBasicLimit     int    `mapstructure:"ai_search_basic_limit"`
	AISearchProLimit       int    `mapstructure:"ai_search_pro_limit"`
	AISearchUnlimitedLimit int    `mapstructure:"ai_search_unlimited_limit"` // 0 means no limit
	AISearchPeriod         string `mapstructure:"ai_search_period"`
}

// GetAISearchLimit returns the AI search limit for the given policy
func (r *RateLimitConfig) GetAISearchLimit(policy string) int {
	switch policy {
	case "basic":
		return r.AISearchBasicLimit
	case "pro":
		return r.AISearchProLimit
	case "unlimited":
		return r.AISearchUnlimitedLimit
	default:
		return r.AISearchBasicLimit
	}
}

func (s *ServerConfig) Address() string {
	return fmt.Sprintf("%s:%d", s.Host, s.Port)
}

func (d *DatabaseConfig) DSN() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%d/%s?sslmode=%s",
		d.User,
		d.Password,
		d.Host,
		d.Port,
		d.Name,
		d.SSLMode,
	)
}

func Load(configPath string) (*Config, error) {
	v := viper.New()

	// Set defaults
	v.SetDefault("server.host", "0.0.0.0")
	v.SetDefault("server.port", 8080)
	v.SetDefault("database.host", "localhost")
	v.SetDefault("database.port", 5432)
	v.SetDefault("database.name", "livlog")
	v.SetDefault("database.user", "livlog")
	v.SetDefault("database.password", "livlog")
	v.SetDefault("database.sslmode", "disable")
	v.SetDefault("logging.format", "console")
	v.SetDefault("jwt.private_key_path", "./keys/private_key.pem")
	v.SetDefault("jwt.public_key_path", "./keys/public_key.pem")
	v.SetDefault("jwt.access_token_lifetime", 3600)
	v.SetDefault("jwt.refresh_token_lifetime", 2592000)
	v.SetDefault("jwt.issuer", "livlog-api")
	v.SetDefault("jwt.audience", "livlog-app")
	v.SetDefault("apple.bundle_id", "net.avalarin.livlog")
	v.SetDefault("openrouter.base_url", "https://openrouter.ai/api/v1/chat/completions")
	v.SetDefault("openrouter.model", "perplexity/sonar")
	v.SetDefault("ratelimit.ai_search_basic_limit", 5)
	v.SetDefault("ratelimit.ai_search_pro_limit", 50)
	v.SetDefault("ratelimit.ai_search_unlimited_limit", 0) // 0 means no limit
	v.SetDefault("ratelimit.ai_search_period", "24h")

	// Read config file
	if configPath != "" {
		v.SetConfigFile(configPath)
	} else {
		v.SetConfigName("config")
		v.SetConfigType("yaml")
		v.AddConfigPath(".")
		v.AddConfigPath("./config")
	}

	if err := v.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, fmt.Errorf("failed to read config file: %w", err)
		}
		// Config file not found, use defaults and env vars
	}

	// Enable environment variable override
	v.SetEnvPrefix("LIVLOG")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	return &cfg, nil
}
