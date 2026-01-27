# SimpleMDM VPN Profile Push Issue - MacBook Air

## Problem Summary

VPN profile is assigned to MacBook Air in SimpleMDM but never gets installed on the device. The profile push silently fails with no error messages in SimpleMDM logs.

## Resolution (2026-01-26)

**Working fix:** switch macOS to a **device-scope EAP IKEv2 profile** (no client certs) and install a separate **device-scope mitmproxy CA** profile.

### Why It Works
- EAP authentication avoids PKCS12 payloads that were rejected silently by User-Approved MDM.
- Both profiles use **device scope** (`PayloadScope=System`).
- Mitmproxy TLS errors disappear when its CA is trusted at device scope (System keychain).

### Steps Applied
1. **EAP VPN profile (device scope):**
   ```bash
   ./macos/scripts/generate-macos-vpn-eap-profile.sh
   ./macos/scripts/push-macos-vpn-eap-profile-mdm.sh
   ```
2. **Mitmproxy CA profile (device scope):**
   ```bash
   ./macos/scripts/generate-macos-mitmproxy-ca-profile.sh
   ./macos/scripts/push-macos-mitmproxy-ca-profile-mdm.sh
   ```
3. **Cleanup:** remove temporary Test VPN profiles from SimpleMDM.

### Verification
- System Settings → VPN shows "Hocuspocus VPN (macOS Device EAP)"
- Logs show:
  - `NESMIKEv2VPNSession ... status changed to connected`
  - `NEIKEv2Provider ... Tunnel Status: UP`
- Mitmproxy logs no longer show `certificate unknown` (remaining blocks are location-policy).

## Device Details

| Property | Value |
|----------|-------|
| Device | MacBook Air (M2, 2023) - Mac14,15 |
| macOS | 26.2 (Build 25C56) |
| Serial | KM2KW1KHWF |
| SimpleMDM ID | 2162127 |
| MDM Enrollment | User-Approved (NOT DEP) |
| Supervised | Yes (`IsSupervised = 1`) |
| Last Seen | Checking in regularly |

## What Works

- Device is enrolled in SimpleMDM (User-Approved MDM)
- Device checks in regularly (last_seen updates)
- MDM enrollment profiles installed:
  - Self Profile (MDM enrollment)
  - SimpleMDM CA
  - SimpleMDM Agent
- Device responds to MDM commands (`QueryDeviceInformation`, `QueryInstalledProfiles`)
- Device shows as supervised

## What Doesn't Work

### SimpleMDM Profile Push
- Profile 218540 "Hocuspocus VPN (Original Cert)" exists in SimpleMDM
- Profile is assigned to device (API shows "Association already exists")
- Device refresh command succeeds
- But profile NEVER appears on device
- No errors in SimpleMDM logs for this device
- Only 3 profiles installed (enrollment-related, no VPN)

## Investigation Results

### Profiles Currently Installed on Device
```
1. Self Profile (com.unwiredmdm.mobileconfig.profile-service) - MDM enrollment
2. SimpleMDM CA (com.unwiredmdm.e03135ca10bc49dc8e0734454c52615c) - Root CA
3. SimpleMDM Agent (com.unwiredmdm.0bdd98442f00469fa6a23bc4400bc7e4) - Agent config
```

### MDM Device Query Response
- `IsSupervised = 1` (device is supervised)
- `MDMOptions.BootstrapTokenAllowed = 1`
- Push token present and valid
- Device responds to all MDM queries

### SimpleMDM API Results
```bash
# Profile association exists
POST /api/v1/custom_configuration_profiles/218540/devices/2162127
{"errors":[{"title":"Association already exists"}]}

# Device refresh succeeds (no error)
POST /api/v1/devices/2162127/refresh
(empty response = success)
```

## Possible Root Causes

### 1. User-Approved MDM Limitations
macOS with User-Approved MDM (not DEP enrolled) has restrictions:
- Some profile types may require user approval
- VPN profiles with certificates may be blocked
- APNs push may work differently than DEP-enrolled devices

**Key Difference**: iPhone is supervised via Apple Configurator with SimpleMDM enrollment (works). MacBook Air is User-Approved MDM only (fails).

### 2. VPN Profile Payload Restrictions
macOS may silently reject certain VPN profile payloads:
- `com.apple.vpn.managed` with AlwaysOn settings
- PKCS12 certificate bundles
- Root CA payloads (`com.apple.security.root`)

### 3. Profile Signing Issues
User-Approved MDM may require additional profile signing that SimpleMDM doesn't provide for VPN profiles.

### 4. macOS 26.2 Changes
macOS 26 may have new MDM restrictions not present in earlier versions.

## Profile Contents (218540)

The profile includes:
1. VPN CA certificate (`com.apple.security.root`)
2. mitmproxy CA certificate (`com.apple.security.root`)
3. Client identity PKCS12 (`com.apple.security.pkcs12`)
4. VPN configuration (`com.apple.vpn.managed` with AlwaysOn)

## Commands Used for Debugging

