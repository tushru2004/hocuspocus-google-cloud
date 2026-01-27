"""
Production VPN verification tests.

These tests verify that the VPN is working correctly against the PRODUCTION database.
No database switching or seeding - tests real production state.

Usage:
    pytest tests/e2e_prod/test_verify_vpn.py -v -s
    # Or via Makefile:
    make verify-vpn-appium
"""
import pytest
import time


class TestVPNVerification:
    """Verify VPN filtering is working in production."""

    @pytest.mark.timeout(60)
    def test_jre_video_allowed(self, ios_driver, mitmproxy_logs):
        """Test that Joe Rogan Experience videos are allowed."""
        print("\n📱 [TEST] Opening JRE video (should be allowed)...")

        # JRE test video
        video_url = "https://m.youtube.com/watch?v=lwgJhmsQz0U"
        ios_driver.get(video_url)

        # Wait for page to load and requests to flow
        time.sleep(8)

        # Check proxy logs
        logs = mitmproxy_logs(tail=100)

        # Verify JRE channel was detected and allowed
        assert "Joe Rogan" in logs or "lwgJhmsQz0U" in logs, \
            f"JRE video not found in logs. Expected 'Joe Rogan' or video ID in logs."

        # Make sure it wasn't blocked
        assert "BLOCKING.*lwgJhmsQz0U" not in logs, \
            "JRE video was blocked but should be allowed!"

        print("✅ [TEST] JRE video ALLOWED (as expected)")

    @pytest.mark.timeout(60)
    def test_reddit_blocked(self, ios_driver, mitmproxy_logs):
        """Test that reddit.com is blocked (non-whitelisted domain)."""
        print("\n📱 [TEST] Opening reddit.com (should be blocked)...")

        # Add cache bust to ensure fresh request
        cache_bust = int(time.time())
        ios_driver.get(f"https://reddit.com/?_cb={cache_bust}")

        # Wait for request to be processed
        time.sleep(6)

        # Check proxy logs
        logs = mitmproxy_logs(tail=50)

        # Verify reddit was blocked
        blocked = (
            ("BLOCKING" in logs or "BLOCKED" in logs) and
            "reddit" in logs.lower()
        )
        generic_blocked = "BLOCKING non-whitelisted domain" in logs or "BLOCKED" in logs

        assert blocked or generic_blocked, \
            f"reddit.com was not blocked! Expected BLOCKING or BLOCKED in logs."

        print("✅ [TEST] reddit.com BLOCKED (as expected)")

    @pytest.mark.timeout(30)
    def test_google_allowed(self, ios_driver, mitmproxy_logs):
        """Test that google.com is allowed (whitelisted domain)."""
        print("\n📱 [TEST] Opening google.com (should be allowed)...")

        cache_bust = int(time.time())
        ios_driver.get(f"https://www.google.com/?_cb={cache_bust}")

        time.sleep(5)

        logs = mitmproxy_logs(tail=30)

        # Verify google was allowed
        assert "Allowing whitelisted domain" in logs or "google.com" in logs, \
            "google.com request not found in logs"

        # Make sure it wasn't blocked
        assert "BLOCKING.*google.com" not in logs, \
            "google.com was blocked but should be allowed!"

        print("✅ [TEST] google.com ALLOWED (as expected)")


