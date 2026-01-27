"""
Simple smoke test to verify E2E test setup is working.

Run this test first to verify:
1. Appium server is running
2. iOS device is connected
3. WebDriverAgent can connect
4. Safari can be automated

Usage:
    pytest tests/e2e/test_smoke.py -v -s
"""
import pytest
import os
from appium import webdriver
from appium.options.ios import XCUITestOptions


class TestSmoke:
    """Quick smoke test to verify test infrastructure."""

    @pytest.fixture(scope="class")
    def driver(self):
        """Set up iOS driver with minimal config."""
        print("\n🔌 [SMOKE] Creating Appium driver...")

        device_type = os.getenv('IOS_DEVICE_TYPE', 'real').lower()

        options = XCUITestOptions()
        options.platform_name = "iOS"
        options.browser_name = "Safari"
        options.automation_name = "XCUITest"
        options.no_reset = True
        options.set_capability("appium:autoAcceptAlerts", True)

        if device_type == 'simulator':
            options.platform_version = "26.2"
            options.device_name = "iPhone 17 Pro"
            options.set_capability("appium:wdaLaunchTimeout", 60000)
        else:
            # Real device config
            options.platform_version = os.getenv("IOS_PLATFORM_VERSION", "18.7.3")
            options.device_name = os.getenv("IOS_DEVICE_NAME", "Tushar's iPhone")
            options.udid = os.getenv("IOS_UDID", "00008020-0004695621DA002E")
            options.set_capability("appium:xcodeOrgId", os.getenv("IOS_XCODE_ORG_ID", "QG9U628JFD"))
            options.set_capability("appium:xcodeSigningId", os.getenv("IOS_XCODE_SIGNING_ID", "Apple Development"))
            options.set_capability("appium:updatedWDABundleId", os.getenv("IOS_WDA_BUNDLE_ID", "com.hocuspocus.WebDriverAgentRunner"))
            use_prebuilt = os.getenv("USE_PREBUILT_WDA", "true").lower() == "true"
            options.set_capability("appium:usePrebuiltWDA", use_prebuilt)
            # Keep WDA installed even if a session fails
            options.set_capability("appium:skipUninstall", True)
            options.set_capability("appium:wdaLaunchTimeout", 600000)  # 10 minutes - real devices can be slow
            options.set_capability("appium:wdaConnectionTimeout", 240000)  # 4 minutes

        print("🔌 [SMOKE] Connecting to Appium at http://127.0.0.1:4723...")

        # Set longer timeout for session creation (WDA can take a while)
        options.set_capability("appium:newCommandTimeout", 300)  # 5 min command timeout

        # Configure HTTP client with longer timeout for session creation
        driver = webdriver.Remote(
            command_executor="http://127.0.0.1:4723",
            options=options
        )
        print("✅ [SMOKE] Appium connection successful!")

        yield driver

        print("🔌 [SMOKE] Closing driver...")
        driver.quit()

    @pytest.mark.timeout(600)
    def test_can_connect_to_device(self, driver):
        """Test that we can connect to the iOS device."""
        print("\n📱 [SMOKE] Testing device connection...")

        # Just verify we have a session
        assert driver.session_id is not None, "Should have a valid session"
        print(f"✅ [SMOKE] Session ID: {driver.session_id}")

    @pytest.mark.timeout(30)
    def test_can_navigate_to_url(self, driver):
        """Test that Safari can navigate to a URL."""
        print("\n🌐 [SMOKE] Testing URL navigation...")

        driver.get("https://example.com")

        # Verify page loaded
        assert "example" in driver.page_source.lower(), "Should load example.com"
        print("✅ [SMOKE] Successfully navigated to example.com")

    @pytest.mark.timeout(10)
    def test_can_get_page_source(self, driver):
        """Test that we can read page source."""
        print("\n📄 [SMOKE] Testing page source access...")

        source = driver.page_source
        assert len(source) > 0, "Should get page source"
        print(f"✅ [SMOKE] Got page source ({len(source)} chars)")
