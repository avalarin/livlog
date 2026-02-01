package handler

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/avalarin/livlog/backend/internal/service"
	"github.com/go-chi/chi/v5"
)

type AuthHandler struct {
	authService      *service.AuthService
	emailAuthService *service.EmailAuthService
}

func NewAuthHandler(authService *service.AuthService, emailAuthService *service.EmailAuthService) *AuthHandler {
	return &AuthHandler{
		authService:      authService,
		emailAuthService: emailAuthService,
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
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	authResp, err := h.authService.AuthenticateWithApple(r.Context(), &req)
	if err != nil {
		if errors.Is(err, service.ErrInvalidToken) ||
			errors.Is(err, service.ErrInvalidIssuer) ||
			errors.Is(err, service.ErrInvalidAudience) {
			respondWithError(w, http.StatusUnauthorized, "Invalid Apple token", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to authenticate", err)
		return
	}

	respondWithJSON(w, http.StatusOK, authResp)
}

type refreshTokenRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *AuthHandler) RefreshToken(w http.ResponseWriter, r *http.Request) {
	var req refreshTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.RefreshToken == "" {
		respondWithError(w, http.StatusBadRequest, "Refresh token is required", nil)
		return
	}

	authResp, err := h.authService.RefreshToken(r.Context(), req.RefreshToken)
	if err != nil {
		if errors.Is(err, service.ErrInvalidCredentials) {
			respondWithError(w, http.StatusUnauthorized, "Invalid refresh token", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to refresh token", err)
		return
	}

	respondWithJSON(w, http.StatusOK, authResp)
}

type logoutRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	var req logoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.RefreshToken == "" {
		respondWithError(w, http.StatusBadRequest, "Refresh token is required", nil)
		return
	}

	if err := h.authService.Logout(r.Context(), req.RefreshToken); err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to logout", err)
		return
	}

	respondWithJSON(w, http.StatusOK, map[string]string{"message": "Logged out successfully"})
}

func (h *AuthHandler) GetMe(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	user, err := h.authService.GetUserByID(r.Context(), userID)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to get user", err)
		return
	}

	respondWithJSON(w, http.StatusOK, user)
}

func (h *AuthHandler) DeleteAccount(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	if err := h.authService.DeleteAccount(r.Context(), userID); err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to delete account", err)
		return
	}

	respondWithJSON(w, http.StatusOK, map[string]string{"message": "Account deleted successfully"})
}

// Email Authentication Handlers

type sendCodeRequest struct {
	Email string `json:"email"`
}

type sendCodeResponse struct {
	Message   string `json:"message"`
	ExpiresIn int    `json:"expires_in"`
}

func (h *AuthHandler) SendVerificationCode(w http.ResponseWriter, r *http.Request) {
	var req sendCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.Email == "" {
		respondWithError(w, http.StatusBadRequest, "Email is required", nil)
		return
	}

	if err := h.emailAuthService.SendVerificationCode(r.Context(), req.Email); err != nil {
		if errors.Is(err, service.ErrInvalidEmail) {
			respondWithError(w, http.StatusBadRequest, "Invalid email format", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to send verification code", err)
		return
	}

	respondWithJSON(w, http.StatusOK, sendCodeResponse{
		Message:   "Verification code sent",
		ExpiresIn: int(service.VerificationCodeExpiry.Seconds()),
	})
}

type resendCodeRequest struct {
	Email string `json:"email"`
}

func (h *AuthHandler) ResendVerificationCode(w http.ResponseWriter, r *http.Request) {
	var req resendCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.Email == "" {
		respondWithError(w, http.StatusBadRequest, "Email is required", nil)
		return
	}

	if err := h.emailAuthService.ResendVerificationCode(r.Context(), req.Email); err != nil {
		if errors.Is(err, service.ErrInvalidEmail) {
			respondWithError(w, http.StatusBadRequest, "Invalid email format", err)
			return
		}
		if errors.Is(err, service.ErrRateLimitExceeded) {
			retryAfter := h.emailAuthService.GetRetryAfter(req.Email)
			w.Header().Set("Retry-After", http.StatusText(retryAfter))

			type rateLimitError struct {
				Error   string         `json:"error"`
				Message string         `json:"message"`
				Details map[string]int `json:"details"`
			}

			resp := rateLimitError{
				Error:   "RATE_LIMIT_EXCEEDED",
				Message: "Please wait before requesting another code",
				Details: map[string]int{"retry_after": retryAfter},
			}

			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)
			json.NewEncoder(w).Encode(resp)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to resend verification code", err)
		return
	}

	respondWithJSON(w, http.StatusOK, sendCodeResponse{
		Message:   "Verification code resent",
		ExpiresIn: int(service.VerificationCodeExpiry.Seconds()),
	})
}

type verifyCodeRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

func (h *AuthHandler) VerifyEmailCode(w http.ResponseWriter, r *http.Request) {
	var req verifyCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.Email == "" {
		respondWithError(w, http.StatusBadRequest, "Email is required", nil)
		return
	}

	if req.Code == "" {
		respondWithError(w, http.StatusBadRequest, "Verification code is required", nil)
		return
	}

	authResp, err := h.emailAuthService.VerifyCode(r.Context(), req.Email, req.Code)
	if err != nil {
		if errors.Is(err, service.ErrInvalidEmail) {
			respondWithError(w, http.StatusBadRequest, "Invalid email format", err)
			return
		}
		if errors.Is(err, service.ErrInvalidCode) ||
			errors.Is(err, service.ErrCodeExpired) ||
			errors.Is(err, service.ErrCodeAlreadyUsed) {
			respondWithError(w, http.StatusUnauthorized, "Verification code is invalid or expired", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to verify code", err)
		return
	}

	respondWithJSON(w, http.StatusOK, authResp)
}

// Helper functions

type errorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

func respondWithError(w http.ResponseWriter, code int, message string, err error) {
	resp := errorResponse{
		Error:   http.StatusText(code),
		Message: message,
	}

	// Log the actual error internally (in production, use proper logger)
	if err != nil {
		// log.Printf("Error: %v", err)
		_ = err
	}

	respondWithJSON(w, code, resp)
}

func respondWithJSON(w http.ResponseWriter, code int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)

	if payload != nil {
		if err := json.NewEncoder(w).Encode(payload); err != nil {
			// log.Printf("Error encoding JSON: %v", err)
			_ = err
		}
	}
}

func getUserIDFromContext(ctx context.Context) string {
	userID, ok := ctx.Value("userID").(string)
	if !ok {
		return ""
	}
	return userID
}
