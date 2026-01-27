# Hocuspocus VPN - macOS Setup

This directory contains configuration and scripts for setting up the Hocuspocus VPN on macOS.

## Related (iPhone E2E / Appium)

If you’re setting up **iPhone E2E tests** (WebDriverAgent + Appium + VPN profile + trust steps), see `tests/e2e/README.md` in the repo root.

## Overview

The macOS setup consists of two components:

1. **VPN Profile** - IKEv2 VPN (EAP for User-Approved MDM, cert auth for supervised devices)
2. **pf Kill Switch** (optional) - Firewall rules that block all traffic except VPN

## Quick Start

```bash
# Generate VPN profile
make macos-vpn-profile

# Install profile manually (double-click) or via MDM
make macos-vpn-profile-mdm

# Optional: Install kill switch (blocks internet without VPN)
make macos-pf-killswitch
make macos-pf-install
```

## VPN Profile

### Features

- **IKEv2 Protocol** - Same as iOS setup
- **Authentication Options**:
  - **EAP (User-Approved MDM)** - username/password, no client cert payloads
  - **Certificate (Supervised / manual)** - PKCS12 client identity
- **VPN On-Demand** - Auto-connects when network is available
- **Mitmproxy CA** - Install via separate device-scope profile for macOS

### Installation Methods

#### Method 1: Manual Installation

1. Generate the profile:
   ```bash
   make macos-vpn-profile
   ```

2. Double-click `macos/profiles/hocuspocus-vpn-macos.mobileconfig`

3. Open **System Settings > Privacy & Security > Profiles**

4. Click **Install** on "Hocuspocus VPN (macOS)"

5. Trust the Mitmproxy CA:
   - Open **Keychain Access**
   - Find "mitmproxy" in System keychain
   - Double-click > Trust > SSL: **Always Trust**

6. Install Location Sender Daemon (for Block Page handling):
   The MacBook uses a custom Python script to push location data to the VPN (since MDM location polling is unreliable on macOS).
   
   a. Install Python dependencies:
      ```bash
      /usr/bin/python3 -m venv ~/hocuspocus-location-daemon/venv
      ~/hocuspocus-location-daemon/venv/bin/pip install pyobjc-framework-CoreLocation requests
      ```
   
   b. Copy script:
      Copy `macos/location-daemon/location_sender.py` to `~/hocuspocus-location-daemon/location_sender.py`
   
   c. Install LaunchAgent (runs on login):
      Copy `macos/location-daemon/com.hocuspocus.location-sender-user.plist` to `~/Library/LaunchAgents/com.hocuspocus.location-sender.plist`
   
   d. Load the Agent:
      ```bash
      launchctl load ~/Library/LaunchAgents/com.hocuspocus.location-sender.plist
      ```

   e. Grant Permissions:
      - A popup will appear asking for Location access for Python. Click "Allow".
      - Or go to System Settings > Privacy & Security > Location Services > Enable for Python/Terminal.

#### Method 2: MDM (SimpleMDM)

1. Enroll Mac in SimpleMDM (requires supervision for enforcement)

2. Push **EAP device-scope** profile:
   ```bash
   make macos-vpn-eap-profile-mdm
   ```

3. Install **mitmproxy CA** at device scope:
   ```bash
   ./macos/scripts/push-macos-mitmproxy-ca-profile-mdm.sh
   ```

4. Profile installs automatically on enrolled Mac

5. **CRITICAL**: Install Location Sender Daemon
   Even with MDM, the MacBook needs the location sender script to ensure the blocking page doesn't show up. MDM location polling is often too slow/stale for the proxy's strict checks.
   Follow step 6 from the "Manual Installation" section above.

## pf Kill Switch (Optional)

The pf (Packet Filter) kill switch blocks ALL internet traffic unless connected to the VPN.

### How It Works

```
┌─────────────────────────────────────────────────────────┐
│  pf Firewall Rules                                      │
├─────────────────────────────────────────────────────────┤
│  block drop all                    # Block everything   │
│  pass on lo0                       # Allow loopback     │
│  pass to VPN_SERVER port 500,4500  # Allow IKEv2       │
│  pass on utun0                     # Allow VPN tunnel   │
└─────────────────────────────────────────────────────────┘
```

### Installation

```bash
# Generate pf configuration
make macos-pf-killswitch

# Install (requires sudo, enables on boot)
make macos-pf-install

# Uninstall (restores normal networking)
make macos-pf-uninstall
```

### Manual Control

```bash
# Check current rules
sudo pfctl -s rules

# Disable temporarily
sudo pfctl -d

# Re-enable
sudo pfctl -e

# Reload rules
sudo pfctl -f /etc/pf.d/hocuspocus-pf.conf
```

## Differences from iOS

| Feature | iOS | macOS |
|---------|-----|-------|
| Always-On VPN | Native (`AlwaysOn` key) | Not available |
| Kill Switch | Built into Always-On | Requires pf firewall |
| Auto-reconnect | Built-in | VPN On-Demand |
| User can disable | No (supervised) | Yes (unless MDM enforced) |
| Profile enforcement | MDM required | MDM recommended |

## Troubleshooting

### VPN Won't Connect

1. Check VPN server is running:
   ```bash
   make status
   ```

2. Verify certificates:
   - Open Keychain Access
   - Check "Hocuspocus VPN CA" is in System keychain
   - Check "Hocuspocus VPN Client" certificate exists

3. Check VPN logs:
   ```bash
   make logs-vpn
   ```

### Kill Switch Blocking Everything

1. Temporarily disable:
   ```bash
   sudo pfctl -d
   ```

2. Check VPN connection:
   - System Settings > VPN > Hocuspocus VPN > Connect

3. Re-enable after VPN is connected:
   ```bash
   sudo pfctl -e
   ```

### Mitmproxy CA Not Trusted

1. Open **Keychain Access**
2. Select **System** keychain (left sidebar)
3. Find "mitmproxy" certificate
4. Double-click > Trust > SSL: **Always Trust**
5. Enter admin password

## Files

```
macos/
├── profiles/
│   ├── hocuspocus-vpn-macos.mobileconfig  # VPN profile
│   └── hocuspocus-pf.conf                  # pf firewall rules
├── scripts/
│   ├── generate-macos-vpn-profile.sh      # Generate VPN profile
│   ├── generate-pf-killswitch.sh          # Generate pf config
│   ├── push-macos-vpn-profile-mdm.sh      # Push via SimpleMDM
│   ├── install-pf-killswitch.sh           # Install pf rules
│   └── uninstall-pf-killswitch.sh         # Remove pf rules
├── launchdaemons/
│   └── com.hocuspocus.pf-killswitch.plist # Auto-enable pf on boot
└── README.md
```
