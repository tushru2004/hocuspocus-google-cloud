# Mac DFU Mode Instructions

> Note: This document is for **macOS supervision/restore** workflows only.
> For **iPhone E2E/Appium/WebDriverAgent** setup, see `tests/e2e/README.md` in the repo root.

## Enter DFU Mode from Setup Assistant (Language Screen)

1. Make sure **USB-C cable** is connected to Admin Mac (use **left-most port** on both Macs)
2. Open **Apple Configurator 2** on Admin Mac
3. On target MacBook at language screen, press and hold:
   - **Left Control + Left Option + Right Shift + Power** (hold 10 seconds)
   - Release all except **Power** (hold 3 more seconds)
4. Screen stays black - Apple Configurator should show **DFU** icon

## Enter DFU Mode from Any State (Mac can be ON)

1. Connect USB-C cable first (Admin Mac ↔ Target Mac, left-most ports)
2. Open Apple Configurator on Admin Mac
3. Target Mac can be powered on (Setup Assistant, login screen, or desktop)
4. On target Mac, press and hold all 4 keys:
   - **Left Control + Left Option + Right Shift + Power**
5. Screen goes black → keep holding for **3 more seconds**
6. Release Control, Option, Shift — but **keep holding Power**
7. Hold Power for **5-10 more seconds**
8. Apple Configurator should show **DFU**

## Important Notes

- Use a **USB-C data cable** (NOT Thunderbolt cable - no lightning bolt icon)
- Use the **left-most USB-C port** on Apple Silicon Macs (closest to hinge on MacBooks)
- On Admin Mac: System Settings → Privacy & Security → set "Allow accessories to connect" to **"Automatically when unlocked"**

## Supervised Restore with Apple Configurator

1. Enter DFU mode (see above)
2. In Apple Configurator: **File → New Blueprint**
3. Enable **"Supervise devices"** in Blueprint settings
4. Save Blueprint
5. Right-click DFU device → **Restore**
6. Apply your supervised Blueprint when prompted

## Pre-download IPSW (Optional)

To avoid download during restore:

```bash
# Install mist
brew install mist-cli

# List available versions
mist list firmware

# Download macOS
mist download firmware "macOS Tahoe" -o ~/Downloads/
```

Then drag the `.ipsw` file onto the DFU device in Apple Configurator.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| DFU not appearing | Try different USB-C cable (not Thunderbolt) |
| Timeout during restore | Pre-download IPSW, use different port |
| Mac enters Recovery instead | Make sure to hold all 4 keys, not just Power |
| Apple Configurator doesn't see device | Check cable, try different port, restart Configurator |
