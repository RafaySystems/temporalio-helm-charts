package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/coreos/go-oidc"
	"github.com/gorilla/mux"
)

const (
	RSIDHeader          = "rsid"
	AuthorizationHeader = "Authorization"
	XRAFAYHeader        = "X-RAFAY"
)

// Configuration holds the proxy configuration
type Config struct {
	Port                   string
	TemporalFrontendURL    string
	OIDCIssuer             string
	OIDCClientID           string
	LogLevel               string
	EnableCORS             bool
	RequestTimeout         time.Duration
	TokenValidationTimeout time.Duration
}

// Proxy represents the HTTP proxy
type Proxy struct {
	config *Config
	//verifier   *oidc.IDTokenVerifier
	httpClient *http.Client
	router     *mux.Router
	OIDCIssuer string
}

// Response represents a standard API response
type Response struct {
	Success bool        `json:"success"`
	Message string      `json:"message,omitempty"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

// TokenClaims represents the JWT token claims
type TokenClaims struct {
	Issuer   string   `json:"iss"`
	Subject  string   `json:"sub"`
	Audience []string `json:"aud"`
	Groups   []string `json:"groups,omitempty"`
	Email    string   `json:"email,omitempty"`
	Name     string   `json:"name,omitempty"`
}

func main() {
	config := loadConfig()

	// Create HTTP client with timeout
	httpClient := &http.Client{
		Timeout: config.RequestTimeout,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: false, // Set to true for self-signed certs in dev
			},
		},
	}

	// Create proxy
	proxy := &Proxy{
		config: config,
		//verifier:   verifier,
		httpClient: httpClient,
		router:     mux.NewRouter(),
		OIDCIssuer: config.OIDCIssuer,
	}

	// Setup routes
	proxy.setupRoutes()

	// Start server
	log.Printf("🚀 Temporal Frontend Proxy starting on port %s", config.Port)
	log.Printf("📡 Forwarding to: %s", config.TemporalFrontendURL)
	log.Printf("🔐 OIDC Issuer: %s", config.OIDCIssuer)
	log.Printf("🆔 OIDC Client ID: %s", config.OIDCClientID)

	server := &http.Server{
		Addr:         ":" + config.Port,
		Handler:      proxy.router,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	log.Fatal(server.ListenAndServe())
}

// loadConfig loads configuration from environment variables
func loadConfig() *Config {
	port := getEnv("PORT", "8081")
	temporalURL := getEnv("TEMPORAL_FRONTEND_URL", "http://temporalio-frontend.rafay-core.svc.cluster.local:7233")
	oidcIssuer := getEnv("OIDC_ISSUER", "https://console.gaap.dev.rafay-edge.net/dex")
	oidcClientID := getEnv("OIDC_CLIENT_ID", "temporal-server")
	logLevel := getEnv("LOG_LEVEL", "info")
	enableCORS := getEnv("ENABLE_CORS", "true") == "true"

	requestTimeout, err := time.ParseDuration(getEnv("REQUEST_TIMEOUT", "30s"))
	if err != nil {
		requestTimeout = 30 * time.Second
	}

	tokenTimeout, err := time.ParseDuration(getEnv("TOKEN_VALIDATION_TIMEOUT", "5s"))
	if err != nil {
		tokenTimeout = 5 * time.Second
	}

	return &Config{
		Port:                   port,
		TemporalFrontendURL:    temporalURL,
		OIDCIssuer:             oidcIssuer,
		OIDCClientID:           oidcClientID,
		LogLevel:               logLevel,
		EnableCORS:             enableCORS,
		RequestTimeout:         requestTimeout,
		TokenValidationTimeout: tokenTimeout,
	}
}

// setupRoutes configures the HTTP routes
func (p *Proxy) setupRoutes() {
	// Health check endpoint
	p.router.HandleFunc("/health", p.healthHandler).Methods("GET")

	// OIDC discovery endpoint
	p.router.HandleFunc("/.well-known/openid_configuration", p.oidcDiscoveryHandler).Methods("GET")

	// Proxy all other requests
	p.router.PathPrefix("/").HandlerFunc(p.proxyHandler)
}

// healthHandler handles health check requests
func (p *Proxy) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	response := Response{
		Success: true,
		Message: "Temporal Frontend Proxy is healthy",
		Data: map[string]interface{}{
			"timestamp": time.Now().UTC(),
			"version":   "1.0.0",
			"config": map[string]interface{}{
				"temporal_frontend_url": p.config.TemporalFrontendURL,
				"oidc_issuer":           p.config.OIDCIssuer,
				"oidc_client_id":        p.config.OIDCClientID,
			},
		},
	}

	json.NewEncoder(w).Encode(response)
}

// oidcDiscoveryHandler forwards OIDC discovery requests to the issuer
func (p *Proxy) oidcDiscoveryHandler(w http.ResponseWriter, r *http.Request) {
	discoveryURL := p.config.OIDCIssuer + "/.well-known/openid_configuration"

	resp, err := p.httpClient.Get(discoveryURL)
	if err != nil {
		log.Printf("Error fetching OIDC discovery: %v", err)
		http.Error(w, "Failed to fetch OIDC discovery", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	// Copy headers
	for key, values := range resp.Header {
		for _, value := range values {
			w.Header().Add(key, value)
		}
	}

	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

// proxyHandler handles all proxy requests
func (p *Proxy) proxyHandler(w http.ResponseWriter, r *http.Request) {
	// Handle CORS preflight requests
	if p.config.EnableCORS && r.Method == "OPTIONS" {
		p.handleCORS(w, r)
		return
	}

	// Extract and validate token
	token, claims, err := p.validateToken(r)
	if err != nil {
		log.Printf("Token validation failed: %v", err)
		p.sendErrorResponse(w, http.StatusUnauthorized, "Invalid or missing token", err.Error())
		return
	}

	// Log request details
	log.Printf("Request: %s %s from %s (user: %s, groups: %v)",
		r.Method, r.URL.Path, r.RemoteAddr, claims.Subject, claims.Groups)

	// Forward request to Temporal frontend
	p.forwardRequest(w, r, token, claims)
}

// validateToken extracts and validates the JWT token from the request
func (p *Proxy) validateToken(r *http.Request) (string, *TokenClaims, error) {
	// Extract token from Authorization header
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		return "", nil, fmt.Errorf("missing authorization header")
	}

	var token string
	if authHeader != "" {
		token = strings.ReplaceAll(authHeader, "Bearer ", "")
	} else {
		x_rafay_header := r.Header.Get(XRAFAYHeader)
		if x_rafay_header == "" {
			return "", nil, fmt.Errorf("missing authorization header")
		}
		token = x_rafay_header
	}

	if token == "" {
		return "", nil, fmt.Errorf("empty bearer token")
	}

	authTokenSplit := strings.Split(token, " ")
	if len(authTokenSplit) == 2 {
		clientId := authTokenSplit[0]
		authToken := authTokenSplit[1]
		// Validate token with timeout
		ctx, cancel := context.WithTimeout(context.Background(), p.config.TokenValidationTimeout)
		defer cancel()
		provider, err := oidc.NewProvider(ctx, p.OIDCIssuer)
		if err != nil {
			return "", nil, fmt.Errorf("failed for provider")
		}
		idTokenVerifier := provider.Verifier(&oidc.Config{ClientID: clientId})
		idToken, err := idTokenVerifier.Verify(ctx, authToken)
		if err != nil {
			return "", nil, fmt.Errorf("token verification failed: %w", err)
		}

		// Extract claims
		var claims TokenClaims
		if err := idToken.Claims(&claims); err != nil {
			return "", nil, fmt.Errorf("failed to extract claims: %w", err)
		}

		// Validate issuer
		if claims.Issuer != p.config.OIDCIssuer {
			return "", nil, fmt.Errorf("invalid issuer: expected %s, got %s", p.config.OIDCIssuer, claims.Issuer)
		}

		// Validate audience
		audienceValid := false
		for _, aud := range claims.Audience {
			if aud == p.config.OIDCClientID {
				audienceValid = true
				break
			}
		}
		if !audienceValid {
			return "", nil, fmt.Errorf("invalid audience: expected %s, got %v", p.config.OIDCClientID, claims.Audience)
		}

		return token, &claims, nil

	}

	return "", nil, fmt.Errorf("invalid authorization header format")

}

// forwardRequest forwards the validated request to the Temporal frontend
func (p *Proxy) forwardRequest(w http.ResponseWriter, r *http.Request, token string, claims *TokenClaims) {
	// Parse the target URL
	targetURL, err := url.Parse(p.config.TemporalFrontendURL)
	if err != nil {
		log.Printf("Error parsing target URL: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Create reverse proxy
	proxy := httputil.NewSingleHostReverseProxy(targetURL)

	// Customize the director to modify the request
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)

		// Set the original Authorization header (validated token)
		req.Header.Set("Authorization", "Bearer "+token)

		// Add custom headers for internal routing
		req.Header.Set("X-Temporal-Proxy", "true")
		req.Header.Set("X-Temporal-User", claims.Subject)
		if claims.Email != "" {
			req.Header.Set("X-Temporal-Email", claims.Email)
		}
		if len(claims.Groups) > 0 {
			req.Header.Set("X-Temporal-Groups", strings.Join(claims.Groups, ","))
		}

		// Log the forwarded request
		log.Printf("Forwarding: %s %s -> %s", req.Method, req.URL.Path, req.URL.String())
	}

	// Customize error handling
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("Proxy error: %v", err)
		p.sendErrorResponse(w, http.StatusBadGateway, "Failed to forward request", err.Error())
	}

	// Serve the request
	proxy.ServeHTTP(w, r)
}

// handleCORS handles CORS preflight requests
func (p *Proxy) handleCORS(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
	w.Header().Set("Access-Control-Max-Age", "86400")
	w.WriteHeader(http.StatusOK)
}

// sendErrorResponse sends a standardized error response
func (p *Proxy) sendErrorResponse(w http.ResponseWriter, statusCode int, message, error string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	response := Response{
		Success: false,
		Message: message,
		Error:   error,
	}

	json.NewEncoder(w).Encode(response)
}

// getEnv gets an environment variable with a default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
