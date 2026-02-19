# AGENTS.md

## Project Overview

This repository contains Docker build configurations for Redlib, a lightweight Reddit alternative. The actual Rust source code is cloned from an external repository (https://github.com/chowder/redlib.git) during the build process.

## Build Commands

### Local Docker Build

Build the Redlib container locally:

```bash
docker build -f redlib/Dockerfile -t redlib .
```

### Build with Specific Alpine Version

```bash
docker build --build-arg ALPINE_VERSION=3.22 -f redlib/Dockerfile -t redlib .
```

### Build with Specific Redlib Branch

```bash
docker build --build-arg REDLIB_BRANCH=main -f redlib/Dockerfile -t redlib .
```

### Run the Container

```bash
docker run -p 8080:8080 -d --name redlib redlib
```

### Verify Container Health

```bash
docker ps
docker inspect --format='{{.State.Health.Status}}' redlib
```

## CI/CD

### GitHub Actions Workflow

The repository uses GitHub Actions for automated builds and pushes to GitHub Container Registry:

- **Trigger**: Changes to any `*/Dockerfile` file
- **Manual trigger**: Available in GitHub Actions interface
- **Platforms**: Builds for linux/amd64 and linux/arm64
- **Image naming**: `ghcr.io/{owner}/containers:{app-name}`

To trigger manually:

1. Go to Actions tab
2. Select "Build container images"
3. Enter comma-separated app names (e.g., "redlib")
4. Click "Run workflow"

## Dockerfile Guidelines

### Structure

The Dockerfile follows a multi-stage build pattern:

1. **Builder stage**: Clones Redlib source and builds with Cargo
2. **Release stage**: Copies binary and sets up minimal Alpine runtime

### Best Practices

- **Alpine version**: Specify explicit Alpine version in ARG
- **Non-root user**: Always run as non-root user (redlib)
- **Health checks**: Include healthcheck for container monitoring
- **Caching**: Use `--no-cache` for apk to ensure fresh package lists
- **Security**: Use `--locked` flag for Cargo builds

### Code Style

- **Comments**: Keep comments concise and descriptive
- **ARGs**: Use uppercase for build arguments
- **Commands**: Follow Alpine package naming conventions
- **User context**: Document user switching for security

## Project-Specific Notes

### Redlib Source Management

- The Redlib source is cloned from GitHub during build
- Branch can be customized via `REDLIB_BRANCH` build argument
- The project uses TLS-OpenSSL branch currently
- Build artifacts are cached in the builder stage

### Environment Variables

Configure via Docker environment variables:

- `PORT` - Server port (default: 8080)
- `DOMAIN` - Domain name
- `REDIS_URL` - Redis connection string (optional)

### Troubleshooting

**Build fails**: Check the Rust build logs for compilation errors

**Healthcheck fails**: Verify network connectivity and port binding

**Permission denied**: Ensure non-root user is used for runtime

## External References

- Redlib GitHub: https://github.com/chowder/redlib
- Rust Docker images: https://hub.docker.com/_/rust
- Alpine Docker images: https://hub.docker.com/_/alpine
