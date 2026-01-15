#!/bin/bash
# Push VPN profile to iPhone via SimpleMDM (silent install)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE_PATH="${SCRIPT_DIR}/../vpn-profiles/hocuspocus-vpn.mobileconfig"

# SimpleMDM API key (store in environment variable for security)
API_KEY="${SIMPLEMDM_API_KEY:-2IkV3x1TEpS9r6AGtmeyvLlBMvwHzCeJgQY4O8VyTtoss2KR6qVpEZcQqPlmLrLV}"

# Generate fresh profile first
echo "Generating VPN profile..."
"${SCRIPT_DIR}/generate-vpn-profile.sh"

# Check for existing Hocuspocus VPN profile
echo "Checking for existing profile..."
EXISTING_PROFILE=$(curl -s -u "${API_KEY}:" \
  "https://a.simplemdm.com/api/v1/custom_configuration_profiles" | \
  python3 -c "import sys, json; data=json.load(sys.stdin)['data']; profiles=[p for p in data if p['attributes']['name']=='Hocuspocus VPN']; print(profiles[0]['id'] if profiles else '')" 2>/dev/null)

if [ -n "$EXISTING_PROFILE" ]; then
    echo "Deleting existing profile (ID: $EXISTING_PROFILE)..."
    curl -s -X DELETE -u "${API_KEY}:" \
      "https://a.simplemdm.com/api/v1/custom_configuration_profiles/${EXISTING_PROFILE}" > /dev/null
    sleep 2
fi

# Upload new profile
echo "Uploading VPN profile to SimpleMDM..."
PROFILE_ID=$(curl -s -X POST \
  -u "${API_KEY}:" \
  -F "name=Hocuspocus VPN" \
  -F "mobileconfig=@${PROFILE_PATH}" \
  "https://a.simplemdm.com/api/v1/custom_configuration_profiles" | \
  python3 -c "import sys, json; print(json.load(sys.stdin)['data']['id'])")

echo "Profile uploaded (ID: $PROFILE_ID)"

# Get all enrolled devices
echo "Finding enrolled devices..."
DEVICES=$(curl -s -u "${API_KEY}:" \
  "https://a.simplemdm.com/api/v1/devices" | \
  python3 -c "import sys, json; data=json.load(sys.stdin)['data']; print(' '.join([str(d['id']) for d in data if d['attributes']['status']=='enrolled']))")

if [ -z "$DEVICES" ]; then
    echo "ERROR: No enrolled devices found"
    exit 1
fi

# Push to all enrolled devices
for DEVICE_ID in $DEVICES; do
    DEVICE_NAME=$(curl -s -u "${API_KEY}:" \
      "https://a.simplemdm.com/api/v1/devices/${DEVICE_ID}" | \
      python3 -c "import sys, json; print(json.load(sys.stdin)['data']['attributes']['device_name'])" 2>/dev/null)

    echo "Pushing profile to: $DEVICE_NAME (ID: $DEVICE_ID)..."
    curl -s -X POST -u "${API_KEY}:" \
      "https://a.simplemdm.com/api/v1/custom_configuration_profiles/${PROFILE_ID}/devices/${DEVICE_ID}" > /dev/null
done

echo ""
echo "==========================================="
echo "VPN profile pushed to all enrolled devices!"
echo "==========================================="
echo ""
echo "The profile installs automatically on supervised devices."