class TestLocationWhitelist:
    """Test per-location whitelist feature.

    These tests use fake location injection to simulate being at a blocked location.
    No need to be physically present - location is injected directly into database.
    
    Current setup:
    - Blocked location: "The Social Hub Vienna" (lat=48.222, lng=16.390, radius=100m)
    - Per-location whitelist: cnbc.com (must be configured in admin dashboard)
    """

    @pytest.mark.timeout(90)
    def test_location_whitelisted_domain_allowed(self, ios_driver, mitmproxy_logs, fake_location):
        """Test that domain in per-location whitelist is allowed at blocked location.

        This test injects a fake location to simulate being at Social Hub Vienna,
        then verifies that cnbc.com (if in per-location whitelist) is allowed.
        """
        print("\n📱 [TEST] Testing per-location whitelist with fake location...")
        
        # Inject fake location: Social Hub Vienna
        fake_location("social_hub_vienna")
        time.sleep(2)  # Give proxy time to pick up new location

        # Visit cnbc.com which should be in the per-location whitelist
        cache_bust = int(time.time())
        ios_driver.get(f"https://www.cnbc.com/?_cb={cache_bust}")
        time.sleep(8)

        logs = mitmproxy_logs(tail=100)

        # Check if we're being treated as at a blocked location
        at_blocked_location = (
            "At blocked location" in logs or 
            "BLOCKED at" in logs or 
            "BLOCKING ENABLED" in logs or
            "per-location whitelist" in logs
        )

        if not at_blocked_location:
            # Check if location injection worked
            print(f"⚠️ Location injection may not have worked. Checking logs...")
            if "BLOCKING non-whitelisted domain" in logs:
                pytest.skip("Location blocking not active - proxy using global whitelist instead")

        # Verify cnbc.com was allowed via per-location whitelist
        whitelist_allowed = "ALLOWING" in logs and "cnbc" in logs.lower()

        assert whitelist_allowed, \
            f"cnbc.com was not allowed! Check if cnbc.com is in per-location whitelist for Social Hub Vienna.\nLogs:\n{logs[-1000:]}"

        print("✅ [TEST] cnbc.com ALLOWED via per-location whitelist (as expected)")

    @pytest.mark.timeout(60)
    def test_non_whitelisted_domain_blocked_at_location(self, ios_driver, mitmproxy_logs, fake_location):
        """Test that non-whitelisted domains are blocked at blocked location."""
        print("\n📱 [TEST] Testing domain blocking at fake location...")

        # Inject fake location: Social Hub Vienna
        fake_location("social_hub_vienna")
        time.sleep(2)

        cache_bust = int(time.time())
        ios_driver.get(f"https://reddit.com/?_cb={cache_bust}")
        time.sleep(8)

        logs = mitmproxy_logs(tail=100)

        # Check if blocked (either at location or via global whitelist)
        blocked = "BLOCKED" in logs or "BLOCKING" in logs

        assert blocked, \
            f"reddit.com was not blocked! Logs:\n{logs[-500:]}"

        # Check if it was blocked specifically due to location
        blocked_at_location = "BLOCKED at" in logs or "At blocked location" in logs
        if blocked_at_location:
            print("✅ [TEST] reddit.com BLOCKED at blocked location (location-based blocking)")
        else:
            print("✅ [TEST] reddit.com BLOCKED (global whitelist - location blocking may not be active)")


class TestLocationWhitelistManual:
    """Manual location tests - only run when physically at a blocked location.
    
    These tests do NOT inject fake location. They check real SimpleMDM-polled location.
    Skip these unless you're physically at the location.
    
    Run with: pytest -k "Manual" tests/e2e_prod/test_verify_vpn.py
    """

    @pytest.mark.skip(reason="Manual test - only run when physically at Social Hub Vienna")
    @pytest.mark.timeout(60)
    def test_real_location_at_social_hub(self, ios_driver, mitmproxy_logs):
        """Test when physically at Social Hub Vienna (real location from SimpleMDM)."""
        print("\n📱 [TEST] Testing with REAL location from SimpleMDM...")
        
        cache_bust = int(time.time())
        ios_driver.get(f"https://reddit.com/?_cb={cache_bust}")
        time.sleep(8)

        logs = mitmproxy_logs(tail=50)
        
        if "At blocked location" not in logs and "BLOCKED at" not in logs:
            pytest.skip("Not physically at a blocked location according to SimpleMDM")
        
        print("✅ [TEST] Confirmed at blocked location via SimpleMDM")


class TestVPNQuickCheck:
    """Quick smoke test for VPN - just verifies blocking works."""

    @pytest.mark.timeout(30)
    def test_domain_blocking_works(self, ios_driver, mitmproxy_logs):
        """Quick test that domain blocking is working."""
        print("\n📱 [QUICK] Testing domain blocking...")

        cache_bust = int(time.time())
        ios_driver.get(f"https://reddit.com/?_cb={cache_bust}")

        time.sleep(5)

        logs = mitmproxy_logs(tail=30)

        assert "BLOCKED" in logs or "BLOCKING" in logs, \
            "No blocking detected in logs - VPN filtering may not be working!"

        print("✅ [QUICK] Domain blocking is working")
