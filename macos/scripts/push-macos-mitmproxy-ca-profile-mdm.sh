#!/bin/bash
#
# Push macOS mitmproxy CA profile via SimpleMDM (device scope)
#
# Usage: ./push-macos-mitmproxy-ca-profile-mdm.sh [device_id]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
PROFILE_PATH="$MACOS_DIR/profiles/hocuspocus-proxy-ca-macos.mobileconfig"

# SimpleMDM API Key
API_KEY="2IkV3x1TEpS9r6AGtmeyvLlBMvwHzCeJgQY4O8VyTtoss2KR6qVpEZcQqPlmLrLV"

# Default to MacBook Air
DEVICE_ID="${1:-2162127}"

echo "=== Pushing macOS mitmproxy CA Profile via SimpleMDM ==="
echo ""

# Generate profile if it doesn't exist
if [ ! -f "$PROFILE_PATH" ]; then
    echo "Profile not found. Generating..."
    "$SCRIPT_DIR/generate-macos-mitmproxy-ca-profile.sh"
fi

echo "Target device ID: $DEVICE_ID"
echo ""

# Delete existing mitmproxy CA profiles if present
echo "Checking for existing Proxy CA profile..."
EXISTING_PROFILE=$(curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/custom_configuration_profiles" | \
    python3 -c "import sys, json; data=json.load(sys.stdin)['data']; profiles=[p for p in data if 'Proxy CA' in p['attributes']['name']]; print(profiles[0]['id'] if profiles else '')" 2>/dev/null || echo "")

if [ -n "$EXISTING_PROFILE" ]; then
    echo "Deleting existing Proxy CA profile (ID: $EXISTING_PROFILE)..."
    curl -s -X DELETE -u "$API_KEY:" \
        "https://a.simplemdm.com/api/v1/custom_configuration_profiles/$EXISTING_PROFILE" > /dev/null
    sleep 2
fi

# Upload profile to SimpleMDM (device scope)
echo "Uploading Proxy CA profile to SimpleMDM..."
UPLOAD_RESPONSE=$(curl -s -X POST \
    -u "$API_KEY:" \
    -F "name=Hocuspocus Proxy CA (macOS Device)" \
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
echo "=== Proxy CA Profile Pushed ==="
echo ""
echo "Profile: Hocuspocus Proxy CA (macOS Device)"
echo "Profile ID: $PROFILE_ID"
echo ""
