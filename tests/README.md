# End-to-End Tests

These E2E tests run on a **real iOS device** connected to the VPN proxy to verify the full system works correctly.

If you're looking for the detailed setup guide, see `tests/e2e/README.md`.

## Quick Start

```bash
cd /Users/tushar/code/hocuspocus-vpn

# Start Appium
make appium

# Full E2E suite (test DB)
make test-e2e

# Production verification suite (prod DB)
make verify-vpn-appium-prod
```

## Running from MacBook Pro (Tests on MacBook Air via SSH)

The iPhone is connected to the MacBook Air. To run tests remotely:

```bash
# SSH uses Tailscale hostname (IP can change)
ssh tushru2004@tushru2004s-macbook-air

# IMPORTANT: SSH doesn't load /opt/homebrew/bin by default
# Always set PATH for Homebrew tools (node, npm, appium):
export PATH=/opt/homebrew/bin:$PATH

# Kill and restart Appium (fixes "port 4723 in use" errors)
pkill -f appium; sleep 2
nohup appium > /tmp/appium.log 2>&1 &
sleep 3 && pgrep -l node  # Verify it's running

# One-liner from MacBook Pro:
ssh tushru2004@tushru2004s-macbook-air "pkill -f appium; sleep 2; export PATH=/opt/homebrew/bin:\$PATH && nohup appium > /tmp/appium.log 2>&1 & sleep 3 && pgrep -l node"

# Run tests remotely:
ssh tushru2004@tushru2004s-macbook-air "export PATH=/opt/homebrew/bin:\$PATH && cd /Users/tushru2004/hocuspocus-vpn && source .venv/bin/activate && USE_PREBUILT_WDA=true IOS_DERIVED_DATA_PATH=/tmp/wda-dd python -m pytest tests/e2e_prod/test_verify_vpn.py -v --tb=short"
```

## Prerequisites

### 1. Hardware Requirements
- Mac with Xcode installed
- Real iPhone connected via USB with:
  - IKEv2 VPN profile installed and connected
  - Developer mode enabled
  - Trusted developer certificate

### 2. Software Requirements

```bash
# One-time: Appium + iOS driver
npm install -g appium
appium driver install xcuitest

# One-time: python deps (repo venv)
cd /Users/tushar/code/hocuspocus-vpn
make test-e2e-install
```

### 3. VPN/Cluster Running (GKE)

Ensure the GKE workloads are running:

```bash
cd /Users/tushar/code/hocuspocus-vpn
make startgcvpn
make pods
```

The tests will fail with a timeout error if the VPN server is not reachable.

### 4. WebDriverAgent Setup (One-time, Critical!)

WebDriverAgent (WDA) must be built and installed on your iPhone. **This is the most common source of test failures.**

#### Step-by-step Setup:

1. **Open WebDriverAgent in Xcode:**
   ```bash
   open ~/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj
   ```

2. **Select the WebDriverAgentRunner target** (not IntegrationApp)

3. **Configure Signing:**
   - Go to **Signing & Capabilities** tab
   - Select your Team (personal or organization)
   - Set a unique Bundle Identifier (e.g., `com.yourname.WebDriverAgentRunner`)

   > **Important:** Free Apple Developer accounts have a limit of 10 App IDs per 7 days. If you hit this limit, reuse an existing Bundle ID.

4. **Select your iPhone as the target device:**
   - Click the device dropdown next to the scheme selector
   - Choose your connected iPhone

5. **Build and run WebDriverAgent:**
   - Press **Cmd+U** (Product → Test)
   - This builds WDA and installs it on your iPhone

6. **Trust the developer certificate on iPhone:**
   - Go to Settings → General → VPN & Device Management
   - Find your developer certificate and tap "Trust"

## Test Configuration

Tests are configured for a specific device. Update these values in `test_ios_flows.py` if using a different device:

```python
options.platform_version = "18.7.3"
options.device_name = "Tushar's iPhone"
options.udid = "00008020-0004695621DA002E"
options.updated_wda_bundle_id = "com.hocuspocus.WebDriverAgentRunner"
```

To find your device info:
```bash
# List connected devices
xcrun xctrace list devices

# Get UDID
idevice_id -l
```

## Test Cases

| Test | Description | What it Verifies |
|------|-------------|------------------|
| `test_whitelisted_domain_loads` | Navigate to Google | Whitelisted domains load correctly |
| `test_non_whitelisted_domain_blocked` | Navigate to Twitter | Non-whitelisted domains are blocked |
| `test_whitelisted_youtube_channel_plays` | Play JRE video | Whitelisted YouTube channels work |
| `test_non_whitelisted_youtube_video_blocked` | Play non-whitelisted video | Non-whitelisted YouTube videos blocked |
| `test_youtube_url_query_params_not_duplicated` | Video URL with params | Regression: URL query params not duplicated |
| `test_google_signin_flow` | Access Google sign-in | OAuth flows work through proxy |
| `test_location_overlay_appears_and_dismissible` | Check location overlay | Proxy-injected overlay appears |
| `test_location_allowed_outside_blocked_zones` | Browse outside blocked zone | Location check allows browsing |

