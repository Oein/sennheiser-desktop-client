# ZenControl — macOS controller for Sennheiser headphones

A native windowed macOS app that controls **Sennheiser ACCENTUM** (and other
Qualcomm-based Sennheiser models such as MOMENTUM 4) directly from macOS, without
the official Smart Control mobile app.

> Verified end-to-end against a real **ACCENTUM Wireless** (firmware 3.34.0):
> connects over the device's GAIA RFCOMM channel and reads/writes live state.

It was built by reverse-engineering the official **Sennheiser Smart Control Plus**
Android app (`com.sonova.chb.control`). See [PROTOCOL.md](PROTOCOL.md) for the full
analysis.

## What it does

A full port of the Smart Control app's device controls. From the window you can:

- **Noise Control** — Adaptive ANC / Transparency / Off, transparency level, Anti-Wind (Off/Max/Auto)
- **Equalizer** — 5-band graphic EQ, presets (Rock, Pop, Jazz, …) and Bass Boost
- **Sound** — Sidetone, Low Latency mode, Better Audio / Compatibility connection mode
- **Calls** — Auto-Answer, Comfort Call (in-call sidetone)
- **General** — Smart Pause, On-Head Detection, Podcast Mode, Voice/Tone Prompts (+ language), Auto Power-Off
- **Connected Devices** — view/connect/disconnect/remove the headphone's paired devices
- **Device** — model, firmware, hardware revision, serial, battery %, active codec, Factory Reset

Live state is also pushed by the headphones via GAIA notifications.

Not ported: firmware update (DFU) and telemetry/crash-dump upload (out of scope).

### Model-aware UI

The window only shows controls the **connected model** actually supports, mirroring the
official app. Profiles are derived from each model's `feature_variant_configs`:

| | ACCENTUM Wireless (`ACAEBT`) | ACCENTUM Plus (`ACPAEBT`) |
|---|---|---|
| Noise control | ANC on/off + Transparency + Anti-Wind | adaptive/custom (variant 2) |
| Transparency level | — (single step) | adjustable |
| Smart Pause / On-Head | — | ✓ |
| Auto-Answer / Comfort Call | — | ✓ |

Unknown Sennheiser GAIA models fall back to a permissive profile (all controls shown).

## How it works

Sennheiser ACCENTUM / MOMENTUM headphones use **Qualcomm GAIA V3** over a
**Bluetooth Classic RFCOMM** (Serial Port Profile) channel — *not* BLE. ZenControl:

1. Finds the paired headphone via `IOBluetooth`.
2. Runs an SDP query and locates the RFCOMM service named **"GAIA"**
   (on ACCENTUM this is channel 15; falls back to the Serial Port 0x1101 record).
3. Exchanges GAIA frames (vendor `0x0495` = Sennheiser) over that channel.

### Diagnostics (no UI)

```bash
./ZenControl.app/Contents/MacOS/ZenControl --selftest   # protocol unit checks
./ZenControl.app/Contents/MacOS/ZenControl --services   # list SDP records of paired devices
./ZenControl.app/Contents/MacOS/ZenControl --probe      # connect, dump live state, exit
```

## Build & run

Requires macOS 13+, Xcode/Swift toolchain.

```bash
cd ZenControl
./build_app.sh release       # produces ZenControl.app
open ZenControl.app
```

On first run macOS will ask for **Bluetooth** permission (declared in `Info.plist`).
The headphones must already be **paired and connected** to the Mac. The app opens a
window that auto-connects to the first paired Sennheiser device.

## Supported / tested

The protocol command set is shared across the current Sennheiser Qualcomm lineup, so
ACCENTUM Wireless, ACCENTUM Plus, ACCENTUM True Wireless and MOMENTUM 4 all use the
same GAIA commands. ACCENTUM Wireless is the primary target.

## Scope & limitations

- Equalizer is not yet wired up — it uses Qualcomm's separate User-EQ feature
  (native `libnative-peq`); the connection/EQ-read groundwork is present but the
  band-set UI is a TODO.
- Firmware update (DFU) is intentionally out of scope.
- This is an unofficial, community project and is not affiliated with Sennheiser/Sonova.
