#!/bin/bash
# Configure network interfaces for mDNS reflection
# Alternative to bridging: configure reflector to listen on specific interfaces

set -e

# Interfaces to configure (can be overridden via environment variables)
INTERFACES="${MDNS_INTERFACES:-eth0 docker0}"

echo "Configuring interfaces for mDNS reflection..."
echo "Interfaces: ${INTERFACES}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Enable multicast on interfaces
for interface in ${INTERFACES}; do
    if ip link show "${interface}" &> /dev/null; then
        echo "Configuring interface ${interface}..."
        # Enable multicast
        ip link set "${interface}" multicast on || true
        # Show interface status
        echo "Interface ${interface} status:"
        ip link show "${interface}" | grep -E "(state|multicast)" || true
    else
        echo "WARNING: Interface ${interface} not found, skipping..."
    fi
done

echo "Interface configuration complete"

