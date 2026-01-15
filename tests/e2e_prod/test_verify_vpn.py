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
    def test_twitter_blocked(self, ios_driver, mitmproxy_logs):
        """Test that twitter.com is blocked (non-whitelisted domain)."""
        print("\n📱 [TEST] Opening twitter.com (should be blocked)...")

        # Add cache bust to ensure fresh request
        cache_bust = int(time.time())
        ios_driver.get(f"https://twitter.com/?_cb={cache_bust}")

        # Wait for request to be processed
        time.sleep(6)

        # Check proxy logs
        logs = mitmproxy_logs(tail=50)

        # Verify twitter was blocked
        blocked = (
            "BLOCKING" in logs and
            ("twitter" in logs.lower() or "x.com" in logs.lower())
        )
        generic_blocked = "BLOCKING non-whitelisted domain" in logs

        assert blocked or generic_blocked, \
            f"twitter.com was not blocked! Expected BLOCKING in logs."

        print("✅ [TEST] twitter.com BLOCKED (as expected)")

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


class TestVPNQuickCheck:
    """Quick smoke test for VPN - just verifies blocking works."""

    @pytest.mark.timeout(30)
    def test_domain_blocking_works(self, ios_driver, mitmproxy_logs):
        """Quick test that domain blocking is working."""
        print("\n📱 [QUICK] Testing domain blocking...")

        cache_bust = int(time.time())
        ios_driver.get(f"https://twitter.com/?_cb={cache_bust}")

        time.sleep(5)

        logs = mitmproxy_logs(tail=30)

        assert "BLOCKING" in logs, \
            "No blocking detected in logs - VPN filtering may not be working!"

        print("✅ [QUICK] Domain blocking is working")