### On MacBook Air (via SSH)
```bash
# Check MDM enrollment
profiles status -type enrollment

# List installed profiles (requires sudo)
sudo /usr/libexec/mdmclient QueryInstalledProfiles

# Trigger MDM check-in
sudo /usr/libexec/mdmclient QueryDeviceInformation
```

### SimpleMDM API
```bash
API_KEY="<key>"

# Check device status
curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/devices/2162127"

# List profiles
curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/custom_configuration_profiles"

# Push profile to device
curl -s -X POST -u "$API_KEY:" \
    "https://a.simplemdm.com/api/v1/custom_configuration_profiles/218540/devices/2162127"

# Refresh device
curl -s -X POST -u "$API_KEY:" \
    "https://a.simplemdm.com/api/v1/devices/2162127/refresh"
```

## Potential Solutions

### Option 1: Manual VPN Configuration
Skip MDM profile push entirely:
1. Import VPN CA and client certificate to Keychain manually
2. Configure VPN in System Settings manually
3. No AlwaysOn VPN (user can disable)

### Option 2: Apple Configurator Profile Push
Use Apple Configurator 2 via USB to push profile directly (bypasses SimpleMDM).

### Option 3: DEP Enrollment
Requires Apple Business Manager:
1. Add MacBook Air to ABM
2. Assign to SimpleMDM
3. Wipe and re-enroll device
4. Full MDM control including profile push

### Option 4: Profile Signing
Sign the VPN profile with a trusted certificate before uploading to SimpleMDM.

### Option 5: Simplified Profile
Try pushing a minimal profile first:
1. Just VPN config without certificates
2. Certificates already in Keychain from manual import
3. See if SimpleMDM can push VPN-only profiles

## Related Files

- Profile attempted: `vpn-profiles/hocuspocus-vpn-macbook-air.mobileconfig`
- Original working profile (iPhone): `vpn-profiles/hocuspocus-vpn.mobileconfig`
- Previous issue doc: `macos/PROFILE-INSTALLATION-ISSUE.md`

## Comparison: iPhone vs MacBook Air

| Aspect | iPhone | MacBook Air |
|--------|--------|-------------|
| Supervision Method | Apple Configurator | User-Approved MDM |
| DEP Enrolled | No | No |
| SimpleMDM Profile Push | Works | Fails |
| Certificates | Same CA chain | Same CA chain |
| VPN Profile | Installs fine | Never arrives |

## Solution: EAP Authentication Profile

The fix is to use EAP (username/password) authentication instead of certificates for macOS.
This eliminates certificate payloads that User-Approved MDM cannot silently install.

### Why This Works

| Profile Type | Certificate Payloads | User-Approved MDM |
|--------------|---------------------|-------------------|
| Original (cert auth) | Yes (VPN CA, PKCS12, mitmproxy CA) | Fails silently |
| EAP (password auth) | None | Should work |

### Deploy the Fix

**Step 1: Update VPN server to support EAP auth**
```bash
cd /Users/tushar/code/hocuspocus-vpn
make build-push-vpn
kubectl rollout restart daemonset vpn-server -n hocuspocus
```

**Step 2: Push EAP profile via SimpleMDM**
```bash
make macos-vpn-eap-profile-mdm
```

Or manually:
```bash
./macos/scripts/generate-macos-vpn-eap-profile.sh
./macos/scripts/push-macos-vpn-eap-profile-mdm.sh
```

### EAP Credentials (embedded in profile)
- **Username**: `vpnuser`
- **Password**: `Dvq0bsdRYCR1Lz54JJDj7PWihNGVqkui`
- **Fixed IP**: `10.10.10.20` (same as certificate auth)

### Files Changed

| File | Change |
|------|--------|
| `docker/vpn/entrypoint.sh` | Added EAP connection + credentials |
| `macos/scripts/generate-macos-vpn-eap-profile.sh` | New EAP profile generator |
| `macos/scripts/push-macos-vpn-eap-profile-mdm.sh` | New SimpleMDM push script |
| `Makefile` | Added `macos-vpn-eap-profile` and `macos-vpn-eap-profile-mdm` targets |

### Verification

After pushing the profile, check on MacBook Air:
```bash
# Check if profile installed
scutil --nc list

# Check VPN connection
scutil --nc status "Hocuspocus VPN"

# View MDM logs if profile doesn't appear
log show --predicate 'subsystem == "com.apple.ManagedClient"' --last 5m
```

## Related setup docs

- iPhone E2E/Appium/WebDriverAgent setup: `tests/e2e/README.md`

## Previous Next Steps (Archived)

1. ~~Try Option 5: Push VPN-config-only profile (no certs)~~ → Implemented as EAP profile
2. ~~Check SimpleMDM support for User-Approved MDM VPN profile limitations~~ → Root cause confirmed
3. ~~Consider manual VPN setup as workaround~~ → Not needed if EAP works
4. ~~Investigate Apple Configurator USB push as alternative~~ → Fallback if EAP fails
