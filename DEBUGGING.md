# Hocuspocus VPN - Debugging & Operations Guide

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              GOOGLE CLOUD PLATFORM                                   │
│                           Project: hocuspocus-vpn                                    │
│                           Region: europe-west1-b                                     │
│                                                                                      │
│  ┌────────────────────────────────────────────────────────────────────────────────┐ │
│  │                     GKE CLUSTER: hocuspocus-vpn                                 │ │
│  │                  Namespace: hocuspocus                                          │ │
│  │                                                                                  │ │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │ │
│  │  │                        NODE (e2-standard-2 spot x2)                       │  │ │
│  │  │                                                                            │  │ │
│  │  │   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐      │  │ │
│  │  │   │   VPN SERVER    │    │   MITMPROXY     │    │   PostgreSQL    │      │  │ │
│  │  │   │  (StrongSwan)   │    │  (Transparent)  │    │   (Database)    │      │  │ │
│  │  │   │                 │    │                 │    │                 │      │  │ │
│  │  │   │ IKEv2 + Certs   │───▶│ HTTP/S Proxy   │───▶│ allowed_hosts   │      │  │ │
│  │  │   │ 10.10.10.0/24   │    │ Port 8080       │    │ youtube_channels│      │  │ │
│  │  │   │                 │    │ YouTube Filter  │    │ blocked_locations│     │  │ │
│  │  │   │ hostNetwork     │    │ hostNetwork     │    │                 │      │  │ │
│  │  │   └────────┬────────┘    └────────┬────────┘    └─────────────────┘      │  │ │
│  │  │            │                      │                                        │  │ │
│  │  │   iptables REDIRECT ──────────────┘                                        │  │ │
│  │  │   (port 80,443 → 8080)                                                     │  │ │
│  │  └────────────────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                                  │ │
│  │  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐     │ │
│  │  │ VPN LoadBalancer    │  │ Frontend LB         │  │ Backend LB          │     │ │
│  │  │ 35.210.225.36       │  │ 35.187.70.238       │  │ 35.190.202.25       │     │ │
│  │  │ UDP 500, 4500       │  │ TCP 80              │  │ TCP 8080            │     │ │
│  │  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘     │ │
│  └────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                      │
│  ┌────────────────────────────────────────────────────────────────────────────────┐ │
│  │  Artifact Registry: europe-west1-docker.pkg.dev/hocuspocus-vpn/hocuspocus-vpn  │ │
│  │  Images: mitmproxy:latest, vpn:latest, admin-backend:latest, admin-frontend    │ │
│  └────────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────┘

                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              CLIENT DEVICES                                          │
│                                                                                      │
│  ┌─────────────────────┐                          ┌─────────────────────┐           │
│  │   iPhone XR         │                          │   MacBook Air       │           │
│  │   VPN IP: 10.10.10.10│                          │   VPN IP: 10.10.10.20│           │
│  │   SimpleMDM: 2154382│                          │   SimpleMDM: 2162127│           │
│  │   iOS (Supervised)  │                          │   macOS (User MDM)  │           │
│  │   AlwaysOn VPN ✓    │                          │   pf killswitch     │           │
│  └─────────────────────┘                          └─────────────────────┘           │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Traffic Flow

```
iPhone/Mac → IKEv2 VPN (35.210.225.36:500/4500)
           → VPN Server assigns IP (10.10.10.x)
           → iptables REDIRECT HTTP/S to port 8080
           → mitmproxy intercepts traffic
           → Checks allowed_hosts / youtube_channels
           → Blocks or forwards to internet
```

## iPhone E2E / Production Verification (Appium)

### What to use

- `make verify-vpn`: quick verification via `pymobiledevice3` (fast, no Appium)
- `make verify-vpn-appium-prod`: full verification via Appium + WebDriverAgent (bypasses Safari caching; uses **prod DB**)
- `make test-e2e`: full E2E suite using the **test DB** (`mitmproxy_e2e_tests`)

### One-time iPhone setup checklist

1. **VPN profile installed + connected** (Always-On supervised iOS profile)
   - Make sure the profile includes `ServiceExceptions` → `DeviceCommunication: Allow` so CoreDevice/Xcode/Appium can talk to the phone while Always-On VPN is enabled.
2. **Trust mitmproxy CA** (required for HTTPS interception)
   - iPhone: Settings → General → About → Certificate Trust Settings → enable “mitmproxy”
3. **Enable Developer Mode**
   - iPhone: Settings → Privacy & Security → Developer Mode → ON (reboot required)
