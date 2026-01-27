"""Pytest configuration for production E2E verification tests.

These tests run against the PRODUCTION database - no switching, no seeding.
Used for quick VPN verification after startup.
"""
import pytest
import subprocess
import os
import time
import uuid

from appium import webdriver
from appium.options.ios import XCUITestOptions


K8S_NAMESPACE = "hocuspocus"

# Blocked locations for testing (must match database)
BLOCKED_LOCATIONS = {
    "social_hub_vienna": {"lat": 48.22286170, "lng": 16.39000710, "name": "The Social Hub Vienna"},
    "john_harris": {"lat": 48.20184899, "lng": 16.36450324, "name": "John Harris Fitness"},
    "test_school_sf": {"lat": 37.77490000, "lng": -122.41940000, "name": "Test School"},
}

# iPhone SimpleMDM device ID
IPHONE_DEVICE_ID = "2154382"


def _run_kubectl_command(args: list, timeout: int = 60) -> subprocess.CompletedProcess:
    """Run a kubectl command."""
    # Ensure kubectl is in PATH (Homebrew on macOS)
    env = os.environ.copy()
    env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
    cmd = ["kubectl", "-n", K8S_NAMESPACE] + args
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)


@pytest.fixture(scope="session", autouse=True)
def appium_preflight_check():
    """Verify Appium server is running."""
    print("\n" + "="*60)
    print("🚀 [PROD] Running production verification preflight...")
    print("="*60)

    try:
        import urllib.request
        urllib.request.urlopen('http://127.0.0.1:4723/status', timeout=5)
        print("✅ Appium server is running")
    except Exception as e:
        pytest.exit(f"Appium server not running! Start with: appium\nError: {e}")

    yield

    print("\n🏁 [PROD] Verification completed")


@pytest.fixture(scope="session")
def e2e_run_id() -> str:
    """Unique ID to correlate this test run in logs."""
    return os.getenv("E2E_RUN_ID") or uuid.uuid4().hex[:12]


@pytest.fixture(scope="session")
def e2e_start_time() -> float:
    """Monotonic start timestamp for log windowing."""
    return time.time()


def _get_current_device_location(device_id: str = IPHONE_DEVICE_ID) -> dict:
    """Get current device location from database."""
    result = _run_kubectl_command([
        "exec", "postgres-0", "--",
        "psql", "-U", "mitmproxy", "-d", "mitmproxy", "-t", "-A", "-c",
        f"SELECT latitude, longitude FROM device_locations WHERE device_id = '{device_id}';"
    ])
    if result.returncode == 0 and result.stdout.strip():
        parts = result.stdout.strip().split("|")
        if len(parts) == 2:
            return {"lat": float(parts[0]), "lng": float(parts[1])}
    return None


def _set_device_location(lat: float, lng: float, device_id: str = IPHONE_DEVICE_ID) -> bool:
    """Inject fake location into database for testing."""
    result = _run_kubectl_command([
        "exec", "postgres-0", "--",
        "psql", "-U", "mitmproxy", "-d", "mitmproxy", "-c",
        f"UPDATE device_locations SET latitude = {lat}, longitude = {lng}, "
        f"fetched_at = NOW() WHERE device_id = '{device_id}';"
    ])
    return result.returncode == 0


@pytest.fixture
def fake_location():
    """Fixture to temporarily set device to a fake location.
    
    Usage:
        def test_at_blocked_location(fake_location):
            fake_location("social_hub_vienna")  # Move device to Social Hub
            # ... run test ...
            # Location auto-restored after test
    
    Available locations: social_hub_vienna, john_harris, test_school_sf
    Or pass custom coords: fake_location(lat=48.123, lng=16.456)
    """
    original_location = _get_current_device_location()
    locations_set = []
    
    def _set_location(location_name: str = None, lat: float = None, lng: float = None):
        if location_name:
            if location_name not in BLOCKED_LOCATIONS:
                raise ValueError(f"Unknown location: {location_name}. Available: {list(BLOCKED_LOCATIONS.keys())}")
            loc = BLOCKED_LOCATIONS[location_name]
            lat, lng = loc["lat"], loc["lng"]
            print(f"📍 [TEST] Setting fake location: {loc['name']} (lat={lat}, lng={lng})")
        else:
            print(f"📍 [TEST] Setting fake location: lat={lat}, lng={lng}")
        
        success = _set_device_location(lat, lng)
        if success:
            locations_set.append(True)
            time.sleep(1)  # Give proxy time to pick up new location
        return success
    
    yield _set_location
    
    # Restore original location after test
    if original_location and locations_set:
        print(f"📍 [TEST] Restoring original location: lat={original_location['lat']}, lng={original_location['lng']}")
        _set_device_location(original_location["lat"], original_location["lng"])


