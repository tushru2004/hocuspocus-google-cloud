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
DEBUG_LOG_PATH="/Users/tushar/code/.cursor/debug.log"
RUN_ID="${RUN_ID:-pre-fix}"

log_ndjson() {
    local hypothesis_id="$1"
    local location="$2"
    local message="$3"
    local data="$4"
    local timestamp
    timestamp=$(($(date +%s) * 1000))
    printf '%s\n' "{\"sessionId\":\"debug-session\",\"runId\":\"${RUN_ID}\",\"hypothesisId\":\"${hypothesis_id}\",\"location\":\"${location}\",\"message\":\"${message}\",\"data\":${data},\"timestamp\":${timestamp}}" >> "$DEBUG_LOG_PATH"
}

# SimpleMDM API Key (same as iOS)
API_KEY="2IkV3x1TEpS9r6AGtmeyvLlBMvwHzCeJgQY4O8VyTtoss2KR6qVpEZcQqPlmLrLV"

echo "=== Pushing macOS VPN Profile via SimpleMDM ==="
echo ""

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

#region agent log
log_ndjson "H1" "push-macos-vpn-profile-mdm.sh:58" "script_start" "{\"deviceId\":\"${DEVICE_ID}\",\"profilePath\":\"${PROFILE_PATH}\"}"
#endregion agent log

# Upload profile to SimpleMDM
echo "Uploading profile to SimpleMDM..."
PROFILE_EXISTS="false"
PROFILE_GENERATED="false"
if [ -f "$PROFILE_PATH" ]; then
    PROFILE_EXISTS="true"
else
    PROFILE_GENERATED="true"
fi

if [ "$PROFILE_GENERATED" = "true" ]; then
    "$SCRIPT_DIR/generate-macos-vpn-profile.sh"
fi

PROFILE_SIZE_BYTES=0
if [ -f "$PROFILE_PATH" ]; then
    PROFILE_SIZE_BYTES=$(stat -f%z "$PROFILE_PATH")
fi

#region agent log
log_ndjson "H1" "push-macos-vpn-profile-mdm.sh:78" "profile_ready" "{\"profileExists\":${PROFILE_EXISTS},\"profileGenerated\":${PROFILE_GENERATED},\"profileSizeBytes\":${PROFILE_SIZE_BYTES}}"
#endregion agent log

UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -u "$API_KEY:" \
    -F "name=Hocuspocus VPN (macOS)" \
    -F "mobileconfig=@$PROFILE_PATH" \
    "https://a.simplemdm.com/api/v1/custom_configuration_profiles")

UPLOAD_HTTP="${UPLOAD_RESPONSE##*$'\n'}"
UPLOAD_BODY="${UPLOAD_RESPONSE%$'\n'*}"
PROFILE_ID=$(echo "$UPLOAD_BODY" | jq -r '.data.id // empty')

#region agent log
log_ndjson "H1" "push-macos-vpn-profile-mdm.sh:97" "upload_response" "{\"uploadHttp\":\"${UPLOAD_HTTP}\",\"profileId\":\"${PROFILE_ID}\"}"
#endregion agent log

if [ -z "$PROFILE_ID" ]; then
    echo "Error uploading profile:"
    echo "$UPLOAD_BODY" | jq .
    exit 1
fi

echo "Profile uploaded with ID: $PROFILE_ID"

# Assign profile to device
echo "Assigning profile to device $DEVICE_ID..."
ASSIGN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -u "$API_KEY:" \
    "https://a.simplemdm.com/api/v1/custom_configuration_profiles/$PROFILE_ID/devices/$DEVICE_ID")

ASSIGN_HTTP="${ASSIGN_RESPONSE##*$'\n'}"
ASSIGN_BODY="${ASSIGN_RESPONSE%$'\n'*}"
ASSIGN_ERROR=$(echo "$ASSIGN_BODY" | jq -r '.errors[0].title // empty')

# Push profile to device
echo "Pushing profile to device..."
PUSH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -u "$API_KEY:" \
    "https://a.simplemdm.com/api/v1/devices/$DEVICE_ID/push_custom_configuration_profiles")

PUSH_HTTP="${PUSH_RESPONSE##*$'\n'}"
PUSH_BODY="${PUSH_RESPONSE%$'\n'*}"
PUSH_ERROR=$(echo "$PUSH_BODY" | jq -r '.errors[0].title // empty')

#region agent log
log_ndjson "H4" "push-macos-vpn-profile-mdm.sh:123" "assign_push_response" "{\"assignHttp\":\"${ASSIGN_HTTP}\",\"assignError\":\"${ASSIGN_ERROR}\",\"pushHttp\":\"${PUSH_HTTP}\",\"pushError\":\"${PUSH_ERROR}\"}"
#endregion agent log

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
