package service

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"go.uber.org/zap"
)

func newTestEmailSender(enabled bool, apiKey, fromName, fromAddress string) *EmailSender {
	log, _ := zap.NewDevelopment()
	s := NewEmailSender(enabled, apiKey, fromName, fromAddress, log)
	return s
}

func TestEmailSender_SendVerificationCode_Success(t *testing.T) {
	var capturedMethod, capturedAuth, capturedContentType string
	var capturedBody map[string]interface{}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedMethod = r.Method
		capturedAuth = r.Header.Get("Authorization")
		capturedContentType = r.Header.Get("Content-Type")

		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("failed to read request body: %v", err)
			return
		}
		if err := json.Unmarshal(body, &capturedBody); err != nil {
			t.Errorf("failed to unmarshal request body: %v", err)
			return
		}

		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	s := newTestEmailSender(true, "test-api-key", "", "sender@example.com")
	s.baseURL = server.URL

	err := s.SendVerificationCode(context.Background(), "recipient@example.com", "123456")
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	if capturedMethod != http.MethodPost {
		t.Errorf("expected POST, got %q", capturedMethod)
	}
	if capturedAuth != "Bearer test-api-key" {
		t.Errorf("unexpected Authorization header: %q", capturedAuth)
	}
	if capturedContentType != "application/json" {
		t.Errorf("unexpected Content-Type: %q", capturedContentType)
	}
	if capturedBody["from"] != "sender@example.com" {
		t.Errorf("unexpected from: %v", capturedBody["from"])
	}
	toSlice, ok := capturedBody["to"].([]interface{})
	if !ok || len(toSlice) == 0 || toSlice[0] != "recipient@example.com" {
		t.Errorf("unexpected to: %v", capturedBody["to"])
	}
}

func TestEmailSender_SendVerificationCode_Disabled(t *testing.T) {
	requestMade := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestMade = true
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	s := newTestEmailSender(false, "test-api-key", "", "sender@example.com")
	s.baseURL = server.URL

	err := s.SendVerificationCode(context.Background(), "recipient@example.com", "123456")
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
	if requestMade {
		t.Error("expected no HTTP request when sender is disabled")
	}
}

func TestEmailSender_SendVerificationCode_APIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
	}))
	defer server.Close()

	s := newTestEmailSender(true, "bad-key", "", "sender@example.com")
	s.baseURL = server.URL

	err := s.SendVerificationCode(context.Background(), "recipient@example.com", "123456")
	if err == nil {
		t.Fatal("expected error for 400 response, got nil")
	}
}

func TestEmailSender_SendVerificationCode_FormatsFromWithName(t *testing.T) {
	var capturedFrom string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("failed to read request body: %v", err)
			return
		}
		var payload map[string]interface{}
		if err := json.Unmarshal(body, &payload); err != nil {
			t.Errorf("failed to unmarshal request body: %v", err)
			return
		}
		capturedFrom, _ = payload["from"].(string)
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	s := newTestEmailSender(true, "test-api-key", "MyApp", "sender@example.com")
	s.baseURL = server.URL

	err := s.SendVerificationCode(context.Background(), "recipient@example.com", "123456")
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	expected := "MyApp <sender@example.com>"
	if capturedFrom != expected {
		t.Errorf("expected from %q, got %q", expected, capturedFrom)
	}
}