@pytest.fixture(scope="session")
def ios_driver(e2e_run_id: str):
    """Create iOS Appium driver for production verification."""
    print("\n🔌 [PROD] Creating Appium driver...")

    options = XCUITestOptions()
    options.platform_name = "iOS"
    options.browser_name = "Safari"
    options.automation_name = "XCUITest"
    options.no_reset = False  # Allow reset to clear Safari data
    options.set_capability("appium:autoAcceptAlerts", True)

    # Real device config (allow overrides for running from another Mac)
    options.platform_version = os.getenv("IOS_PLATFORM_VERSION", "18.7.3")
    options.device_name = os.getenv("IOS_DEVICE_NAME", "Tushar's iPhone")
    options.udid = os.getenv("IOS_UDID", "00008020-0004695621DA002E")
    options.set_capability("appium:xcodeOrgId", os.getenv("IOS_XCODE_ORG_ID", "2TF5QH3WTY"))
    xcode_signing_id = os.getenv("IOS_XCODE_SIGNING_ID", "").strip()
    if xcode_signing_id:
        options.set_capability("appium:xcodeSigningId", xcode_signing_id)
    options.set_capability("appium:updatedWDABundleId", os.getenv("IOS_WDA_BUNDLE_ID", "com.tushru2004.WebDriverAgentRunner"))
    use_prebuilt = os.getenv("USE_PREBUILT_WDA", "true").lower() == "true"
    options.set_capability("appium:usePrebuiltWDA", use_prebuilt)
    options.set_capability(
        "appium:allowProvisioningUpdates",
        os.getenv("IOS_ALLOW_PROVISIONING_UPDATES", "true").lower() == "true",
    )
    options.set_capability(
        "appium:allowProvisioningDeviceRegistration",
        os.getenv("IOS_ALLOW_DEVICE_REGISTRATION", "true").lower() == "true",
    )
    derived_data_path = os.getenv("IOS_DERIVED_DATA_PATH", "").strip()
    if derived_data_path:
        options.set_capability("appium:derivedDataPath", derived_data_path)
    # Keep WDA installed on the device so the iPhone can show the trust prompt
    options.set_capability("appium:skipUninstall", True)
    options.set_capability("appium:showXcodeLog", True)
    options.set_capability("appium:wdaLaunchTimeout", 600000)  # 10 minutes
    options.set_capability("appium:wdaConnectionTimeout", 240000)  # 4 minutes
    options.set_capability("appium:newCommandTimeout", 300)  # 5 minutes

    driver = webdriver.Remote(
        command_executor="http://127.0.0.1:4723",
        options=options
    )
    print("✅ [PROD] Connected to device")

    # Emit a marker request so logs can be correlated even with noisy background traffic.
    # This is intentionally a benign path on a whitelisted domain.
    marker = os.getenv("E2E_LOG_MARKER") or f"HP_E2E_{e2e_run_id}"
    os.environ["E2E_LOG_MARKER"] = marker
    try:
        driver.get(f"https://www.google.com/{marker}?t={int(time.time())}")
        time.sleep(2)
        print(f"🧷 [PROD] Log marker emitted: {marker}")
    except Exception as e:
        # Don't fail the session if the marker URL doesn't load (network/VPN issues will be caught by tests).
        print(f"⚠️  [PROD] Could not emit log marker ({marker}): {e}")

    yield driver

    print("🔌 [PROD] Closing driver...")
    driver.quit()


