package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/avalarin/livlog/backend/internal/config"
	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

var (
	ErrAISearchRateLimitExceeded = errors.New("AI search rate limit exceeded")
)

type AISearchService struct {
	cfg        *config.Config
	usageRepo  *repository.AISearchUsageRepository
	userRepo   *repository.UserRepository
	httpClient *http.Client
	ratePeriod time.Duration
	logger     *zap.Logger
}

type SearchOption struct {
	ID          string   `json:"id"`
	Title       string   `json:"title"`
	EntryType   string   `json:"entryType"`
	Year        string   `json:"year,omitempty"`
	Genre       string   `json:"genre,omitempty"`
	Author      string   `json:"author,omitempty"`
	Platform    string   `json:"platform,omitempty"`
	Description string   `json:"description"`
	ImageURLs   []string `json:"imageUrls"`
}

// DTO for parsing OpenRouter response
type searchOptionDTO struct {
	Title       string   `json:"title"`
	EntryType   string   `json:"entryType"`
	Year        string   `json:"year,omitempty"`
	Genre       string   `json:"genre,omitempty"`
	Author      string   `json:"author,omitempty"`
	Platform    string   `json:"platform,omitempty"`
	Description string   `json:"description"`
	ImageURLs   []string `json:"imageUrls,omitempty"`
}

type optionsResponseDTO struct {
	Options []searchOptionDTO `json:"options"`
}

// OpenRouter API response structure (OpenAI-compatible)
type chatCompletionResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

func NewAISearchService(
	cfg *config.Config,
	usageRepo *repository.AISearchUsageRepository,
	userRepo *repository.UserRepository,
	logger *zap.Logger,
) (*AISearchService, error) {
	// Parse rate limit period
	period, err := time.ParseDuration(cfg.RateLimit.AISearchPeriod)
	if err != nil {
		return nil, fmt.Errorf("invalid ai_search_period: %w", err)
	}

	return &AISearchService{
		cfg:        cfg,
		usageRepo:  usageRepo,
		userRepo:   userRepo,
		httpClient: &http.Client{Timeout: 30 * time.Second},
		ratePeriod: period,
		logger:     logger,
	}, nil
}

