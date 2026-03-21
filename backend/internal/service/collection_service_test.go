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

// --- CollectionService statistics tests ---
//
// NOTE: CollectionService takes a concrete *repository.CollectionRepository (not an interface),
// so it cannot be unit-tested with hand-rolled mocks without modifying production code.
//
// NewCollectionService signature:
//
//	func NewCollectionService(
//	    collectionRepo *repository.CollectionRepository,
//	    userRepo       *repository.UserRepository,
//	) *CollectionService
//
// Because both fields are concrete pointer types backed by a live database connection,
// there is no injection seam available for the statistics methods
// (GetCollectionStatistics, GetAvailableStatistics, UpdateStatisticsConfig).
//
// Recommended path forward (choose one):
//
//  1. Extract a CollectionRepository interface in the service package covering the methods
//     used by the statistics functions (GetUserRole, EnsureDefaultStatConfigs,
//     GetCollectionStatConfigs, GetStatisticDefinitions, GetCollectionStatValues,
//     RefreshCollectionStatValues, GetAvailableStatsForCollection, SetCollectionStatConfigs),
//     then change CollectionService to hold that interface. This is the standard Go pattern
//     and keeps production code clean.
//
//  2. Write integration tests against a real (test) database using testcontainers or a
//     local Postgres instance spun up by the test binary. The backend already uses pgx
//     directly, so a test helper that creates a *repository.CollectionRepository with a
//     test connection pool would cover all the same scenarios listed below.
//
// The 12 test scenarios that should be covered once a seam is available:
//
//  GetCollectionStatistics
//   - HappyPath_CacheHit:             cached values exist, returns stats in config order
//   - CacheMiss_TriggersRefresh:       empty cache, refresh called, returns stats
//   - AccessDenied:                    GetUserRole returns ErrCollectionNotFound
//   - MissingDefinition_Skipped:       config has stat ID not in definitions, row skipped
//   - MissingCacheValue_ShowsDash:     stat in config but not in cache values, shows "—"
//
//  GetAvailableStatistics
//   - EnabledAndDisabled:              enabled stats get their position, disabled get -1
//   - AccessDenied:                    GetUserRole returns ErrCollectionNotFound
//
//  UpdateStatisticsConfig
//   - OwnerCanUpdate:                  role "owner", succeeds
//   - WriterCanUpdate:                 role "write", succeeds
//   - ReadRoleForbidden:               role "read", returns ErrNotCollectionOwner
//   - UnknownStatID:                   unknown stat ID, returns error containing "unknown statistic id"
//   - EmptyStatIDs:                    empty slice, clears config successfully
