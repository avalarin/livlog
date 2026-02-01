package service

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var (
	ErrInvalidToken      = errors.New("invalid token")
	ErrTokenExpired      = errors.New("token expired")
	ErrInvalidIssuer     = errors.New("invalid issuer")
	ErrInvalidAudience   = errors.New("invalid audience")
	ErrAppleKeysNotFound = errors.New("apple public keys not found")
)

const appleKeysURL = "https://appleid.apple.com/auth/keys"

type AppleTokenClaims struct {
	Sub            string `json:"sub"`
	Email          string `json:"email"`
	EmailVerified  bool   `json:"email_verified"`
	IsPrivateEmail bool   `json:"is_private_email"`
	jwt.RegisteredClaims
}

type AppleVerifier struct {
	bundleID string
	keys     map[string]*rsa.PublicKey
	client   *http.Client
}

type appleJWKS struct {
	Keys []appleJWK `json:"keys"`
}

type appleJWK struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

func NewAppleVerifier(bundleID string) *AppleVerifier {
	return &AppleVerifier{
		bundleID: bundleID,
		keys:     make(map[string]*rsa.PublicKey),
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

func (v *AppleVerifier) VerifyIdentityToken(identityToken string) (*AppleTokenClaims, error) {
	// Parse token to get kid
	token, err := jwt.ParseWithClaims(identityToken, &AppleTokenClaims{}, func(token *jwt.Token) (interface{}, error) {
		// Validate signing method
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}

		// Get kid from header
		kid, ok := token.Header["kid"].(string)
		if !ok {
			return nil, errors.New("kid not found in token header")
		}

		// Get or fetch Apple public key
		publicKey, err := v.getPublicKey(kid)
		if err != nil {
			return nil, err
		}

		return publicKey, nil
	})

	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, ErrTokenExpired
		}
		return nil, fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}

	claims, ok := token.Claims.(*AppleTokenClaims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	// Verify issuer
	if claims.Issuer != "https://appleid.apple.com" {
		return nil, ErrInvalidIssuer
	}

	// Verify audience (bundle ID)
	if claims.Audience[0] != v.bundleID {
		return nil, ErrInvalidAudience
	}

	return claims, nil
}

func (v *AppleVerifier) getPublicKey(kid string) (*rsa.PublicKey, error) {
	// Check cache
	if key, exists := v.keys[kid]; exists {
		return key, nil
	}

	// Fetch keys from Apple
	if err := v.fetchAppleKeys(); err != nil {
		return nil, err
	}

	// Check cache again
	key, exists := v.keys[kid]
	if !exists {
		return nil, ErrAppleKeysNotFound
	}

	return key, nil
}

func (v *AppleVerifier) fetchAppleKeys() error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, appleKeysURL, nil)
	if err != nil {
		return err
	}

	resp, err := v.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to fetch Apple keys: status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	var jwks appleJWKS
	if err := json.Unmarshal(body, &jwks); err != nil {
		return err
	}

	// Convert JWKs to RSA public keys
	for _, key := range jwks.Keys {
		if key.Kty != "RSA" {
			continue
		}

		nBytes, err := base64.RawURLEncoding.DecodeString(key.N)
		if err != nil {
			continue
		}

		eBytes, err := base64.RawURLEncoding.DecodeString(key.E)
		if err != nil {
			continue
		}

		n := new(big.Int).SetBytes(nBytes)
		e := 0
		for _, b := range eBytes {
			e = e<<8 + int(b)
		}

		publicKey := &rsa.PublicKey{
			N: n,
			E: e,
		}

		v.keys[key.Kid] = publicKey
	}

	return nil
}
