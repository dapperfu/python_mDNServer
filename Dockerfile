# Multi-stage build for mDNServer
FROM python:3.11-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy project files
WORKDIR /build
COPY pyproject.toml ./
COPY mdnserver/ ./mdnserver/

# Install package
RUN pip install --no-cache-dir --user .

# Runtime stage
FROM python:3.11-slim

# Install runtime dependencies (avahi-utils for avahi-resolve)
RUN apt-get update && apt-get install -y --no-install-recommends \
    avahi-utils \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 -s /bin/bash mdnserver

# Copy installed package from builder
COPY --from=builder /root/.local /home/mdnserver/.local

# Set PATH to include user local bin
ENV PATH=/home/mdnserver/.local/bin:$PATH

# Create runtime directory
RUN mkdir -p /var/run/mdnserver && \
    chown mdnserver:mdnserver /var/run/mdnserver

# Switch to non-root user
USER mdnserver

# Expose DNS port
EXPOSE 5053/udp 5053/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD dig @127.0.0.1 -p 5053 +short +timeout=2 test.local || exit 1

# Default environment variables
ENV MDNSERVER_PORT=5053
ENV MDNSERVER_ADDRESS=0.0.0.0
ENV MDNSERVER_LOG_LEVEL=INFO

# Run the server
ENTRYPOINT ["mdnserver"]
CMD ["--port", "5053", "--address", "0.0.0.0", "--log-level", "INFO"]

