#!/bin/bash
#
# Push macOS VPN Profile via SimpleMDM
#
# This script uploads the macOS VPN profile to SimpleMDM and pushes it to enrolled Macs.
#
# Usage: ./push-macos-vpn-profile-mdm.sh [device_id]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
PROFILE_PATH="$MACOS_DIR/profiles/hocuspocus-vpn-macos.mobileconfig"

# SimpleMDM API Key (same as iOS)
API_KEY="2IkV3x1TEpS9r6AGtmeyvLlBMvwHzCeJgQY4O8VyTtoss2KR6qVpEZcQqPlmLrLV"

echo "=== Pushing macOS VPN Profile via SimpleMDM ==="
echo ""

# Check if profile exists
if [ ! -f "$PROFILE_PATH" ]; then
    echo "Profile not found. Generating..."
    "$SCRIPT_DIR/generate-macos-vpn-profile.sh"
fi

# Get device ID (either from argument or list devices)
DEVICE_ID="$1"

if [ -z "$DEVICE_ID" ]; then
    echo "Available devices in SimpleMDM:"
    echo ""

    # List all devices
    DEVICES=$(curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/devices" | \
        jq -r '.data[] | "\(.id)\t\(.attributes.name)\t\(.attributes.model)"')

    echo "ID          Name                    Model"
    echo "-------------------------------------------"
    echo "$DEVICES"
    echo ""

    # Filter for Macs
    echo "Mac devices:"
    curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/devices" | \
        jq -r '.data[] | select(.attributes.model | test("Mac|MacBook|iMac|Mac mini|Mac Pro"; "i")) | "\(.id)\t\(.attributes.name)"'

    echo ""
    echo "Usage: $0 <device_id>"
    echo ""
    exit 1
fi

echo "Target device ID: $DEVICE_ID"
echo ""

# Upload profile to SimpleMDM
echo "Uploading profile to SimpleMDM..."
UPLOAD_RESPONSE=$(curl -s -X POST \
    -u "$API_KEY:" \
    -F "name=Hocuspocus VPN (macOS)" \
    -F "mobileconfig=@$PROFILE_PATH" \
    "https://a.simplemdm.com/api/v1/custom_configuration_profiles")

PROFILE_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.data.id // empty')

if [ -z "$PROFILE_ID" ]; then
    echo "Error uploading profile:"
    echo "$UPLOAD_RESPONSE" | jq .
    exit 1
fi

echo "Profile uploaded with ID: $PROFILE_ID"

# Assign profile to device
echo "Assigning profile to device $DEVICE_ID..."
ASSIGN_RESPONSE=$(curl -s -X POST \
    -u "$API_KEY:" \
    "https://a.simplemdm.com/api/v1/custom_configuration_profiles/$PROFILE_ID/devices/$DEVICE_ID")

# Push profile to device
echo "Pushing profile to device..."
PUSH_RESPONSE=$(curl -s -X POST \
    -u "$API_KEY:" \
    "https://a.simplemdm.com/api/v1/devices/$DEVICE_ID/push_custom_configuration_profiles")

echo ""
echo "=== Profile Pushed ==="
echo ""
echo "The VPN profile has been pushed to device $DEVICE_ID"
echo ""
echo "On the Mac:"
echo "  1. Check System Settings > Privacy & Security > Profiles"
echo "  2. The profile should install automatically (or prompt for approval)"
echo "  3. Trust the Mitmproxy CA in Keychain Access:"
echo "     - Open Keychain Access"
echo "     - Find 'mitmproxy' certificate in System keychain"
echo "     - Double-click > Trust > SSL: Always Trust"
echo ""
