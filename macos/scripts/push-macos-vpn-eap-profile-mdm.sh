#!/bin/bash
#
# Push macOS VPN EAP Profile via SimpleMDM
#
# This script uploads the EAP-based VPN profile to SimpleMDM and pushes it
# to the MacBook Air. This profile uses username/password auth instead of
# certificates, which should work with User-Approved MDM.
#
# Usage: ./push-macos-vpn-eap-profile-mdm.sh [device_id]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
PROFILE_PATH="$MACOS_DIR/profiles/hocuspocus-vpn-macos-eap.mobileconfig"

# SimpleMDM API Key
API_KEY="2IkV3x1TEpS9r6AGtmeyvLlBMvwHzCeJgQY4O8VyTtoss2KR6qVpEZcQqPlmLrLV"

# Default to MacBook Air
DEVICE_ID="${1:-2162127}"

echo "=== Pushing macOS VPN EAP Profile via SimpleMDM ==="
echo ""

# Generate profile if it doesn't exist
if [ ! -f "$PROFILE_PATH" ]; then
    echo "Profile not found. Generating..."
    "$SCRIPT_DIR/generate-macos-vpn-eap-profile.sh"
fi

echo "Target device ID: $DEVICE_ID"
echo ""

# Get device name from SimpleMDM
DEVICE_NAME=$(curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/devices/$DEVICE_ID" | \
    python3 -c "import sys, json; print(json.load(sys.stdin)['data']['attributes']['name'])" 2>/dev/null || echo "Unknown")
echo "Device name: $DEVICE_NAME"
echo ""

# Delete old EAP profile if exists
echo "Checking for existing EAP profile..."
EXISTING_PROFILE=$(curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/custom_configuration_profiles" | \
    python3 -c "import sys, json; data=json.load(sys.stdin)['data']; profiles=[p for p in data if 'EAP' in p['attributes']['name'] or 'eap' in p['attributes']['name'].lower()]; print(profiles[0]['id'] if profiles else '')" 2>/dev/null || echo "")

if [ -n "$EXISTING_PROFILE" ]; then
    echo "Deleting existing EAP profile (ID: $EXISTING_PROFILE)..."
    curl -s -X DELETE -u "$API_KEY:" \
        "https://a.simplemdm.com/api/v1/custom_configuration_profiles/$EXISTING_PROFILE" > /dev/null
    sleep 2
fi

# Upload profile to SimpleMDM
echo "Uploading EAP profile to SimpleMDM..."
UPLOAD_RESPONSE=$(curl -s -X POST \
    -u "$API_KEY:" \
    -F "name=Hocuspocus VPN (macOS Device EAP)" \
    -F "mobileconfig=@$PROFILE_PATH" \
    "https://a.simplemdm.com/api/v1/custom_configuration_profiles")

PROFILE_ID=$(echo "$UPLOAD_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null || echo "")

if [ -z "$PROFILE_ID" ]; then
    echo "Error uploading profile:"
    echo "$UPLOAD_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$UPLOAD_RESPONSE"
    exit 1
fi

echo "Profile uploaded with ID: $PROFILE_ID"

# Assign profile to device
echo "Assigning profile to device $DEVICE_ID..."
ASSIGN_RESPONSE=$(curl -s -X POST \
    -u "$API_KEY:" \
    "https://a.simplemdm.com/api/v1/custom_configuration_profiles/$PROFILE_ID/devices/$DEVICE_ID")

if echo "$ASSIGN_RESPONSE" | grep -q "errors"; then
    echo "Assignment response: $ASSIGN_RESPONSE"
fi

# Trigger device refresh
echo "Triggering device refresh..."
curl -s -X POST -u "$API_KEY:" "https://a.simplemdm.com/api/v1/devices/$DEVICE_ID/refresh" > /dev/null

echo ""
echo "=== EAP Profile Pushed ==="
echo ""
echo "Profile: Hocuspocus VPN (macOS EAP)"
echo "Profile ID: $PROFILE_ID"
echo "Device: $DEVICE_NAME ($DEVICE_ID)"
echo ""
echo "This profile uses EAP authentication (no certificates)."
echo "Check the Mac in ~30 seconds:"
echo "  1. System Settings → VPN"
echo "  2. Or run: scutil --nc list"
echo ""
echo "If the profile still doesn't install, check macOS system logs:"
echo "  log show --predicate 'subsystem == \"com.apple.ManagedClient\"' --last 5m"
echo ""
