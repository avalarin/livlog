package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"go.uber.org/zap"
)

type EmailSender struct {
	enabled     bool
	apiKey      string
	fromName    string
	fromAddress string
	baseURL     string
	httpClient  *http.Client
	log         *zap.Logger
}

func NewEmailSender(enabled bool, apiKey string, fromName string, fromAddress string, log *zap.Logger) *EmailSender {
	return &EmailSender{
		enabled:     enabled,
		apiKey:      apiKey,
		fromName:    fromName,
		fromAddress: fromAddress,
		baseURL:     "https://api.resend.com",
		httpClient:  &http.Client{Timeout: 10 * time.Second},
		log:         log,
	}
}

func (s *EmailSender) SendVerificationCode(ctx context.Context, email string, code string) error {
	if !s.enabled {
		s.log.Debug("email sending disabled, skipping", zap.String("email", email))
		return nil
	}

	return s.sendViaResend(ctx, email, code)
}

func (s *EmailSender) IsEnabled() bool {
	return s.enabled
}

func (s *EmailSender) sendViaResend(ctx context.Context, toEmail string, code string) error {
	from := s.fromAddress
	if s.fromName != "" {
		from = fmt.Sprintf("%s <%s>", s.fromName, s.fromAddress)
	}

	payload := map[string]interface{}{
		"from":    from,
		"to":      []string{toEmail},
		"subject": "Your Grove verification code",
		"text":    fmt.Sprintf("Your verification code is: %s\n\nThis code will expire in 5 minutes.\n\nIf you didn't request this code, you can safely ignore this email.", code),
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal email payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.baseURL+"/emails", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+s.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send email: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("resend API error: status %d", resp.StatusCode)
	}

	s.log.Info("verification email sent", zap.String("to", toEmail))
	return nil
}
