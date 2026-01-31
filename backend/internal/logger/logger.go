package logger

import (
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

func New(format string) (*zap.Logger, error) {
	var config zap.Config

	if format == "json" {
		config = zap.NewProductionConfig()
		config.EncoderConfig.TimeKey = "timestamp"
		config.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder
	} else {
		config = zap.NewDevelopmentConfig()
		config.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder
	}

	return config.Build()
}