// SearchOptions performs AI search and returns options with downloaded images
func (s *AISearchService) SearchOptions(ctx context.Context, userID uuid.UUID, query string) ([]SearchOption, error) {
	s.logger.Info("starting AI search",
		zap.String("user_id", userID.String()),
		zap.String("query", query),
	)

	// Get user to check their AI usage policy
	user, err := s.userRepo.GetUserByID(ctx, userID)
	if err != nil {
		s.logger.Error("failed to get user",
			zap.String("user_id", userID.String()),
			zap.Error(err),
		)
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	s.logger.Info("user AI usage policy",
		zap.String("user_id", userID.String()),
		zap.String("policy", string(user.AIUsagePolicy)),
	)

	// Get the rate limit for the user's policy
	limit := s.cfg.RateLimit.GetAISearchLimit(string(user.AIUsagePolicy))

	// Check rate limit (skip if limit is 0 - unlimited)
	if limit > 0 {
		err := s.usageRepo.CheckAndIncrementUsage(
			ctx,
			userID,
			limit,
			s.ratePeriod,
		)
		if err != nil {
			if errors.Is(err, repository.ErrRateLimitExceeded) {
				s.logger.Warn("rate limit exceeded",
					zap.String("user_id", userID.String()),
					zap.String("policy", string(user.AIUsagePolicy)),
					zap.Int("limit", limit),
				)
				return nil, ErrAISearchRateLimitExceeded
			}
			s.logger.Error("failed to check rate limit",
				zap.String("user_id", userID.String()),
				zap.Error(err),
			)
			return nil, fmt.Errorf("failed to check rate limit: %w", err)
		}
	} else {
		s.logger.Info("unlimited policy - skipping rate limit check",
			zap.String("user_id", userID.String()),
		)
	}

	// Call OpenRouter API
	options, err := s.callOpenRouterAPI(ctx, query)
	if err != nil {
		s.logger.Error("failed to call OpenRouter API",
			zap.String("query", query),
			zap.Error(err),
		)
		return nil, fmt.Errorf("failed to call OpenRouter API: %w", err)
	}

	s.logger.Info("AI search completed",
		zap.String("user_id", userID.String()),
		zap.Int("results_count", len(options)),
	)

	// Download images for each option
	var results []SearchOption
	for _, option := range options {
		result := SearchOption{
			ID:          uuid.New().String(),
			Title:       option.Title,
			EntryType:   option.EntryType,
			Year:        option.Year,
			Genre:       option.Genre,
			Author:      option.Author,
			Platform:    option.Platform,
			Description: option.Description,
			ImageURLs:   []string{},
		}

		// Download images (up to 3)
		imageURLs := option.ImageURLs
		if len(imageURLs) > 3 {
			imageURLs = imageURLs[:3]
		}

		for _, imageURL := range imageURLs {
			// Try to download the image
			if s.isValidImageURL(imageURL) {
				result.ImageURLs = append(result.ImageURLs, imageURL)
			}
		}

		results = append(results, result)
	}

	return results, nil
}

// callOpenRouterAPI calls the OpenRouter API and returns search options
func (s *AISearchService) callOpenRouterAPI(ctx context.Context, query string) ([]searchOptionDTO, error) {
	prompt := fmt.Sprintf(`User is searching for: "%s"

Search and find what this might be. It could be a movie, book, game, or something else.
Return up to 5 most relevant options as JSON array.

For each option provide:
- title: the exact title
- entryType: one of "movie", "book", "game", or "custom"
- year: release/publication year (if applicable)
- genre: genre(s)
- author: author name (for books only, null otherwise)
- platform: gaming platform (for games only, null otherwise)
- description: brief 1-2 sentence description
- imageUrls: array of up to 3 image URLs (posters, covers, screenshots) - direct links to images

Return ONLY valid JSON in this exact format, no markdown, no extra text:
{"options": [{"title": "...", "entryType": "...", "year": "...", "genre": "...", "author": null, "platform": null, "description": "...", "imageUrls": ["url1", "url2"]}]}`, query)

	requestBody := map[string]interface{}{
		"model": s.cfg.OpenRouter.Model,
		"messages": []map[string]string{
			{
				"role":    "user",
				"content": prompt,
			},
		},
	}

	bodyBytes, err := json.Marshal(requestBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", s.cfg.OpenRouter.BaseURL, bytes.NewBuffer(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", s.cfg.OpenRouter.APIKey))
	req.Header.Set("X-Title", "livlogios")

	s.logger.Info("calling OpenRouter API",
		zap.String("url", s.cfg.OpenRouter.BaseURL),
		zap.String("model", s.cfg.OpenRouter.Model),
		zap.String("query", query),
	)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		s.logger.Error("OpenRouter API request failed",
			zap.Error(err),
		)
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	s.logger.Info("OpenRouter API response received",
		zap.Int("status_code", resp.StatusCode),
	)

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		bodyStr := string(body)
		s.logger.Error("OpenRouter API returned error",
			zap.Int("status_code", resp.StatusCode),
			zap.String("response_body", bodyStr),
		)
		return nil, fmt.Errorf("OpenRouter API error (status %d): %s", resp.StatusCode, bodyStr)
	}

	var chatResp chatCompletionResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		s.logger.Error("failed to decode OpenRouter response",
			zap.Error(err),
		)
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if len(chatResp.Choices) == 0 || chatResp.Choices[0].Message.Content == "" {
		s.logger.Error("OpenRouter response has no content")
		return nil, fmt.Errorf("no content in OpenRouter response")
	}

	// Parse the JSON from the text (remove markdown code blocks if present)
	content := chatResp.Choices[0].Message.Content
	s.logger.Debug("OpenRouter response content",
		zap.String("content", content),
	)

	cleanedText := strings.ReplaceAll(content, "```json", "")
	cleanedText = strings.ReplaceAll(cleanedText, "```", "")
	cleanedText = strings.TrimSpace(cleanedText)

	var optionsResp optionsResponseDTO
	if err := json.Unmarshal([]byte(cleanedText), &optionsResp); err != nil {
		s.logger.Error("failed to parse options JSON",
			zap.Error(err),
			zap.String("cleaned_text", cleanedText),
		)
		return nil, fmt.Errorf("failed to parse options JSON: %w", err)
	}

	s.logger.Info("successfully parsed OpenRouter response",
		zap.Int("options_count", len(optionsResp.Options)),
	)

	return optionsResp.Options, nil
}

// isValidImageURL performs basic validation on image URLs
func (s *AISearchService) isValidImageURL(url string) bool {
	if url == "" {
		return false
	}
	// Basic URL validation
	return strings.HasPrefix(url, "http://") || strings.HasPrefix(url, "https://")
}
