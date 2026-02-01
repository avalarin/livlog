package service

import (
	"sync"
	"time"
)

// RateLimiter provides in-memory rate limiting
// Thread-safe using RWMutex
type RateLimiter struct {
	mu       sync.RWMutex
	attempts map[string]time.Time
	window   time.Duration
}

// NewRateLimiter creates a new rate limiter with the specified time window
func NewRateLimiter(window time.Duration) *RateLimiter {
	return &RateLimiter{
		attempts: make(map[string]time.Time),
		window:   window,
	}
}

// Allow checks if the action is allowed for the given key
// Returns true if allowed, false if rate limited
func (r *RateLimiter) Allow(key string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	lastAttempt, exists := r.attempts[key]
	now := time.Now()

	if !exists || now.Sub(lastAttempt) >= r.window {
		r.attempts[key] = now
		return true
	}

	return false
}

// Reset removes the rate limit for the given key
func (r *RateLimiter) Reset(key string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.attempts, key)
}

// Cleanup removes expired entries from the rate limiter
// Should be called periodically to prevent memory leaks
func (r *RateLimiter) Cleanup() {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now()
	for key, lastAttempt := range r.attempts {
		if now.Sub(lastAttempt) >= r.window {
			delete(r.attempts, key)
		}
	}
}

// GetRetryAfter returns the number of seconds until the next allowed attempt
// Returns 0 if the action is allowed now
func (r *RateLimiter) GetRetryAfter(key string) int {
	r.mu.RLock()
	defer r.mu.RUnlock()

	lastAttempt, exists := r.attempts[key]
	if !exists {
		return 0
	}

	elapsed := time.Since(lastAttempt)
	if elapsed >= r.window {
		return 0
	}

	remaining := r.window - elapsed
	return int(remaining.Seconds()) + 1 // Round up
}