## Database Seeding

Tests automatically seed the database with test data via `conftest.py`. The seed data includes:

**Allowed Hosts:**
- google.com, youtube.com, github.com, amazon.com
- accounts.google.com, googleapis.com, gstatic.com, googleusercontent.com

**YouTube Channels:**
- UC_x5XG1OV2P6uZZ5FSM9Ttw (Google Developers)
- UCzQUP1qoWDoEbmsQxvdjxgQ (Joe Rogan Experience)

**Blocked Locations:**
- Test School (San Francisco) - for testing location blocking

## Troubleshooting

### Understanding Test Results: Why is X Blocked/Allowed?

The tests verify **two separate filtering mechanisms**:

1. **Global Domain Whitelist Tests** (`test_google_allowed`, `test_twitter_blocked`)
   - `google.com` → allowed because it's in `allowed_hosts` table
   - `twitter.com` → blocked because it's NOT in `allowed_hosts` table
   - **Location doesn't matter** for these tests

2. **Location Whitelist Tests** (`TestLocationWhitelist`)
   - Only run when physically at a blocked location (e.g., Social Hub Vienna)
   - Test that per-location whitelist domains work at blocked locations

**To check what's whitelisted:**
```bash
# Global whitelist
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "SELECT domain FROM allowed_hosts WHERE enabled = true ORDER BY domain;"

# Blocked locations
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "SELECT name, latitude, longitude, radius_meters FROM blocked_locations;"

# Current device location (SimpleMDM polling)
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "SELECT device_id, latitude, longitude, fetched_at FROM device_locations;"
```

### How SimpleMDM Location Tracking Works

```
SimpleMDM polls iPhone location every 30 seconds
        ↓
location-poller sidecar fetches from SimpleMDM API
        ↓
Stores in `device_locations` table
        ↓
Proxy reads location on each request (no JavaScript injection needed)
```

Check location-poller logs:
```bash
kubectl logs -n hocuspocus deployment/mitmproxy -c location-poller --tail=20
```

### Testing Location-Based Blocking (Fake Location Injection)

You don't need to be physically at a blocked location to test location-based blocking.
The tests can **inject fake locations directly into the database**.

```python
# In test:
def test_at_blocked_location(fake_location):
    fake_location("social_hub_vienna")  # Inject fake location
    # ... test runs with device "at" Social Hub Vienna ...
    # Location auto-restored after test
```

**Available fake locations:**
- `social_hub_vienna` - The Social Hub Vienna (lat=48.222, lng=16.390)
- `john_harris` - John Harris Fitness (lat=48.201, lng=16.364)
- `test_school_sf` - Test School SF (lat=37.774, lng=-122.419)

**Or use custom coordinates:**
```python
fake_location(lat=48.123, lng=16.456)
```

**Manual location injection (for debugging):**
```bash
# Set device to Social Hub Vienna
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "UPDATE device_locations SET latitude=48.222861, longitude=16.390007 WHERE device_id='2154382';"

# Restore to real location (SimpleMDM will overwrite in ~30s anyway)
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "SELECT * FROM device_locations;"
```

### Error: "xcodebuild failed with code 65"

**Possible causes:**

1. **iPhone has not trusted the Developer App certificate**
   - Solution: Settings → General → VPN & Device Management → Trust developer cert

2. **"The identity used to sign the executable is no longer valid"**
   - The signing certificate expired or mismatched
   - Solution: In Xcode, clean build folder (Cmd+Shift+K), rebuild WDA (Cmd+U)

3. **"The file couldn't be opened because it doesn't exist"**
   - Wrong target built (IntegrationApp instead of WebDriverAgentRunner)
   - Solution: In Xcode, select **WebDriverAgentRunner** scheme, then Cmd+U

4. **Provisioning profile issues**
   - Solution: Xcode → Signing & Capabilities → Select your Team → let Xcode manage signing

**Full rebuild steps:**
1. Open WebDriverAgent.xcodeproj in Xcode:
   ```bash
   open ~/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj
   ```
2. Select **WebDriverAgentRunner** scheme (not IntegrationApp)
3. Select your Team in Signing & Capabilities
4. Set Bundle Identifier (e.g., `com.yourname.WebDriverAgentRunner`)
5. Select your iPhone as target device
6. Press **Cmd+U** to build and run tests
7. Trust developer cert on iPhone if prompted

### Error: "Maximum App ID limit reached"

**Cause:** Free Apple Developer accounts can only create 10 App IDs per 7 days.

**Solution:**
1. Check existing App IDs in WebDriverAgent project:
   ```bash
   grep -r "PRODUCT_BUNDLE_IDENTIFIER" ~/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/*.xcodeproj/project.pbxproj
   ```
2. Reuse an existing Bundle ID instead of creating a new one
3. Or wait 7 days for the limit to reset

### Error: "VPN server not responding" / Timeout

**Cause:** GKE VPN/mitmproxy isn’t running or the device isn’t actually connected to VPN.

