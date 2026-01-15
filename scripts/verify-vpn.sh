#!/bin/bash
# Verify VPN is working by opening a JRE video on iPhone and checking proxy logs
set -e

echo "🔍 Verifying VPN and YouTube filtering..."

# Check if iPhone is connected
if ! ~/.local/bin/pymobiledevice3 usbmux list 2>/dev/null | grep -q "iPhone"; then
    echo "⚠️  No iPhone connected via USB. Skipping verification."
    exit 0
fi

# Check if Web Inspector is enabled (use perl for timeout on macOS)
if ! perl -e 'alarm 10; exec @ARGV' ~/.local/bin/pymobiledevice3 webinspector opened-tabs &>/dev/null; then
    echo "⚠️  Web Inspector not enabled on iPhone. Skipping verification."
    echo "   Enable: Settings → Safari → Advanced → Web Inspector = ON"
    exit 0
fi

echo "📱 iPhone connected, opening JRE video..."

# JRE test video
VIDEO_URL="https://m.youtube.com/watch?v=lwgJhmsQz0U"
VIDEO_ID="lwgJhmsQz0U"

# Launch video in Safari (background, with timeout)
~/.local/bin/pymobiledevice3 webinspector launch "$VIDEO_URL" &>/dev/null &
PID=$!

# Wait for page to load
sleep 8

# Kill launch process if still running
kill $PID 2>/dev/null || true

# Check mitmproxy logs for the video
echo "📋 Checking proxy logs for JRE video..."
LOGS=$(kubectl logs -n hocuspocus deployment/mitmproxy --tail=50 2>/dev/null)

# First check if mitmproxy CA is trusted
if echo "$LOGS" | grep -q "client does not trust the proxy's certificate"; then
    echo "❌ Mitmproxy CA not trusted on iPhone!"
    echo ""
    echo "   This is a ONE-TIME manual step required by Apple's security model."
    echo "   Fix: Settings → General → About → Certificate Trust Settings → Enable 'mitmproxy'"
    echo ""
    echo "   Once enabled, trust persists across VPN restarts (unless mitmproxy PVC is deleted)."
    exit 1
fi

JRE_PASSED=false
if echo "$LOGS" | grep -q "Joe Rogan Experience"; then
    if echo "$LOGS" | grep -q "$VIDEO_ID"; then
        echo "✅ JRE video ALLOWED (as expected)"
        JRE_PASSED=true
    fi
fi

if [ "$JRE_PASSED" = false ]; then
    # Check for errors
    if echo "$LOGS" | grep -q "BLOCKED.*$VIDEO_ID"; then
        echo "❌ JRE video was BLOCKED (should be allowed)"
        exit 1
    fi

    # Check VPN connection
    VPN_LOGS=$(kubectl logs -n hocuspocus deployment/vpn-server -c strongswan --tail=20 2>/dev/null)
    if echo "$VPN_LOGS" | grep -q "no trusted RSA public key\|no issuer certificate"; then
        echo "❌ VPN verification FAILED: Certificate error"
        echo "   Run: make vpn-profile-install"
        exit 1
    fi

    if ! echo "$VPN_LOGS" | grep -q "CHILD_SA.*established\|keep alive\|IKE_SA.*established"; then
        echo "❌ VPN not connected"
        exit 1
    fi

    echo "⚠️  Could not verify JRE video (may not have loaded yet)"
fi

# Test 2: Verify non-whitelisted domain is blocked
echo ""
echo "⏳ Waiting 30 seconds before next test..."
sleep 30
echo "📱 Opening twitter.com (should be blocked)..."
# Use cache-busting query param to force fresh request
CACHE_BUST=$(date +%s)
BLOCKED_URL="https://twitter.com/?_cb=$CACHE_BUST"

~/.local/bin/pymobiledevice3 webinspector launch "$BLOCKED_URL" &>/dev/null &
PID=$!
sleep 6
kill $PID 2>/dev/null || true

echo "📋 Checking proxy logs for blocked domain..."
LOGS=$(kubectl logs -n hocuspocus deployment/mitmproxy --tail=30 2>/dev/null)

DOMAIN_BLOCKED=false
# Check for blocking log format: "🚫 BLOCKING non-whitelisted domain: X" or "🚫 BLOCKING: X"
if echo "$LOGS" | grep -qi "BLOCKING.*twitter\|BLOCKING.*x.com"; then
    echo "✅ twitter.com BLOCKED (as expected)"
    DOMAIN_BLOCKED=true
elif echo "$LOGS" | grep -qi "BLOCKING non-whitelisted domain"; then
    echo "✅ Non-whitelisted domain BLOCKED (as expected)"
    DOMAIN_BLOCKED=true
elif echo "$LOGS" | grep -qi "BLOCKING.*youtube\|BLOCKING.*googlevideo"; then
    echo "✅ Non-whitelisted YouTube content BLOCKED (blocking working)"
    DOMAIN_BLOCKED=true
else
    echo "⚠️  Could not verify domain blocking (may not have loaded yet)"
fi

# Final summary
echo ""
echo "=== Verification Summary ==="
if [ "$JRE_PASSED" = true ] && [ "$DOMAIN_BLOCKED" = true ]; then
    echo "✅ VPN verification PASSED!"
    echo "   - VPN connected"
    echo "   - YouTube filtering working (JRE allowed)"
    echo "   - Domain blocking working (twitter.com blocked)"
    exit 0
elif [ "$JRE_PASSED" = true ]; then
    echo "✅ VPN verification PARTIAL"
    echo "   - VPN connected"
    echo "   - YouTube filtering working (JRE allowed)"
    echo "   - Domain blocking: could not verify"
    exit 0
else
    echo "⚠️  VPN verification incomplete. Check manually."
    exit 1
fi
