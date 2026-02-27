package middleware

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/avalarin/livlog/backend/internal/service"
)

// contextKey is an unexported type for context keys in this package.
type contextKey string

// UserIDContextKey is the context key for storing the authenticated user's ID.
const UserIDContextKey contextKey = "userID"

func AuthMiddleware(jwtService *service.JWTService) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Extract Authorization header
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				respondUnauthorized(w, "Authorization header required")
				return
			}

			// Extract Bearer token
			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) != 2 || parts[0] != "Bearer" {
				respondUnauthorized(w, "Invalid authorization header format")
				return
			}

			token := parts[1]

			// Validate token
			claims, err := jwtService.ValidateAccessToken(token)
			if err != nil {
				respondUnauthorized(w, "Invalid or expired token")
				return
			}

			// Add user ID to context
			ctx := context.WithValue(r.Context(), UserIDContextKey, claims.UserID)

			// Call next handler
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func GetUserIDFromContext(ctx context.Context) string {
	userID, ok := ctx.Value(UserIDContextKey).(string)
	if !ok {
		return ""
	}
	return userID
}

type errorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

func respondUnauthorized(w http.ResponseWriter, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)

	resp := errorResponse{
		Error:   "Unauthorized",
		Message: message,
	}

	_ = json.NewEncoder(w).Encode(resp)
}