4. **Install WebDriverAgentRunner**
   - Mac: `cd /Users/tushar/code/hocuspocus-vpn && make test-e2e-setup`
5. **Trust the Developer App certificate**
   - iPhone: Settings → General → VPN & Device Management → Developer App → Trust
   - If “Developer App” isn’t visible, run the WDA install step again once; iOS only shows the trust entry after the dev-signed app is installed.

### Run prod verification

```bash
cd /Users/tushar/code/hocuspocus-vpn
make appium
make verify-vpn-appium-prod
```

### Common failures

- **`xcodebuild failed with code 65`**: almost always the iPhone has not trusted the Developer App certificate yet.
- **No “Developer App” menu**: WDA isn’t installed yet; run `make test-e2e-setup` (or the `xcodebuild ... WebDriverAgentRunner ... test` command in `tests/e2e/README.md`) once while the phone is unlocked.

## macOS SimpleMDM (User-Approved MDM) Fix

### Symptoms
- Profiles installed, but VPN service not created (`scutil --nc list` empty)
- NetworkExtension logs show `wrong type` or `Failed to load configuration`

### Fix Summary
- Use **EAP IKEv2** profile with **device scope** (`PayloadScope=System`)
- Add DH Group 19 for IKE/Child SAs
- Keep VPN CA payload; avoid client certs (PKCS12) on user-approved MDM
- Both VPN and mitmproxy CA profiles are **device-wide**

### Mitmproxy TLS Errors
If mitmproxy logs `certificate unknown`, install the proxy CA as a separate **device-scope** profile:
```bash
./macos/scripts/generate-macos-mitmproxy-ca-profile.sh
./macos/scripts/push-macos-mitmproxy-ca-profile-mdm.sh
```

### Verification
- System Settings → VPN shows "Hocuspocus VPN (macOS Device EAP)"
- Logs show `NESMIKEv2VPNSession ... status changed to connected`

## API Keys & Credentials

### SimpleMDM API
- **Dashboard**: https://a.simplemdm.com
- **API Key**: `2IkV3x1TEpS9r6AGtmeyvLlBMvwHzCeJgQY4O8VyTtoss2KR6qVpEZcQqPlmLrLV`
- **Usage**: Device management, profile push, app deployment

```bash
# Test SimpleMDM API
API_KEY="2IkV3x1TEpS9r6AGtmeyvLlBMvwHzCeJgQY4O8VyTtoss2KR6qVpEZcQqPlmLrLV"

# List devices
curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/devices" | jq '.data[] | {id: .id, name: .attributes.name, status: .attributes.status}'

# Get device details
curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/devices/2154382" | jq '.data.attributes'

# List profiles
curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/custom_configuration_profiles" | jq '.data[] | {id: .id, name: .attributes.name}'

# Refresh device (trigger MDM check-in)
curl -s -X POST -u "$API_KEY:" "https://a.simplemdm.com/api/v1/devices/2154382/refresh"

# Get logs
curl -s -u "$API_KEY:" "https://a.simplemdm.com/api/v1/logs?limit=50" | jq '.data[]'
```

### YouTube Data API
- **API Key**: `AIzaSyAxNpnhN98kX2DOqQHQe4qq6NzvNqcYVq0`
- **Purpose**: Verify video channel ownership for YouTube filtering
- **Console**: https://console.cloud.google.com/apis/credentials?project=hocuspocus-vpn

```bash
# Test YouTube API
YOUTUBE_API_KEY="AIzaSyAxNpnhN98kX2DOqQHQe4qq6NzvNqcYVq0"
VIDEO_ID="lwgJhmsQz0U"

curl -s "https://www.googleapis.com/youtube/v3/videos?part=snippet&id=$VIDEO_ID&key=$YOUTUBE_API_KEY" | jq '.items[0].snippet.channelId'
```

### Google Cloud
- **Project**: `hocuspocus-vpn`
- **Region**: `europe-west1-b`
- **Service Account**: Default compute service account

```bash
# Authenticate with gcloud
gcloud auth login
gcloud config set project hocuspocus-vpn

# Get cluster credentials
gcloud container clusters get-credentials hocuspocus-vpn --zone europe-west1-b
```

### Database (PostgreSQL)
- **Host**: `postgres-service.hocuspocus.svc.cluster.local` (internal)
- **Port**: `5432`
- **Database**: `mitmproxy` (prod), `mitmproxy_e2e_tests` (tests)
- **User**: `postgres`
- **Password**: `mitmproxy_secret_password`

