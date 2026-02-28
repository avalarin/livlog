package handler

import (
	"context"

	"github.com/avalarin/livlog/backend/internal/middleware"
)

func getUserIDFromContext(ctx context.Context) string {
	return middleware.GetUserIDFromContext(ctx)
}
