# Variables
BINARY_NAME=temporal-frontend-proxy
DOCKER_IMAGE=temporal-frontend-proxy
DOCKER_TAG=$(shell date -u '+%Y%m%d-%H%M%S')
REGISTRY=registry.dev.rafay-edge.net/rafay

# Go related variables
GOCMD=go
GOBUILD=$(GOCMD) build
GOCLEAN=$(GOCMD) clean
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get
GOMOD=$(GOCMD) mod

# Build flags
LDFLAGS=-ldflags "-X main.Version=$(shell git describe --tags --always --dirty) -X main.BuildTime=$(shell date -u '+%Y-%m-%d_%H:%M:%S')"

.PHONY: all build clean test deps docker-build docker-push docker-run help

# Default target
all: clean deps test build

# Build the application
build:
	@echo "🔨 Building $(BINARY_NAME)..."
	$(GOBUILD) $(LDFLAGS) -o $(BINARY_NAME) .

# Clean build artifacts
clean:
	@echo "🧹 Cleaning..."
	$(GOCLEAN)
	rm -f $(BINARY_NAME)

# Run tests
test:
	@echo "🧪 Running tests..."
	$(GOTEST) -v ./...

# Get dependencies
deps:
	@echo "📦 Getting dependencies..."
	$(GOMOD) download
	$(GOMOD) tidy

# Run the application locally
run:
	@echo "🚀 Running $(BINARY_NAME)..."
	./$(BINARY_NAME)

# Run with hot reload (requires air: go install github.com/cosmtrek/air@latest)
dev:
	@echo "🔥 Running in development mode..."
	air

# Build Docker image
docker-build:
	@echo "🐳 Building Docker image..."
	docker build --platform linux/amd64 -t $(DOCKER_IMAGE):$(DOCKER_TAG) .
	docker tag $(DOCKER_IMAGE):$(DOCKER_TAG) $(REGISTRY)/$(DOCKER_IMAGE):$(DOCKER_TAG)

# Build multi-platform Docker image
docker-build-multi:
	@echo "🐳 Building multi-platform Docker image..."
	docker buildx build --platform linux/amd64,linux/arm64 -t $(REGISTRY)/$(DOCKER_IMAGE):$(DOCKER_TAG) --push .

# Push Docker image to registry
docker-push:
	@echo "📤 Pushing Docker image..."
	docker push $(REGISTRY)/$(DOCKER_IMAGE):$(DOCKER_TAG)

# Run Docker container locally
docker-run:
	@echo "🐳 Running Docker container..."
	docker run -p 8081:8081 \
		-e TEMPORAL_FRONTEND_URL=http://temporalio-frontend.rafay-core.svc.cluster.local:7233 \
		-e OIDC_ISSUER=https://console.gaap.dev.rafay-edge.net/dex \
		-e OIDC_CLIENT_ID=temporal-server \
		$(DOCKER_IMAGE):$(DOCKER_TAG)

# Run Docker container with custom config
docker-run-custom:
	@echo "🐳 Running Docker container with custom config..."
	docker run -p 8081:8081 \
		-e TEMPORAL_FRONTEND_URL=$(TEMPORAL_URL) \
		-e OIDC_ISSUER=$(OIDC_ISSUER) \
		-e OIDC_CLIENT_ID=$(OIDC_CLIENT_ID) \
		-e LOG_LEVEL=debug \
		$(DOCKER_IMAGE):$(DOCKER_TAG)

# Build and push to registry
build-and-push: docker-build docker-push

# Show current tag and platform
show-tag:
	@echo "🏷️  Current Docker tag: $(DOCKER_TAG)"
	@echo "🖥️  Target platform: linux/amd64"

# Build with specific tag
build-with-tag:
	@echo "🐳 Building Docker image with tag: $(DOCKER_TAG)..."
	docker build --platform linux/amd64 -t $(DOCKER_IMAGE):$(DOCKER_TAG) .
	docker tag $(DOCKER_IMAGE):$(DOCKER_TAG) $(REGISTRY)/$(DOCKER_IMAGE):$(DOCKER_TAG)
	@echo "✅ Built with tag: $(DOCKER_TAG)"

# Tag as latest (for convenience)
tag-latest:
	@echo "🏷️  Tagging as latest..."
	docker tag $(REGISTRY)/$(DOCKER_IMAGE):$(DOCKER_TAG) $(REGISTRY)/$(DOCKER_IMAGE):latest
	docker push $(REGISTRY)/$(DOCKER_IMAGE):latest

# Build, push, and tag as latest
build-push-latest: build-with-tag docker-push tag-latest

# Install development tools
install-tools:
	@echo "🛠️ Installing development tools..."
	go install github.com/cosmtrek/air@latest
	go install golang.org/x/tools/cmd/goimports@latest
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# Format code
fmt:
	@echo "🎨 Formatting code..."
	goimports -w .
	gofmt -s -w .

# Lint code
lint:
	@echo "🔍 Linting code..."
	golangci-lint run

# Security scan
security-scan:
	@echo "🔒 Running security scan..."
	gosec ./...

# Generate go.sum
generate-deps:
	@echo "📋 Generating go.sum..."
	$(GOMOD) download
	$(GOMOD) tidy

# Show help
help:
	@echo "Available targets:"
	@echo "  build           - Build the application"
	@echo "  clean           - Clean build artifacts"
	@echo "  test            - Run tests"
	@echo "  deps            - Get dependencies"
	@echo "  run             - Run the application locally"
	@echo "  dev             - Run with hot reload (requires air)"
	@echo "  docker-build    - Build Docker image (AMD64)"
	@echo "  docker-build-multi - Build multi-platform Docker image"
	@echo "  docker-push     - Push Docker image to registry"
	@echo "  docker-run      - Run Docker container locally"
	@echo "  build-and-push  - Build and push to registry"
	@echo "  show-tag        - Show current Docker tag and platform"
	@echo "  build-with-tag  - Build with timestamp tag"
	@echo "  tag-latest      - Tag current build as latest"
	@echo "  build-push-latest - Build, push, and tag as latest"
	@echo "  install-tools   - Install development tools"
	@echo "  fmt             - Format code"
	@echo "  lint            - Lint code"
	@echo "  security-scan   - Run security scan"
	@echo "  generate-deps   - Generate go.sum"
	@echo "  help            - Show this help"

# Environment variables for docker-run-custom
# Usage: make docker-run-custom TEMPORAL_URL=http://localhost:7233 OIDC_ISSUER=https://dex.example.com OIDC_CLIENT_ID=my-client 