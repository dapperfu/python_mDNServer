# Multi-stage build for mDNServer
FROM python:3.11-slim AS builder

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

# Install runtime dependencies
# - avahi-daemon: mDNS daemon required for avahi-resolve
# - avahi-utils: provides avahi-resolve command
# - dbus: required by avahi-daemon
# - dbus-x11: provides dbus-launch (needed for dbus session)
# - gosu: for user switching in startup script
# - dnsutils: provides dig command for healthcheck
# - procps: provides pgrep, ps, and other process utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    avahi-daemon \
    avahi-utils \
    dbus \
    dbus-x11 \
    gosu \
    dnsutils \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 -s /bin/bash mdnserver

# Copy installed package from builder
COPY --from=builder /root/.local /home/mdnserver/.local

# Set PATH to include user local bin
ENV PATH=/home/mdnserver/.local/bin:$PATH

# Create runtime directories
RUN mkdir -p /var/run/mdnserver && \
    mkdir -p /var/run/dbus && \
    mkdir -p /var/run/avahi-daemon && \
    chown -R mdnserver:mdnserver /var/run/mdnserver

# Configure avahi-daemon for container use
# Disable publishing (we only need to resolve, not publish)
RUN sed -i 's/#enable-dbus=yes/enable-dbus=yes/' /etc/avahi/avahi-daemon.conf && \
    sed -i 's/#enable-reflector=no/enable-reflector=yes/' /etc/avahi/avahi-daemon.conf && \
    sed -i 's/#publish-hinfo=no/publish-hinfo=no/' /etc/avahi/avahi-daemon.conf && \
    sed -i 's/#publish-workstation=yes/publish-workstation=no/' /etc/avahi/avahi-daemon.conf && \
    sed -i 's/^#use-ipv4=yes/use-ipv4=yes/' /etc/avahi/avahi-daemon.conf && \
    sed -i 's/^#use-ipv6=no/use-ipv6=no/' /etc/avahi/avahi-daemon.conf

# Create startup script that runs as root to start avahi-daemon, then switches to user
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Function to cleanup on exit\n\
cleanup() {\n\
    echo "Shutting down..."\n\
    if [ -n "$AVAHI_PID" ]; then\n\
        kill "$AVAHI_PID" 2>/dev/null || true\n\
    fi\n\
    if [ -n "$DBUS_PID" ]; then\n\
        kill "$DBUS_PID" 2>/dev/null || true\n\
    fi\n\
    exit 0\n\
}\n\
trap cleanup SIGTERM SIGINT\n\
\n\
# Start dbus daemon\n\
echo "Starting dbus daemon..."\n\
eval $(dbus-launch --sh-syntax)\n\
export DBUS_SESSION_BUS_ADDRESS\n\
# Try to get DBUS PID (optional, for logging)\n\
DBUS_PID=$(pgrep -f "dbus-daemon.*$DBUS_SESSION_BUS_ADDRESS" 2>/dev/null | head -1 || echo "")\n\
if [ -n "$DBUS_PID" ]; then\n\
    echo "dbus daemon started (PID: $DBUS_PID, address: $DBUS_SESSION_BUS_ADDRESS)"\n\
else\n\
    echo "dbus daemon started (address: $DBUS_SESSION_BUS_ADDRESS)"\n\
fi\n\
\n\
# Start avahi-daemon as root (needs root for network binding)\n\
echo "Starting avahi-daemon..."\n\
avahi-daemon --daemonize --no-drop-root\n\
\n\
# Wait a moment for avahi-daemon to be ready\n\
sleep 2\n\
\n\
# Check if avahi-daemon is running and get PID\n\
AVAHI_PID=$(pgrep -x avahi-daemon 2>/dev/null | head -1 || echo "")\n\
if [ -z "$AVAHI_PID" ]; then\n\
    echo "ERROR: avahi-daemon failed to start"\n\
    echo "Checking for error messages..."\n\
    avahi-daemon --no-drop-root --no-chroot 2>&1 | head -20 || true\n\
    exit 1\n\
fi\n\
\n\
echo "avahi-daemon started successfully (PID: $AVAHI_PID)"\n\
\n\
# Verify avahi-resolve can connect to daemon\n\
if ! avahi-resolve --name -4 localhost.local 2>/dev/null; then\n\
    echo "WARNING: avahi-resolve test failed, but continuing..."\n\
fi\n\
\n\
# Switch to non-root user and start mdnserver\n\
# DBUS_SESSION_BUS_ADDRESS is preserved in environment\n\
exec gosu mdnserver env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" mdnserver "$@"\n\
' > /usr/local/bin/start-mdnserver.sh && \
    chmod +x /usr/local/bin/start-mdnserver.sh

# Expose DNS port
EXPOSE 5053/udp 5053/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD dig @127.0.0.1 -p 5053 +short +timeout=2 test.local || exit 1

# Default environment variables
ENV MDNSERVER_PORT=5053
ENV MDNSERVER_ADDRESS=0.0.0.0
ENV MDNSERVER_LOG_LEVEL=INFO

# Run the startup script
ENTRYPOINT ["/usr/local/bin/start-mdnserver.sh"]
CMD ["--port", "5053", "--address", "0.0.0.0", "--log-level", "INFO"]