```bash
# Connect to database from local (requires port-forward)
kubectl port-forward svc/postgres-service -n hocuspocus 5432:5432 &
psql -h localhost -U postgres -d mitmproxy
# Password: mitmproxy_secret_password
```

### VPN Credentials
- **Username**: `vpnuser`
- **Password**: `Dvq0bsdRYCR1Lz54JJDj7PWihNGVqkui`
- **Note**: Certificate-based auth is preferred; these are fallback credentials

## Connecting to Google Cloud

### Prerequisites
```bash
# Install gcloud CLI
brew install google-cloud-sdk

# Install kubectl
brew install kubectl

# Authenticate
gcloud auth login
gcloud auth application-default login
```

### Get Cluster Access
```bash
# Set project
gcloud config set project hocuspocus-vpn

# Get kubeconfig for cluster
gcloud container clusters get-credentials hocuspocus-vpn --zone europe-west1-b

# Verify connection
kubectl get nodes
kubectl get pods -n hocuspocus
```

### GCP Console URLs
- **GKE Dashboard**: https://console.cloud.google.com/kubernetes/list?project=hocuspocus-vpn
- **Workloads**: https://console.cloud.google.com/kubernetes/workload?project=hocuspocus-vpn
- **Services**: https://console.cloud.google.com/kubernetes/discovery?project=hocuspocus-vpn
- **Artifact Registry**: https://console.cloud.google.com/artifacts?project=hocuspocus-vpn
- **Billing**: https://console.cloud.google.com/billing?project=hocuspocus-vpn

## Start/Stop Cluster

### Start VPN (Daily Use)
```bash
cd /Users/tushar/code/hocuspocus-vpn

# Start everything (scales nodes + deploys services)
make startgcvpn

# What it does:
# 1. Scales node pool from 0 to 2 nodes
# 2. Waits for nodes to be ready
# 3. Deploys all K8s resources (kubectl apply -k k8s/)
# 4. Runs verification script
```

### Stop VPN (Save Costs)
```bash
# Stop VPN (deletes LB + scales nodes to 0)
make stopgcvpn

# What it does:
# 1. Deletes VPN LoadBalancer service
# 2. Scales node pool to 0 nodes
# Idle cost: ~$0.05/day (disk storage only)
```

### Manual Node Scaling
```bash
# Scale up
gcloud container clusters resize hocuspocus-vpn \
    --node-pool vpn-pool \
    --num-nodes 2 \
    --zone europe-west1-b \
    --project hocuspocus-vpn \
    --quiet

# Scale down
gcloud container clusters resize hocuspocus-vpn \
    --node-pool vpn-pool \
    --num-nodes 0 \
    --zone europe-west1-b \
    --project hocuspocus-vpn \
    --quiet
```

### Check Status
```bash
make status

# Or manually:
kubectl get nodes
kubectl get pods -n hocuspocus -o wide
kubectl get svc -n hocuspocus
```

## Debugging Commands

### Pod Management
```bash
# List all pods with status
kubectl get pods -n hocuspocus -o wide

# Describe pod (events, conditions)
kubectl describe pod <pod-name> -n hocuspocus

# Get pod logs
kubectl logs -n hocuspocus <pod-name>
kubectl logs -n hocuspocus <pod-name> -c <container-name>  # Multi-container
kubectl logs -n hocuspocus <pod-name> --previous  # Previous crash

# Follow logs
kubectl logs -n hocuspocus -l app=mitmproxy -f
kubectl logs -n hocuspocus -l app=vpn-server -c strongswan -f

# Exec into pod
kubectl exec -it -n hocuspocus <pod-name> -- /bin/sh
kubectl exec -it -n hocuspocus <pod-name> -c <container> -- /bin/sh
```

### Mitmproxy Debugging
```bash
# View mitmproxy logs
make logs
# Or:
kubectl logs -n hocuspocus -l app=mitmproxy -f

# Check for YouTube filtering
kubectl logs -n hocuspocus -l app=mitmproxy --tail=100 | grep -E "(YouTube|ALLOWED|BLOCKED|channel)"

# Check location tracking
kubectl logs -n hocuspocus -l app=mitmproxy --tail=100 | grep -E "(location|GPS|blocked_location)"

# Restart mitmproxy (after code changes)
make deploy-mitmproxy
# Or:
kubectl rollout restart deployment mitmproxy -n hocuspocus
```

