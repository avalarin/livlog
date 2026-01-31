# Build stage
FROM golang:1.22-alpine3.19 AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Copy go mod files first for better caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /app/server \
    ./cmd/server

# Runtime stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata

# Create non-root user
RUN addgroup -S livlog && adduser -S livlog -G livlog

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/server .

# Copy migrations
COPY --from=builder /app/migrations ./migrations

# Copy config
COPY --from=builder /app/config.yaml .

# Set ownership
RUN chown -R livlog:livlog /app

# Switch to non-root user
USER livlog

# Expose HTTP port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8080/api/v1/health || exit 1

# Run the server
ENTRYPOINT ["/app/server"]
CMD ["-config", "/app/config.yaml", "-migrations", "/app/migrations"]
