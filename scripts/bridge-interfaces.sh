#!/bin/bash
# Bridge network interfaces for mDNS reflection
# This script creates bridges between network interfaces to enable mDNS reflection

set -e

# Default interfaces to bridge (can be overridden via environment variables)
INTERFACES="${BRIDGE_INTERFACES:-eth0 docker0}"
BRIDGE_NAME="${BRIDGE_NAME:-mdns-br0}"

echo "Bridging interfaces for mDNS reflection..."
echo "Interfaces: ${INTERFACES}"
echo "Bridge name: ${BRIDGE_NAME}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Install bridge-utils if not available (supports both apt and apk)
if ! command -v brctl &> /dev/null; then
    echo "Installing bridge-utils..."
    if command -v apk &> /dev/null; then
        apk add --no-cache bridge-utils
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y bridge-utils
    else
        echo "ERROR: Cannot install bridge-utils, package manager not found"
        exit 1
    fi
fi

# Check if bridge already exists
if ip link show "${BRIDGE_NAME}" &> /dev/null; then
    echo "Bridge ${BRIDGE_NAME} already exists, removing..."
    ip link set "${BRIDGE_NAME}" down
    brctl delbr "${BRIDGE_NAME}" || true
fi

# Create the bridge
echo "Creating bridge ${BRIDGE_NAME}..."
brctl addbr "${BRIDGE_NAME}"
ip link set "${BRIDGE_NAME}" up

# Add interfaces to bridge
for interface in ${INTERFACES}; do
    if ip link show "${interface}" &> /dev/null; then
        echo "Adding interface ${interface} to bridge..."
        # Bring interface down before adding to bridge
        ip link set "${interface}" down || true
        # Add to bridge
        brctl addif "${BRIDGE_NAME}" "${interface}" || {
            echo "WARNING: Failed to add ${interface} to bridge, continuing..."
        }
        # Bring interface back up
        ip link set "${interface}" up || true
    else
        echo "WARNING: Interface ${interface} not found, skipping..."
    fi
done

# Bring bridge up
ip link set "${BRIDGE_NAME}" up

echo "Bridge ${BRIDGE_NAME} created successfully"
echo "Bridge status:"
brctl show "${BRIDGE_NAME}"

# Show bridge IP configuration
echo ""
echo "Bridge IP configuration:"
ip addr show "${BRIDGE_NAME}" || echo "No IP configured on bridge"