### VPN Server Debugging
```bash
# View VPN logs
make logs-vpn
# Or:
kubectl logs -n hocuspocus -l app=vpn-server -c strongswan -f

# Check VPN connections
kubectl exec -n hocuspocus -it $(kubectl get pods -n hocuspocus -l app=vpn-server -o jsonpath='{.items[0].metadata.name}') -c strongswan -- ipsec statusall

# Check iptables rules
kubectl exec -n hocuspocus -it $(kubectl get pods -n hocuspocus -l app=vpn-server -o jsonpath='{.items[0].metadata.name}') -c strongswan -- iptables -t nat -L -n -v

# View certificates on VPN server
kubectl exec -n hocuspocus -it $(kubectl get pods -n hocuspocus -l app=vpn-server -o jsonpath='{.items[0].metadata.name}') -c strongswan -- ls -la /etc/ipsec.d/
```

### Database Debugging
```bash
# Port forward to connect locally
kubectl port-forward svc/postgres-service -n hocuspocus 5432:5432 &

# Connect with psql
psql -h localhost -U postgres -d mitmproxy

# Useful queries
SELECT * FROM allowed_hosts WHERE enabled = true;
SELECT * FROM youtube_channels WHERE enabled = true;
SELECT * FROM blocked_locations WHERE enabled = true;
SELECT * FROM device_locations ORDER BY timestamp DESC LIMIT 10;
```

### Network Debugging
```bash
# Check services
kubectl get svc -n hocuspocus

# Check endpoints (do services have pods?)
kubectl get endpoints -n hocuspocus

# Test connectivity from inside cluster
kubectl run test-pod --rm -it --image=alpine -- sh
# Then: apk add curl && curl -v http://mitmproxy-service:8080

# Check VPN LoadBalancer IP
kubectl get svc vpn-service -n hocuspocus -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Common Debug Workflows

#### VPN Not Connecting
```bash
# 1. Check VPN pod is running
kubectl get pods -n hocuspocus -l app=vpn-server

# 2. Check VPN logs for errors
kubectl logs -n hocuspocus -l app=vpn-server -c strongswan --tail=50

# 3. Check VPN service has external IP
kubectl get svc vpn-service -n hocuspocus

# 4. Verify certificates exist
kubectl exec -n hocuspocus $(kubectl get pods -n hocuspocus -l app=vpn-server -o jsonpath='{.items[0].metadata.name}') -c strongswan -- ls -la /etc/ipsec.d/certs/

# 5. Check ipsec status
kubectl exec -n hocuspocus $(kubectl get pods -n hocuspocus -l app=vpn-server -o jsonpath='{.items[0].metadata.name}') -c strongswan -- ipsec statusall
```

#### HTTPS Sites Not Loading
```bash
# 1. Check mitmproxy is running
kubectl get pods -n hocuspocus -l app=mitmproxy

# 2. Check mitmproxy logs for errors
kubectl logs -n hocuspocus -l app=mitmproxy --tail=50

# 3. Verify traffic is being redirected (iptables)
kubectl exec -n hocuspocus $(kubectl get pods -n hocuspocus -l app=vpn-server -o jsonpath='{.items[0].metadata.name}') -c strongswan -- iptables -t nat -L PREROUTING -n -v

# 4. Check if CA cert is trusted on device
# On iPhone: Settings → General → About → Certificate Trust Settings
```

#### YouTube Videos Being Blocked Incorrectly
```bash
# 1. Check YouTube API is working
YOUTUBE_API_KEY="AIzaSyAxNpnhN98kX2DOqQHQe4qq6NzvNqcYVq0"
VIDEO_ID="<video-id>"
curl -s "https://www.googleapis.com/youtube/v3/videos?part=snippet&id=$VIDEO_ID&key=$YOUTUBE_API_KEY" | jq '.items[0].snippet.channelTitle'

# 2. Check channel is in whitelist
kubectl port-forward svc/postgres-service -n hocuspocus 5432:5432 &
psql -h localhost -U postgres -d mitmproxy -c "SELECT * FROM youtube_channels WHERE enabled = true;"

# 3. Check mitmproxy logs for the video request
kubectl logs -n hocuspocus -l app=mitmproxy --tail=200 | grep -i "$VIDEO_ID"
```

## Device-Specific Debugging

### iPhone Debugging
```bash
# List connected devices
idevice_id -l

# Get device info
ideviceinfo -u <UDID>

# Open URL in Safari
~/.local/bin/pymobiledevice3 webinspector launch "https://example.com"