**Solution:**
1. Start cluster: `make startgcvpn`
2. Verify pods: `make pods`
3. Verify iPhone VPN is connected (Always-On profile active)

### Error: "Port #8100 is occupied" or "Port 4723 in use"

**Cause:** A previous WebDriverAgent/Appium session is still running.

**Solution:**
```bash
# Kill Appium and restart
pkill -f appium
sleep 2
appium

# If running via SSH to MacBook Air (must set PATH):
ssh tushru2004@tushru2004s-macbook-air "pkill -f appium; sleep 2; export PATH=/opt/homebrew/bin:\$PATH && nohup appium > /tmp/appium.log 2>&1 & sleep 3 && pgrep -l node"
```

### Error: "Unable to launch WebDriverAgent"

**Cause:** WDA needs to be rebuilt or the device needs to trust the certificate.

**Solution:**
1. On iPhone: Settings → General → VPN & Device Management → Trust your developer certificate
2. In Xcode: Clean build folder (Cmd+Shift+K) and rebuild WDA (Cmd+U)
3. Ensure `usePrebuiltWDA: True` is set in test config

### Tests pass on simulator but fail on real device

**Cause:** Simulator tests don't go through the VPN proxy.

**Explanation:**
- iOS Simulator cannot connect to IKEv2 VPN
- Only real devices with VPN connected will test actual proxy functionality
- Simulator tests will show "positive" results (sites load) but won't test blocking

### Blocking tests fail (sites load instead of being blocked)

**Cause:** VPN is not connected on the iPhone.

**Solution:**
1. Check iPhone Settings → VPN → Ensure VPN is connected
2. Clear Safari cache: Settings → Safari → Clear History and Website Data
3. Check proxy logs: `make logs`

## Common Issues We Encountered

### 1. WebDriverAgent Build Failures

The most common issue was WebDriverAgent failing to build with "xcodebuild failed with code 65". This was resolved by:

1. Opening WebDriverAgent.xcodeproj directly in Xcode
2. Manually configuring signing for WebDriverAgentRunner target
3. Building and running on the device from Xcode first (Cmd+U)
4. Setting `usePrebuiltWDA: True` in the test configuration

### 2. App ID Limit

We hit the 10 App ID limit on free Apple Developer accounts. The WebDriverAgent project creates multiple bundle IDs:
- com.hocuspocus.WebDriverAgentLib
- com.hocuspocus.WebDriverAgentRunner
- com.hocuspocus.IntegrationApp
- etc.

**Fix:** Reuse existing bundle IDs instead of creating new ones.

### 3. VPN Server Not Running

Tests would timeout trying to connect to the VPN server IP. The fixture checks VPN server reachability before running tests.

**Fix:** Ensure EC2 instance is running with `terraform apply`.

### 4. Simulator vs Real Device Confusion

Tests behave differently on simulator vs real device:
- **Simulator:** No VPN connection → no proxy → no blocking → tests pass incorrectly
- **Real device:** VPN connected → proxy active → blocking works → tests accurate

**Fix:** Always run E2E tests on real device with VPN connected.

### 5. Port 8100 Stuck

After test failures, WebDriverAgent sometimes leaves port 8100 occupied.

**Fix:** Kill and restart Appium: `pkill -f appium && appium`

## Running Tests

### Using Makefile (Recommended)
```bash
# Run all E2E tests
make test-e2e

# Run main flow tests only (with autoAcceptAlerts)
make test-e2e-flows

# Run location overlay tests only (without autoAcceptAlerts)
make test-e2e-overlay

# Run simulator tests (currently skipped)
make test-simulator
```

### Using pytest directly
```bash
# Full test suite
PYTHONPATH=src pytest tests/e2e/ -v

# Single test
PYTHONPATH=src pytest tests/e2e/test_ios_flows.py::TestIOSProxyFlows::test_whitelisted_domain_loads -v

# With debug output
PYTHONPATH=src pytest tests/e2e/ -v -s
```

## Test Files

| File | Tests | autoAcceptAlerts | Purpose |
|------|-------|------------------|---------|
| `test_ios_flows.py` | 6 | Yes | Main proxy flow tests |
| `test_location_overlay.py` | 2 | No | Location overlay appearance tests |

### Expected Results

```
tests/e2e/test_ios_flows.py::TestIOSProxyFlows::test_whitelisted_domain_loads PASSED
tests/e2e/test_ios_flows.py::TestIOSProxyFlows::test_non_whitelisted_domain_blocked PASSED
tests/e2e/test_ios_flows.py::TestIOSProxyFlows::test_jre_video_plays PASSED
tests/e2e/test_ios_flows.py::TestIOSProxyFlows::test_non_jre_youtube_video_blocked PASSED
tests/e2e/test_ios_flows.py::TestIOSProxyFlows::test_google_signin_flow PASSED
tests/e2e/test_ios_flows.py::TestIOSProxyFlows::test_location_overlay_appears_and_dismissible PASSED
tests/e2e/test_ios_flows.py::TestIOSProxyFlows::test_location_allowed_outside_blocked_zones PASSED

======================== 7 passed in ~60s =========================
```