@pytest.fixture(scope="session")
def mitmproxy_logs(e2e_start_time: float, e2e_run_id: str):
    """Fixture to fetch mitmproxy logs for assertions.

    Primary source: kubectl logs (cluster access required).
    Fallback source: Grafana → Loki (useful on machines without kubectl access).
    """

    def _logs_via_kubectl(tail: int) -> str:
        # These production verification tests run while the device and other clients
        # (e.g. macOS location sender, background Apple services) may be generating
        # lots of traffic. Small tails can miss the relevant allow/block lines,
        # causing flaky false negatives.
        tail = max(int(tail), 2000)

        # Prefer a "since" window to cut noise between runs.
        since_seconds = int(os.getenv("MITMPROXY_LOG_SINCE_SECONDS", "0") or "0")
        if since_seconds <= 0:
            since_seconds = max(60, int(time.time() - e2e_start_time) + 30)

        result = _run_kubectl_command(
            ["logs", "deployment/mitmproxy", f"--since={since_seconds}s", f"--tail={tail}"],
            timeout=30,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout
        raise RuntimeError((result.stderr or "").strip() or "kubectl logs returned empty output")

    def _logs_via_grafana_loki() -> str:
        """Fetch logs from Loki via Grafana proxy.

        Requires:
          - Grafana reachable (see `/Users/tushar/code/URLS.md`)
          - Env vars:
            - GRAFANA_URL (default: http://34.52.195.7)
            - GRAFANA_USER (default: admin)
            - GRAFANA_PASSWORD (default: hocuspocus123)
        """
        import json
        import urllib.request
        import urllib.parse
        import base64

        grafana_url = os.getenv("GRAFANA_URL", "http://34.52.195.7").rstrip("/")
        grafana_user = os.getenv("GRAFANA_USER", "admin")
        grafana_password = os.getenv("GRAFANA_PASSWORD", "hocuspocus123")

        auth = base64.b64encode(f"{grafana_user}:{grafana_password}".encode()).decode()

        def _get(path: str) -> dict:
            req = urllib.request.Request(
                f"{grafana_url}{path}",
                headers={"Authorization": f"Basic {auth}"},
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                return json.loads(resp.read().decode())

        # Find Loki datasource id
        ds_id_env = os.getenv("GRAFANA_LOKI_DATASOURCE_ID")
        if ds_id_env:
            loki_id = int(ds_id_env)
        else:
            datasources = _get("/api/datasources")
            loki = next((d for d in datasources if str(d.get("type", "")).lower() == "loki"), None)
            if not loki:
                raise RuntimeError("Grafana Loki datasource not found")
            loki_id = int(loki["id"])

        # Query last N seconds from start time to now
        since_seconds = int(os.getenv("MITMPROXY_LOG_SINCE_SECONDS", "0") or "0")
        if since_seconds <= 0:
            since_seconds = max(120, int(time.time() - e2e_start_time) + 30)

        end_ns = int(time.time() * 1e9)
        start_ns = end_ns - int(since_seconds * 1e9)

        query = os.getenv("LOKI_QUERY", '{app="mitmproxy"}')
        params = urllib.parse.urlencode(
            {
                "query": query,
                "start": str(start_ns),
                "end": str(end_ns),
                "limit": os.getenv("LOKI_LIMIT", "5000"),
                "direction": "forward",
            }
        )

        req = urllib.request.Request(
            f"{grafana_url}/api/datasources/proxy/{loki_id}/loki/api/v1/query_range?{params}",
            headers={"Authorization": f"Basic {auth}"},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read().decode())

        streams = payload.get("data", {}).get("result", []) or []
        lines: list[str] = []
        for stream in streams:
            for ts, line in stream.get("values", []) or []:
                lines.append(line)

        # Optional marker filtering (helps reduce noise)
        marker = os.getenv("E2E_LOG_MARKER", "")
        if marker:
            marker_idx = next((i for i, l in enumerate(lines) if marker in l), None)
            if marker_idx is not None:
                lines = lines[marker_idx:]

        return "\n".join(lines)

    def get_logs(tail: int = 2000) -> str:
        # Prefer kubectl if available
        if subprocess.run(["which", "kubectl"], capture_output=True, text=True).returncode == 0:
            try:
                return _logs_via_kubectl(tail=tail)
            except Exception:
                # Fall back to Grafana Loki if kubectl is missing/misconfigured
                pass
        return _logs_via_grafana_loki()

    print(f"🧾 [PROD] Log correlation run_id={e2e_run_id}")
    return get_logs
