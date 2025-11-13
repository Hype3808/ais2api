# =============================================================================
# Multi-stage build for MAXIMUM image size optimization
# Final image size: ~400-600MB (down from 1.5-2GB)
# =============================================================================

# Stage 1: Dependencies
FROM node:18-slim AS dependencies

WORKDIR /app

# Copy only package files for better layer caching
COPY package*.json ./

# Install production dependencies only
RUN npm ci --only=production --no-audit --no-fund \
    && npm cache clean --force

# Stage 2: Playwright Browser Installation
FROM node:18-slim AS browser

WORKDIR /app

# Install ONLY the minimal dependencies for Firefox
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core libraries for Firefox
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libexpat1 \
    libgbm1 \
    libglib2.0-0 \
    libnspr4 \
    libnss3 \
    libx11-6 \
    libxcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    # Fonts (minimal set)
    fonts-liberation \
    # Cleanup in same layer
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy dependencies from previous stage
COPY --from=dependencies /app/node_modules ./node_modules
COPY package*.json ./

# Install Playwright Firefox ONLY (no chromium, webkit)
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npx playwright install firefox --with-deps \
    && rm -rf /root/.cache \
    && rm -rf /tmp/*

# Stage 3: Final optimized image
FROM node:18-slim

# Set environment for production
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=7860 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    # Node.js memory optimization
    NODE_OPTIONS="--max-old-space-size=1024"

WORKDIR /app

# Install ONLY runtime dependencies (no build tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Minimal Firefox runtime libraries
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libexpat1 \
    libgbm1 \
    libglib2.0-0 \
    libnspr4 \
    libnss3 \
    libx11-6 \
    libxcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    fonts-liberation \
    # Health check requirement
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    # Remove unnecessary files
    && rm -rf /usr/share/doc/* \
    && rm -rf /usr/share/man/* \
    && rm -rf /var/cache/apt/*

# Copy dependencies from Stage 1
COPY --from=dependencies /app/node_modules ./node_modules

# Copy Playwright browsers from Stage 2
COPY --from=browser /ms-playwright /ms-playwright

# Copy application files
COPY --chown=node:node . .

# Create auth directory
RUN mkdir -p /app/auth && chown -R node:node /app

# Switch to non-root user for security
USER node

# Expose ports
EXPOSE 7860 9998

# Optimized health check (lighter)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD node -e "require('http').get('http://localhost:7860/api/status', (r) => process.exit(r.statusCode === 200 ? 0 : 1))"

# Use exec form for better signal handling
CMD ["node", "unified-server.js"]
