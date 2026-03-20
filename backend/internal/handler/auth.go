package handler

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"go.uber.org/zap"

	"github.com/avalarin/livlog/backend/internal/service"
)

type AuthHandler struct {
	authService      *service.AuthService
	emailAuthService *service.EmailAuthService
	log              *zap.Logger
}

func NewAuthHandler(authService *service.AuthService, emailAuthService *service.EmailAuthService, log *zap.Logger) *AuthHandler {
	return &AuthHandler{
		authService:      authService,
		emailAuthService: emailAuthService,
		log:              log,
	}
}

func (h *AuthHandler) RegisterRoutes(r chi.Router) {
	r.Post("/auth/apple", h.AppleAuth)
	r.Post("/auth/email/send-code", h.SendVerificationCode)
	r.Post("/auth/email/resend-code", h.ResendVerificationCode)
	r.Post("/auth/email/verify", h.VerifyEmailCode)
	r.Post("/auth/refresh", h.RefreshToken)
	r.Post("/auth/logout", h.Logout)
	r.Get("/auth/me", h.GetMe)
	r.Delete("/auth/account", h.DeleteAccount)
}

func (h *AuthHandler) AppleAuth(w http.ResponseWriter, r *http.Request) {
	var req service.AppleAuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	authResp, err := h.authService.AuthenticateWithApple(r.Context(), &req)
	if err != nil {
		if errors.Is(err, service.ErrInvalidToken) ||
			errors.Is(err, service.ErrInvalidIssuer) ||
			errors.Is(err, service.ErrInvalidAudience) ||
			errors.Is(err, service.ErrTokenExpired) {
			respondWithError(h.log, w, http.StatusUnauthorized, "Invalid Apple token", err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to authenticate", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, authResp)
}

type refreshTokenRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *AuthHandler) RefreshToken(w http.ResponseWriter, r *http.Request) {
	var req refreshTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.RefreshToken == "" {
		respondWithError(h.log, w, http.StatusBadRequest, "Refresh token is required", nil)
		return
	}

	authResp, err := h.authService.RefreshToken(r.Context(), req.RefreshToken)
	if err != nil {
		if errors.Is(err, service.ErrInvalidCredentials) {
			respondWithError(h.log, w, http.StatusUnauthorized, "Invalid refresh token", err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to refresh token", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, authResp)
}

type logoutRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	var req logoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.RefreshToken == "" {
		respondWithError(h.log, w, http.StatusBadRequest, "Refresh token is required", nil)
		return
	}

	if err := h.authService.Logout(r.Context(), req.RefreshToken); err != nil {
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to logout", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, map[string]string{"message": "Logged out successfully"})
}

func (h *AuthHandler) GetMe(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	user, err := h.authService.GetUserByID(r.Context(), userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to get user", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, user)
}

func (h *AuthHandler) DeleteAccount(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	if err := h.authService.DeleteAccount(r.Context(), userID); err != nil {
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to delete account", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, map[string]string{"message": "Account deleted successfully"})
}

// Email Authentication Handlers

type sendCodeRequest struct {
	Email    string `json:"email"`
	DeviceID string `json:"device_id"`
}

type sendCodeResponse struct {
	Message        string `json:"message"`
	ExpiresIn      int    `json:"expires_in"`
	ResendCooldown int    `json:"resend_cooldown"`
}

type rateLimitErrorResponse struct {
	Error   string         `json:"error"`
	Message string         `json:"message"`
	Details map[string]int `json:"details"`
}

func (h *AuthHandler) SendVerificationCode(w http.ResponseWriter, r *http.Request) {
	var req sendCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.Email == "" {
		respondWithError(h.log, w, http.StatusBadRequest, "Email is required", nil)
		return
	}

	if err := h.emailAuthService.SendVerificationCode(r.Context(), req.Email, req.DeviceID, getClientIP(r)); err != nil {
		if errors.Is(err, service.ErrInvalidEmail) {
			respondWithError(h.log, w, http.StatusBadRequest, "Invalid email format", err)
			return
		}
		if errors.Is(err, service.ErrRateLimitExceeded) {
			retryAfter := h.emailAuthService.GetResendCooldown()
			w.Header().Set("Retry-After", strconv.Itoa(retryAfter))
			respondWithJSON(h.log, w, http.StatusTooManyRequests, rateLimitErrorResponse{
				Error:   "RATE_LIMIT_EXCEEDED",
				Message: "Please wait before requesting another code",
				Details: map[string]int{"retry_after": retryAfter},
			})
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to send verification code", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, sendCodeResponse{
		Message:        "Verification code sent",
		ExpiresIn:      int(service.VerificationCodeExpiry.Seconds()),
		ResendCooldown: h.emailAuthService.GetResendCooldown(),
	})
}

type resendCodeRequest struct {
	Email    string `json:"email"`
	DeviceID string `json:"device_id"`
}

func (h *AuthHandler) ResendVerificationCode(w http.ResponseWriter, r *http.Request) {
	var req resendCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.Email == "" {
		respondWithError(h.log, w, http.StatusBadRequest, "Email is required", nil)
		return
	}

	if err := h.emailAuthService.ResendVerificationCode(r.Context(), req.Email, req.DeviceID, getClientIP(r)); err != nil {
		if errors.Is(err, service.ErrInvalidEmail) {
			respondWithError(h.log, w, http.StatusBadRequest, "Invalid email format", err)
			return
		}
		if errors.Is(err, service.ErrRateLimitExceeded) {
			retryAfter := h.emailAuthService.GetResendCooldown()
			w.Header().Set("Retry-After", strconv.Itoa(retryAfter))
			respondWithJSON(h.log, w, http.StatusTooManyRequests, rateLimitErrorResponse{
				Error:   "RATE_LIMIT_EXCEEDED",
				Message: "Please wait before requesting another code",
				Details: map[string]int{"retry_after": retryAfter},
			})
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to resend verification code", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, sendCodeResponse{
		Message:        "Verification code resent",
		ExpiresIn:      int(service.VerificationCodeExpiry.Seconds()),
		ResendCooldown: h.emailAuthService.GetResendCooldown(),
	})
}

type verifyCodeRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

func (h *AuthHandler) VerifyEmailCode(w http.ResponseWriter, r *http.Request) {
	var req verifyCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.Email == "" {
		respondWithError(h.log, w, http.StatusBadRequest, "Email is required", nil)
		return
	}

	if req.Code == "" {
		respondWithError(h.log, w, http.StatusBadRequest, "Verification code is required", nil)
		return
	}

	authResp, err := h.emailAuthService.VerifyCode(r.Context(), req.Email, req.Code)
	if err != nil {
		if errors.Is(err, service.ErrInvalidEmail) {
			respondWithError(h.log, w, http.StatusBadRequest, "Invalid email format", err)
			return
		}
		if errors.Is(err, service.ErrInvalidCode) ||
			errors.Is(err, service.ErrCodeExpired) ||
			errors.Is(err, service.ErrCodeAlreadyUsed) {
			respondWithError(h.log, w, http.StatusUnauthorized, "Verification code is invalid or expired", err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to verify code", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, authResp)
}

// Helper functions

type errorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

func respondWithError(log *zap.Logger, w http.ResponseWriter, code int, message string, err error) {
	if code == http.StatusInternalServerError && err != nil && errors.Is(err, context.Canceled) {
		respondWithJSON(log, w, http.StatusServiceUnavailable,
			errorResponse{Error: http.StatusText(http.StatusServiceUnavailable), Message: "request canceled by client"})
		return
	}
	if code == http.StatusInternalServerError && err != nil && errors.Is(err, context.DeadlineExceeded) {
		respondWithJSON(log, w, http.StatusGatewayTimeout,
			errorResponse{Error: http.StatusText(http.StatusGatewayTimeout), Message: "request timed out"})
		return
	}

	if code >= 500 && err != nil {
		log.Error("unhandled error",
			zap.Int("status", code),
			zap.String("message", message),
			zap.Error(err),
		)
	}

	resp := errorResponse{
		Error:   http.StatusText(code),
		Message: message,
	}

	respondWithJSON(log, w, code, resp)
}

func getClientIP(r *http.Request) string {
	// chi's RealIP middleware sets RemoteAddr to the real IP,
	// but it may still include a port suffix
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func respondWithJSON(log *zap.Logger, w http.ResponseWriter, code int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)

	if payload != nil {
		if err := json.NewEncoder(w).Encode(payload); err != nil {
			log.Error("failed to encode JSON response", zap.Int("status", code), zap.Error(err))
		}
	}
}