# List Safari tabs
~/.local/bin/pymobiledevice3 webinspector opened-tabs
```

### MacBook Air Debugging (via SSH)

**Important:** SSH sessions don't load `/opt/homebrew/bin` by default. Always prefix commands with the PATH or use full paths.

```bash
# SSH to MacBook Air via Tailscale (use hostname, not IP - IP can change)
ssh tushru2004@tushru2004s-macbook-air

# CRITICAL: Set PATH for Homebrew tools (node, npm, appium, etc.)
export PATH=/opt/homebrew/bin:$PATH

# Or use full paths directly:
/opt/homebrew/bin/appium
/opt/homebrew/bin/node --version

# Check MDM enrollment
profiles status -type enrollment

# List installed profiles (requires sudo, password: hhh420)
echo 'hhh420' | sudo -S /usr/libexec/mdmclient QueryInstalledProfiles

# Trigger MDM check-in
echo 'hhh420' | sudo -S /usr/libexec/mdmclient QueryDeviceInformation

# Check VPN connection
scutil --nc list

# Check location daemon
launchctl list | grep hocuspocus
tail -f /tmp/hocuspocus-location-sender.log
```

### Running Appium on MacBook Air (via SSH)

```bash
# SSH with PATH set
ssh tushru2004@tushru2004s-macbook-air

# Check if Appium is running
pgrep -l node  # Appium runs as a node process

# Kill existing Appium (if stuck or port 4723 in use)
pkill -f appium
sleep 2

# Start Appium with correct PATH
export PATH=/opt/homebrew/bin:$PATH
nohup appium > /tmp/appium.log 2>&1 &

# Verify it started
sleep 3
pgrep -l node
tail -20 /tmp/appium.log

# One-liner to kill and restart Appium
ssh tushru2004@tushru2004s-macbook-air "pkill -f appium; sleep 2; export PATH=/opt/homebrew/bin:\$PATH && nohup appium > /tmp/appium.log 2>&1 & sleep 3 && pgrep -l node"
```

### Running E2E Tests from MacBook Pro (via SSH to Air)

```bash
# Run E2E prod tests remotely
ssh tushru2004@tushru2004s-macbook-air "export PATH=/opt/homebrew/bin:\$PATH && cd /Users/tushru2004/hocuspocus-vpn && source .venv/bin/activate && USE_PREBUILT_WDA=true IOS_DERIVED_DATA_PATH=/tmp/wda-dd python -m pytest tests/e2e_prod/test_verify_vpn.py -v --tb=short"
```

## Deployment Commands

### Deploy Code Changes
```bash
# Mitmproxy (Python proxy code)
make deploy-mitmproxy
# Builds image, pushes to Artifact Registry, restarts deployment

# VPN Server (StrongSwan config)
make build-push-vpn
kubectl rollout restart daemonset vpn-server -n hocuspocus

# Admin Backend (Kotlin)
cd /Users/tushar/code/hocuspocus-admin-backend
docker build --platform linux/amd64 -t europe-west1-docker.pkg.dev/hocuspocus-vpn/hocuspocus-vpn/admin-backend:latest .
docker push europe-west1-docker.pkg.dev/hocuspocus-vpn/hocuspocus-vpn/admin-backend:latest
kubectl rollout restart deployment backend -n hocuspocus

# Admin Frontend (React)
cd /Users/tushar/code/hocuspocus-admin-frontend
docker build --platform linux/amd64 -t europe-west1-docker.pkg.dev/hocuspocus-vpn/hocuspocus-vpn/admin-frontend:latest .
docker push europe-west1-docker.pkg.dev/hocuspocus-vpn/hocuspocus-vpn/admin-frontend:latest
kubectl rollout restart deployment frontend -n hocuspocus
```

### Push VPN Profile
```bash
# Via SimpleMDM (recommended for iOS)
make vpn-profile-mdm DEVICE=iphone

# Via USB (Apple Configurator)
make vpn-profile-install DEVICE=iphone

# Generate only (no push)
make vpn-profile DEVICE=iphone
```

## Cost Management

### Current Costs (Running)
| Resource | Cost |
|----------|------|
| 2x e2-standard-2 spot nodes | ~$0.048/hr |
| 3x Load Balancers | ~$0.075/hr |
| Disk Storage (12GB) | ~$0.002/hr |
| **Total Running** | **~$0.125/hr** (~$3/day) |

### Idle Costs (Stopped)
| Resource | Cost |
|----------|------|
| Disk Storage only | ~$0.05/day |

### Check Billing
```bash
make cost

