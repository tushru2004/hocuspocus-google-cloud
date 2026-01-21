#!/bin/bash
#
# Uninstall pf Kill Switch from macOS
#

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

echo "=== Uninstalling Hocuspocus pf Kill Switch ==="
echo ""

# Unload LaunchDaemon
echo "Unloading LaunchDaemon..."
launchctl unload /Library/LaunchDaemons/com.hocuspocus.pf-killswitch.plist 2>/dev/null || true

# Remove files
echo "Removing files..."
rm -f /Library/LaunchDaemons/com.hocuspocus.pf-killswitch.plist
rm -f /etc/pf.d/hocuspocus-pf.conf

# Disable pf (restores normal networking)
echo "Disabling pf..."
pfctl -d 2>/dev/null || true

echo ""
echo "=== Kill Switch Uninstalled ==="
echo "Normal networking has been restored."
echo ""
