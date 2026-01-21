# Hocuspocus VPN - macOS Setup

This directory contains configuration and scripts for setting up the Hocuspocus VPN on macOS.

## Overview

The macOS setup consists of two components:

1. **VPN Profile** - IKEv2 VPN with certificate authentication and VPN On-Demand
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
- **Certificate Authentication** - No passwords needed
- **VPN On-Demand** - Auto-connects when network is available
- **Mitmproxy CA** - Included for HTTPS filtering

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

#### Method 2: MDM (SimpleMDM)

1. Enroll Mac in SimpleMDM (requires supervision for enforcement)

2. Push profile:
   ```bash
   make macos-vpn-profile-mdm
   ```

3. Profile installs automatically on enrolled Mac

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
