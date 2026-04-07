# Stage 1: Install bun from the official image
FROM oven/bun:1-slim AS bun-deps
RUN bun install -g @anthropic-ai/claude-code

# Stage 2: Python builder
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
ENV SETUPTOOLS_SCM_PRETEND_VERSION=0.2.7
ENV UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# Install git
RUN apt-get update && apt-get install -y \
  git \
  && rm -rf /var/lib/apt/lists/*

# Copy dependency files and install Python dependencies
COPY uv.lock pyproject.toml ./
RUN uv sync --locked --no-install-project --no-dev

# Copy application code
COPY . /app

# Install the project
RUN uv sync --locked --no-dev

# Stage 3: Runtime
FROM python:3.11-slim-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y \
  curl wget ripgrep fd-find exa sed mawk procps\
  build-essential \
  git \
  && rm -rf /var/lib/apt/lists/*

# Copy bun binaries from bun-deps stage and link to node
COPY --from=bun-deps /usr/local/bin/bun /usr/local/bin/
COPY --from=bun-deps /usr/local/bin/bunx /usr/local/bin/
RUN ln -s /usr/local/bin/bun /usr/local/bin/node && ln -s /usr/local/bin/bunx /usr/local/bin/npx

# Install package for claude and link to claude bin
COPY --from=bun-deps /root/.bun/install/global /app/bun_global
RUN ln -s /app/bun_global/node_modules/\@anthropic-ai/claude-code/cli.js /usr/local/bin/claude


# Copy Python application from builder
COPY --from=builder /app /app

WORKDIR /app

ENV PATH="/app/.venv/bin:/app/bun_global/bin:$PATH"
ENV PYTHONPATH=/app
ENV SERVER__HOST=0.0.0.0
ENV SERVER__PORT=8000
ENV LOGGING__LEVEL=INFO
ENV LOGGING__FORMAT=json

EXPOSE ${SERVER__PORT:-8000}

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:${SERVER__PORT:-8000}/health || exit 1

# Run the API server by default
CMD ["ccproxy"]

