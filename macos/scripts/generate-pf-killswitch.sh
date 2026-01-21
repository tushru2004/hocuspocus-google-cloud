#!/bin/bash
#
# Generate pf (Packet Filter) Kill Switch for macOS
#
# This creates firewall rules that block all traffic except:
# - VPN server connection (IKEv2 ports 500, 4500)
# - VPN tunnel interface (utun*)
# - Local loopback
# - DHCP (for WiFi connection)
#
# Usage: ./generate-pf-killswitch.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$MACOS_DIR/profiles"

mkdir -p "$OUTPUT_DIR"

echo "=== Generating pf Kill Switch Configuration ==="
echo ""

# Get VPN server IP
VPN_IP=$(kubectl get svc vpn-service -n hocuspocus -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
if [ -z "$VPN_IP" ]; then
    echo "Error: Could not get VPN service IP. Is the cluster running?"
    exit 1
fi
echo "VPN Server IP: $VPN_IP"

# Generate pf.conf
PF_CONF="$OUTPUT_DIR/hocuspocus-pf.conf"

cat > "$PF_CONF" << EOF
#
# Hocuspocus VPN Kill Switch
#
# This configuration blocks ALL traffic except:
# - VPN server connection
# - Traffic through VPN tunnel
# - Local loopback
# - DHCP for network connectivity
#
# Generated: $(date)
# VPN Server: $VPN_IP
#

# Options
set block-policy drop
set skip on lo0

# Scrub incoming packets
scrub in all

# Block all traffic by default
block drop all

# Allow loopback
pass quick on lo0 all

# Allow DHCP (needed to connect to WiFi/Ethernet)
pass out quick proto udp from any port 68 to any port 67

# Allow DNS to resolve VPN server (optional, remove if using IP only)
# pass out quick proto udp to any port 53

# Allow connection to VPN server (IKEv2)
pass out quick proto udp from any to $VPN_IP port 500
pass out quick proto udp from any to $VPN_IP port 4500
pass in quick proto udp from $VPN_IP port 500 to any
pass in quick proto udp from $VPN_IP port 4500 to any

# Allow ESP protocol for IKEv2
pass out quick proto esp from any to $VPN_IP
pass in quick proto esp from $VPN_IP to any

# Allow all traffic through VPN tunnel interfaces (utun0, utun1, etc.)
pass quick on utun0 all
pass quick on utun1 all
pass quick on utun2 all
pass quick on utun3 all

# Allow established connections (for VPN tunnel)
pass in quick proto tcp all flags S/SA keep state
pass out quick proto tcp all flags S/SA keep state
EOF

echo ""
echo "=== pf Kill Switch Configuration Generated ==="
echo "Config: $PF_CONF"
echo ""

# Generate LaunchDaemon for auto-loading pf on boot
LAUNCHDAEMON_DIR="$MACOS_DIR/launchdaemons"
mkdir -p "$LAUNCHDAEMON_DIR"

LAUNCHDAEMON_PLIST="$LAUNCHDAEMON_DIR/com.hocuspocus.pf-killswitch.plist"

cat > "$LAUNCHDAEMON_PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hocuspocus.pf-killswitch</string>
    <key>ProgramArguments</key>
    <array>
        <string>/sbin/pfctl</string>
        <string>-f</string>
        <string>/etc/pf.d/hocuspocus-pf.conf</string>
        <string>-e</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/var/log/hocuspocus-pf.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/hocuspocus-pf.log</string>
</dict>
</plist>
EOF

echo "LaunchDaemon: $LAUNCHDAEMON_PLIST"
echo ""

# Generate installation script
INSTALL_SCRIPT="$MACOS_DIR/scripts/install-pf-killswitch.sh"

cat > "$INSTALL_SCRIPT" << 'INSTALL_EOF'
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
INSTALL_EOF

chmod +x "$INSTALL_SCRIPT"

# Generate uninstall script
UNINSTALL_SCRIPT="$MACOS_DIR/scripts/uninstall-pf-killswitch.sh"

cat > "$UNINSTALL_SCRIPT" << 'UNINSTALL_EOF'
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
UNINSTALL_EOF

chmod +x "$UNINSTALL_SCRIPT"

echo "Install script: $INSTALL_SCRIPT"
echo "Uninstall script: $UNINSTALL_SCRIPT"
echo ""
echo "To install the kill switch:"
echo "  sudo $INSTALL_SCRIPT"
echo ""
echo "To test pf rules without persisting:"
echo "  sudo pfctl -f $PF_CONF"
echo "  sudo pfctl -e"
echo ""
echo "WARNING: The kill switch will block ALL internet traffic until VPN is connected!"
echo ""
