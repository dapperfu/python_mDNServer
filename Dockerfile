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

# Create avahi user and group (required by avahi-daemon)
#RUN groupadd -r avahi && useradd -r -g avahi -d /var/run/avahi-daemon -s /usr/sbin/nologin avahi

# Create non-root user for mdnserver
RUN useradd -m -u 1000 -s /bin/bash mdnserver

# Copy installed package from builder
COPY --from=builder /root/.local /home/mdnserver/.local

# Set PATH to include user local bin
ENV PATH=/home/mdnserver/.local/bin:$PATH

# Create runtime directories
RUN mkdir -p /var/run/mdnserver && \
    mkdir -p /var/run/dbus && \
    mkdir -p /var/run/avahi-daemon && \
    chown -R mdnserver:mdnserver /var/run/mdnserver && \
    chown -R avahi:avahi /var/run/avahi-daemon

# Configure avahi-daemon for container use
# Enable D-Bus (needed for avahi-resolve to communicate with daemon)
# Disable publishing (we only need to resolve, not publish)
RUN sed -i 's/#enable-dbus=yes/enable-dbus=yes/' /etc/avahi/avahi-daemon.conf && \
    sed -i 's/enable-dbus=no/enable-dbus=yes/' /etc/avahi/avahi-daemon.conf && \
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
    exit 0\n\
}\n\
trap cleanup SIGTERM SIGINT\n\
\n\
# Start dbus daemon (needed for avahi-resolve to communicate with avahi-daemon)\n\
echo "Starting dbus daemon..."\n\
eval $(dbus-launch --sh-syntax)\n\
export DBUS_SESSION_BUS_ADDRESS\n\
# Also set system bus to use session bus (avahi-daemon checks system bus)\n\
export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"\n\
echo "dbus daemon started (address: $DBUS_SESSION_BUS_ADDRESS)"\n\
\n\
# Create symlink so avahi-daemon can find system bus (it checks /run/dbus/system_bus_socket)\n\
mkdir -p /run/dbus\n\
# Extract the socket path from DBUS_SESSION_BUS_ADDRESS (format: unix:path=/tmp/dbus-...)\n\
SESSION_SOCKET="${DBUS_SESSION_BUS_ADDRESS#unix:path=}"\n\
# Remove any abstract socket prefix if present\n\
SESSION_SOCKET="${SESSION_SOCKET#unix:abstract=}"\n\
echo "Extracted socket path: $SESSION_SOCKET"\n\
# Wait for socket to be created (with retries)\n\
for i in 1 2 3 4 5; do\n\
    if [ -e "$SESSION_SOCKET" ]; then\n\
        echo "Socket found after $i attempts"\n\
        break\n\
    fi\n\
    sleep 0.5\n\
done\n\
# Create a symlink from system bus socket to our session bus\n\
# This tricks avahi-daemon into using our session D-Bus\n\
if [ -n "$SESSION_SOCKET" ]; then\n\
    if [ -e "$SESSION_SOCKET" ]; then\n\
        rm -f /run/dbus/system_bus_socket\n\
        ln -sf "$SESSION_SOCKET" /run/dbus/system_bus_socket\n\
        echo "Created symlink: /run/dbus/system_bus_socket -> $SESSION_SOCKET"\n\
        # Verify symlink\n\
        if [ -L /run/dbus/system_bus_socket ]; then\n\
            echo "Symlink verified successfully"\n\
            ls -la /run/dbus/system_bus_socket\n\
        else\n\
            echo "WARNING: Symlink creation may have failed"\n\
        fi\n\
    else\n\
        echo "WARNING: Socket does not exist: $SESSION_SOCKET"\n\
        echo "Attempting to create symlink anyway..."\n\
        rm -f /run/dbus/system_bus_socket\n\
        ln -sf "$SESSION_SOCKET" /run/dbus/system_bus_socket 2>&1 || echo "Symlink creation failed"\n\
    fi\n\
else\n\
    echo "WARNING: Could not extract socket path from DBUS_SESSION_BUS_ADDRESS"\n\
fi\n\
\n\
# Start avahi-daemon as root (needs root for network binding)\n\
echo "Starting avahi-daemon..."\n\
# Start in background and capture output\n\
AVAHI_LOG=$(mktemp)\n\
avahi-daemon --no-drop-root --no-chroot > "$AVAHI_LOG" 2>&1 &\n\
AVAHI_BG_PID=$!\n\
\n\
# Wait a moment and check if it's still running\n\
sleep 3\n\
\n\
# Check if the background process is still running\n\
if ! kill -0 $AVAHI_BG_PID 2>/dev/null; then\n\
    echo "ERROR: avahi-daemon failed to start. Output:"\n\
    cat "$AVAHI_LOG" 2>/dev/null || true\n\
    rm -f "$AVAHI_LOG"\n\
    exit 1\n\
fi\n\
\n\
# If it's running, get the actual avahi-daemon PID (it might have forked)\n\
AVAHI_PID=$(pgrep -x avahi-daemon 2>/dev/null | head -1 || echo "")\n\
if [ -z "$AVAHI_PID" ]; then\n\
    echo "WARNING: avahi-daemon process not found, but background process is running"\n\
    AVAHI_PID=$AVAHI_BG_PID\n\
else\n\
    # Kill the background process if avahi-daemon forked\n\
    if [ "$AVAHI_PID" != "$AVAHI_BG_PID" ]; then\n\
        kill $AVAHI_BG_PID 2>/dev/null || true\n\
    fi\n\
fi\n\
rm -f "$AVAHI_LOG"\n\
\n\
echo "avahi-daemon started successfully (PID: $AVAHI_PID)"\n\
\n\
# Verify avahi-resolve can connect to daemon\n\
if ! avahi-resolve --name -4 localhost.local 2>/dev/null; then\n\
    echo "WARNING: avahi-resolve test failed, but continuing..."\n\
fi\n\
\n\
# Switch to non-root user and start mdnserver\n\
# DBUS_SESSION_BUS_ADDRESS is needed for avahi-resolve\n\
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

