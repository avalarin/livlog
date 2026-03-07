package service

import (
	"strings"
	"testing"
)

func TestValidateIcon_ValidSystemIcons(t *testing.T) {
	validNames := []string{"folder", "movie", "bookmark", "music", "briefcase"}
	for _, name := range validNames {
		if err := validateIcon("system:" + name); err != nil {
			t.Errorf("expected system:%s to be valid, got %v", name, err)
		}
	}
}

func TestValidateIcon_InvalidSystemIcon(t *testing.T) {
	if err := validateIcon("system:unknown"); err != ErrInvalidIcon {
		t.Errorf("expected ErrInvalidIcon for system:unknown, got %v", err)
	}
}

func TestValidateIcon_ValidEmoji(t *testing.T) {
	cases := []string{"emoji:🎬", "emoji:📋", "emoji:🇦🇺", "emoji:👨‍👩‍👧"}
	for _, icon := range cases {
		if err := validateIcon(icon); err != nil {
			t.Errorf("expected %s to be valid, got %v", icon, err)
		}
	}
}

func TestValidateIcon_EmptyEmoji(t *testing.T) {
	if err := validateIcon("emoji:"); err != ErrInvalidIcon {
		t.Errorf("expected ErrInvalidIcon for empty emoji, got %v", err)
	}
}

func TestValidateIcon_InvalidPrefix(t *testing.T) {
	cases := []string{"foo:bar", "plain text", "📋", ""}
	for _, icon := range cases {
		if err := validateIcon(icon); err != ErrInvalidIcon {
			t.Errorf("expected ErrInvalidIcon for %q, got %v", icon, err)
		}
	}
}

func TestValidateIcon_TooLong(t *testing.T) {
	long := "system:" + strings.Repeat("x", 50)
	if err := validateIcon(long); err != ErrInvalidIcon {
		t.Errorf("expected ErrInvalidIcon for too-long icon, got %v", err)
	}
}

func TestValidateColor_ValidColors(t *testing.T) {
	colors := []string{"dodger-blue", "dusty-grape", "straw-gold", "rosewood",
		"coral-glow", "vibrant-coral", "vintage-grape", "yellow-green", "granite", "verdigris"}
	for _, c := range colors {
		if err := validateColor(c); err != nil {
			t.Errorf("expected %s to be valid, got %v", c, err)
		}
	}
}

func TestValidateColor_Invalid(t *testing.T) {
	cases := []string{"purple", "red", "", "blue"}
	for _, c := range cases {
		if err := validateColor(c); err != ErrInvalidColor {
			t.Errorf("expected ErrInvalidColor for %q, got %v", c, err)
		}
	}
}
