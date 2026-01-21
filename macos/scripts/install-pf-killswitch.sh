#!/bin/bash
#
# Install pf Kill Switch on macOS
#
# This script must be run as root (sudo)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

echo "=== Installing Hocuspocus pf Kill Switch ==="
echo ""

# Create pf.d directory if it doesn't exist
mkdir -p /etc/pf.d

# Copy pf configuration
echo "Installing pf configuration..."
cp "$MACOS_DIR/profiles/hocuspocus-pf.conf" /etc/pf.d/
chmod 644 /etc/pf.d/hocuspocus-pf.conf

# Copy LaunchDaemon
echo "Installing LaunchDaemon..."
cp "$MACOS_DIR/launchdaemons/com.hocuspocus.pf-killswitch.plist" /Library/LaunchDaemons/
chmod 644 /Library/LaunchDaemons/com.hocuspocus.pf-killswitch.plist
chown root:wheel /Library/LaunchDaemons/com.hocuspocus.pf-killswitch.plist

# Load and enable pf rules
echo "Loading pf rules..."
pfctl -f /etc/pf.d/hocuspocus-pf.conf
pfctl -e 2>/dev/null || true

# Load LaunchDaemon
echo "Loading LaunchDaemon..."
launchctl load /Library/LaunchDaemons/com.hocuspocus.pf-killswitch.plist 2>/dev/null || true

echo ""
echo "=== Kill Switch Installed ==="
echo ""
echo "The firewall will now block all internet traffic except:"
echo "  - VPN server connection"
echo "  - Traffic through VPN tunnel"
echo ""
echo "To check status: sudo pfctl -s rules"
echo "To disable temporarily: sudo pfctl -d"
echo "To re-enable: sudo pfctl -e"
echo ""
