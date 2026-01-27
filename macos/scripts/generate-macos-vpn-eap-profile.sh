#!/bin/bash
#
# Generate macOS VPN Profile with EAP Authentication (.mobileconfig)
#
# This creates an IKEv2 VPN profile that uses username/password (EAP-MSCHAPv2)
# instead of certificates. This is specifically for macOS devices enrolled via
# User-Approved MDM where SimpleMDM cannot push certificate payloads.
#
# Benefits:
# - No client certificate payloads (only VPN CA for server validation)
# - Can be pushed via SimpleMDM to User-Approved MDM devices
# - Still uses server certificate verification for security
#
# Usage: ./generate-macos-vpn-eap-profile.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$MACOS_DIR")"
OUTPUT_DIR="$MACOS_DIR/profiles"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

echo "=== Generating macOS VPN EAP Profile ==="
echo ""

# Get VPN server IP
VPN_IP=$(kubectl get svc vpn-service -n hocuspocus -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
if [ -z "$VPN_IP" ]; then
    echo "Error: Could not get VPN service IP. Is the cluster running?"
    exit 1
fi
echo "VPN Server IP: $VPN_IP"

# EAP Credentials (must match VPN server config)
EAP_USERNAME="vpnuser"

# Get VPN CA certificate for server validation
echo "Fetching VPN CA certificate..."
VPN_POD=$(kubectl get pods -n hocuspocus -l app=vpn-server -o jsonpath='{.items[0].metadata.name}')
if [ -z "$VPN_POD" ]; then
    echo "Error: VPN pod not found"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

kubectl exec -n hocuspocus "$VPN_POD" -c strongswan -- cat /etc/ipsec.d/cacerts/ca-cert.pem > "$TEMP_DIR/vpn-ca.pem" 2>/dev/null
if [ ! -s "$TEMP_DIR/vpn-ca.pem" ]; then
    echo "Error: Could not fetch VPN CA certificate"
    exit 1
fi
VPN_CA_BASE64=$(base64 -i "$TEMP_DIR/vpn-ca.pem" | tr -d '\n')
echo "VPN CA certificate fetched"

# Get mitmproxy CA certificate for HTTPS interception
echo "Fetching mitmproxy CA certificate..."
MITMPROXY_POD=$(kubectl get pods -n hocuspocus -l app=mitmproxy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
MITMPROXY_CA_BASE64=""
if [ -n "$MITMPROXY_POD" ]; then
    kubectl exec -n hocuspocus "$MITMPROXY_POD" -- cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > "$TEMP_DIR/mitmproxy-ca.pem" 2>/dev/null || true
fi
if [ -s "$TEMP_DIR/mitmproxy-ca.pem" ]; then
    MITMPROXY_CA_BASE64=$(base64 -i "$TEMP_DIR/mitmproxy-ca.pem" | tr -d '\n')
    echo "mitmproxy CA certificate fetched"
else
    echo "Warning: Could not fetch mitmproxy CA certificate (HTTPS interception will fail)"
fi

# Generate UUIDs for profile
PROFILE_UUID=$(uuidgen)
VPN_UUID=$(uuidgen)
CA_UUID=$(uuidgen)
MITMPROXY_UUID=$(uuidgen)

# Profile output path
PROFILE_PATH="$OUTPUT_DIR/hocuspocus-vpn-macos-eap.mobileconfig"

echo "Generating EAP profile with VPN CA certificate..."

cat > "$PROFILE_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <!-- VPN CA Certificate for server validation -->
        <dict>
            <key>PayloadCertificateFileName</key>
            <string>vpn-ca.pem</string>
            <key>PayloadContent</key>
            <data>$VPN_CA_BASE64</data>
            <key>PayloadDescription</key>
            <string>VPN Certificate Authority for server validation</string>
            <key>PayloadDisplayName</key>
            <string>Hocuspocus VPN CA</string>
            <key>PayloadIdentifier</key>
            <string>com.hocuspocus.vpn.macos.eap.ca</string>
            <key>PayloadType</key>
            <string>com.apple.security.root</string>
            <key>PayloadUUID</key>
            <string>$CA_UUID</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
EOF

if [ -n "$MITMPROXY_CA_BASE64" ]; then
cat >> "$PROFILE_PATH" << EOF
        <!-- mitmproxy CA Certificate for HTTPS interception -->
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
            <string>com.hocuspocus.proxy.ca</string>
            <key>PayloadType</key>
            <string>com.apple.security.root</string>
            <key>PayloadUUID</key>
            <string>$MITMPROXY_UUID</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
EOF
fi

cat >> "$PROFILE_PATH" << EOF
        <!-- IKEv2 VPN Configuration with EAP Authentication and On Demand -->
        <dict>
            <key>PayloadDisplayName</key>
            <string>Hocuspocus VPN (macOS EAP - Always On)</string>
            <key>PayloadIdentifier</key>
            <string>com.hocuspocus.vpn.macos.eap.ikev2</string>
            <key>PayloadType</key>
            <string>com.apple.vpn.managed</string>
            <key>PayloadUUID</key>
            <string>$VPN_UUID</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>UserDefinedName</key>
            <string>Hocuspocus VPN</string>
            <key>VPNType</key>
            <string>IKEv2</string>
            <!-- VPN On Demand - Auto-connect and prevent user from disabling -->
            <key>OnDemandEnabled</key>
            <integer>1</integer>
            <key>OnDemandUserOverrideDisabled</key>
            <true/>
            <key>OnDemandRules</key>
            <array>
                <!-- Always connect on any network -->
                <dict>
                    <key>Action</key>
                    <string>Connect</string>
                </dict>
            </array>
            <key>IKEv2</key>
            <dict>
                <key>RemoteAddress</key>
                <string>$VPN_IP</string>
                <key>RemoteIdentifier</key>
                <string>$VPN_IP</string>
                <key>LocalIdentifier</key>
                <string>$EAP_USERNAME</string>
                <key>AuthenticationMethod</key>
                <string>None</string>
                <key>ExtendedAuthEnabled</key>
                <true/>
                <key>AuthName</key>
                <string>$EAP_USERNAME</string>
                <key>AuthPassword</key>
                <string>Dvq0bsdRYCR1Lz54JJDj7PWihNGVqkui</string>
                <key>ServerCertificateIssuerCommonName</key>
                <string>Hocuspocus VPN CA</string>
                <key>ServerCertificateCommonName</key>
                <string>$VPN_IP</string>
                <key>EnablePFS</key>
                <true/>
                <key>IKESecurityAssociationParameters</key>
                <dict>
                    <key>EncryptionAlgorithm</key>
                    <string>AES-256</string>
                    <key>IntegrityAlgorithm</key>
                    <string>SHA2-256</string>
                    <key>DiffieHellmanGroup</key>
                    <integer>19</integer>
                </dict>
                <key>ChildSecurityAssociationParameters</key>
                <dict>
                    <key>EncryptionAlgorithm</key>
                    <string>AES-256</string>
                    <key>IntegrityAlgorithm</key>
                    <string>SHA2-256</string>
                    <key>DiffieHellmanGroup</key>
                    <integer>19</integer>
                </dict>
            </dict>
        </dict>
    </array>

    <key>PayloadDescription</key>
    <string>Hocuspocus VPN configuration for macOS with Always-On VPN (auto-connect, user cannot disable)</string>
    <key>PayloadDisplayName</key>
    <string>Hocuspocus VPN (macOS Always-On)</string>
    <key>PayloadIdentifier</key>
    <string>com.hocuspocus.vpn.macos.eap.alwayson</string>
    <key>PayloadScope</key>
    <string>System</string>
    <key>PayloadOrganization</key>
    <string>Hocuspocus</string>
    <key>PayloadRemovalDisallowed</key>
    <true/>
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
echo "=== macOS VPN EAP Profile Generated ==="
echo "Profile: $PROFILE_PATH"
echo ""
echo "This profile uses EAP authentication (username/password)."
echo "No client certificates; includes VPN CA for server validation."
echo ""
echo "Credentials embedded in profile:"
echo "  Username: $EAP_USERNAME"
echo "  Password: (embedded)"
echo ""
echo "To deploy via SimpleMDM:"
echo "  $SCRIPT_DIR/push-macos-vpn-eap-profile-mdm.sh"
echo ""
echo "IMPORTANT: The VPN server must be updated to support EAP auth:"
echo "  cd $PROJECT_DIR && make build-push-vpn deploy-vpn"
echo ""
