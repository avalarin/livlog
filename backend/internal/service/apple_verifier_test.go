package service

import (
	"encoding/json"
	"testing"
)

func TestAppleBool_UnmarshalJSON_BoolTrue(t *testing.T) {
	var b appleBool
	if err := json.Unmarshal([]byte(`true`), &b); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !bool(b) {
		t.Error("expected true, got false")
	}
}

func TestAppleBool_UnmarshalJSON_BoolFalse(t *testing.T) {
	var b appleBool
	if err := json.Unmarshal([]byte(`false`), &b); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if bool(b) {
		t.Error("expected false, got true")
	}
}

func TestAppleBool_UnmarshalJSON_StringTrue(t *testing.T) {
	var b appleBool
	if err := json.Unmarshal([]byte(`"true"`), &b); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !bool(b) {
		t.Error("expected true, got false")
	}
}

func TestAppleBool_UnmarshalJSON_StringFalse(t *testing.T) {
	var b appleBool
	if err := json.Unmarshal([]byte(`"false"`), &b); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if bool(b) {
		t.Error("expected false, got true")
	}
}

func TestAppleBool_UnmarshalJSON_InvalidNumber(t *testing.T) {
	var b appleBool
	err := json.Unmarshal([]byte(`123`), &b)
	if err == nil {
		t.Fatal("expected error for invalid input, got nil")
	}
}

func TestAppleBool_UnmarshalJSON_InvalidString(t *testing.T) {
	var b appleBool
	// Unrecognized string value (not "true") — treated as false, no error
	if err := json.Unmarshal([]byte(`"abc"`), &b); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if bool(b) {
		t.Error("expected false for non-'true' string, got true")
	}
}

func TestAppleBool_InStruct(t *testing.T) {
	type testClaims struct {
		EmailVerified  appleBool `json:"email_verified"`
		IsPrivateEmail appleBool `json:"is_private_email"`
	}

	// Mixed: bool + string
	input := `{"email_verified": true, "is_private_email": "false"}`
	var claims testClaims
	if err := json.Unmarshal([]byte(input), &claims); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !bool(claims.EmailVerified) {
		t.Error("expected email_verified=true")
	}
	if bool(claims.IsPrivateEmail) {
		t.Error("expected is_private_email=false")
	}
}
