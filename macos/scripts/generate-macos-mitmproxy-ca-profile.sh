#!/bin/bash
#
# Generate macOS profile with mitmproxy CA (device scope)
#
# This installs the mitmproxy CA as a trusted root so system processes
# (including mdmclient) trust HTTPS interception.
#
# Usage: ./generate-macos-mitmproxy-ca-profile.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$MACOS_DIR/profiles"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

echo "=== Generating macOS mitmproxy CA Profile ==="
echo ""

# Fetch mitmproxy CA certificate
echo "Fetching mitmproxy CA certificate..."
MITMPROXY_POD=$(kubectl get pods -n hocuspocus -l app=mitmproxy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$MITMPROXY_POD" ]; then
    echo "Error: mitmproxy pod not found"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

kubectl exec -n hocuspocus "$MITMPROXY_POD" -- cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > "$TEMP_DIR/mitmproxy-ca.pem" 2>/dev/null
if [ ! -s "$TEMP_DIR/mitmproxy-ca.pem" ]; then
    echo "Error: Could not fetch mitmproxy CA certificate"
    exit 1
fi

MITMPROXY_CA_BASE64=$(base64 -i "$TEMP_DIR/mitmproxy-ca.pem" | tr -d '\n')
echo "mitmproxy CA certificate fetched"

# Generate UUIDs for profile
PROFILE_UUID=$(uuidgen)
CA_UUID=$(uuidgen)

# Profile output path
PROFILE_PATH="$OUTPUT_DIR/hocuspocus-proxy-ca-macos.mobileconfig"

cat > "$PROFILE_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadCertificateFileName</key>
            <string>mitmproxy-ca.pem</string>
            <key>PayloadContent</key>
            <data>$MITMPROXY_CA_BASE64</data>
            <key>PayloadDescription</key>
            <string>mitmproxy CA for HTTPS interception</string>
            <key>PayloadDisplayName</key>
            <string>Hocuspocus Proxy CA</string>
            <key>PayloadIdentifier</key>
            <string>com.hocuspocus.proxy.ca.macos</string>
            <key>PayloadType</key>
            <string>com.apple.security.root</string>
            <key>PayloadUUID</key>
            <string>$CA_UUID</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>

    <key>PayloadDescription</key>
    <string>Hocuspocus mitmproxy CA for macOS</string>
    <key>PayloadDisplayName</key>
    <string>Hocuspocus Proxy CA (macOS)</string>
    <key>PayloadIdentifier</key>
    <string>com.hocuspocus.proxy.ca.macos.profile</string>
    <key>PayloadOrganization</key>
    <string>Hocuspocus</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>$PROFILE_UUID</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
EOF

echo ""
echo "=== macOS mitmproxy CA Profile Generated ==="
echo "Profile: $PROFILE_PATH"
echo ""