# Or check GCP Console:
# https://console.cloud.google.com/billing?project=hocuspocus-vpn
```

## Troubleshooting Common Issues

### Understanding Why a Domain is Blocked/Allowed

The proxy has **two separate filtering mechanisms**:

1. **Global Domain Whitelist** (always active)
   - Only domains in `allowed_hosts` table can be accessed
   - If domain NOT in whitelist → blocked everywhere

2. **Location-Based Blocking** (only at specific locations)
   - When device is inside a "blocked location" radius, stricter rules apply
   - Only domains in the **per-location whitelist** for that location are allowed

**To check current whitelist and locations:**
```bash
# Check allowed domains
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "SELECT domain FROM allowed_hosts WHERE enabled = true ORDER BY domain;"

# Check blocked locations
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "SELECT name, latitude, longitude, radius_meters FROM blocked_locations WHERE enabled = true;"

# Check current device location (from SimpleMDM polling)
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "SELECT device_id, latitude, longitude, fetched_at FROM device_locations;"

# Check location-poller is working
kubectl logs -n hocuspocus deployment/mitmproxy -c location-poller --tail=10
```

**Example:** Twitter blocked because it's NOT in `allowed_hosts`, not because of location.

### SimpleMDM Location Polling Architecture

```
SimpleMDM polls iPhone location every 30 seconds
        ↓
location-poller sidecar fetches from SimpleMDM API
        ↓
Stores in `device_locations` table in PostgreSQL
        ↓
When iPhone makes a request, mitmproxy:
  1. Maps VPN IP (10.10.10.10) → device ID (2154382)
  2. Looks up device location from DB
  3. Checks if device is inside any "blocked location" radius
  4. If inside → apply per-location whitelist rules
  5. If outside → apply global whitelist rules
```

### Testing Location-Based Blocking (Fake Location Injection)

You can test location-based blocking without being physically present by injecting
fake locations directly into the database:

```bash
# Set iPhone to Social Hub Vienna (blocked location)
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "UPDATE device_locations SET latitude=48.222861, longitude=16.390007, fetched_at=NOW() WHERE device_id='2154382';"

# Set to John Harris Fitness
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "UPDATE device_locations SET latitude=48.201848, longitude=16.364503, fetched_at=NOW() WHERE device_id='2154382';"

# Restore to somewhere outside blocked zones (SimpleMDM will overwrite in ~30s anyway)
kubectl exec -n hocuspocus postgres-0 -- psql -U mitmproxy -d mitmproxy \
  -c "UPDATE device_locations SET latitude=48.18, longitude=16.38, fetched_at=NOW() WHERE device_id='2154382';"
```

**E2E tests have a `fake_location` fixture** that handles injection and auto-restore:
```python
def test_at_blocked_location(fake_location):
    fake_location("social_hub_vienna")  # Moves device to Social Hub
    # ... test runs ...
    # Location auto-restored after test
```

**Note:** SimpleMDM overwrites the location every ~30 seconds, so fake locations are temporary.

### Pod Stuck in Pending
```bash
kubectl describe pod <pod-name> -n hocuspocus
# Check Events section for: insufficient resources, PVC not found, node not ready
```

### Deployment Selector Immutable Error
```bash
# Delete and recreate deployment
kubectl delete deployment <name> -n hocuspocus
kubectl apply -f k8s/<name>-deployment.yaml
```

### mitmproxy Container Missing Files
```bash
# Rebuild image to include new files
make deploy-mitmproxy
```

### SimpleMDM API Key Rejected
```bash
# Test key directly
curl -s -u "2IkV3x1TEpS9r6AGtmeyvLlBMvwHzCeJgQY4O8VyTtoss2KR6qVpEZcQqPlmLrLV:" \
  "https://a.simplemdm.com/api/v1/devices"
# If fails, check key in SimpleMDM dashboard: Settings → API
```

### Nodes Won't Scale Up
```bash
# Check node pool status
gcloud container node-pools describe vpn-pool \
    --cluster hocuspocus-vpn \
    --zone europe-west1-b

# Check for quota issues
gcloud compute regions describe europe-west1 --format="table(quotas)"
```

## External Service URLs

| Service | URL |
|---------|-----|
| Admin Frontend | http://35.187.70.238 |
| Admin Backend API | http://35.190.202.25:8080/api |
| VPN Server | 35.210.225.36 (UDP 500, 4500) |
| SimpleMDM Dashboard | https://a.simplemdm.com |
| GCP Console | https://console.cloud.google.com/kubernetes?project=hocuspocus-vpn |
