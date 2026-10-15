# Sennheiser Smart Control — protocol analysis

Analysis of `Sennheiser+Smart+Control+Plus_1.5.0_APKPure.xapk`
(package `com.sonova.chb.control`, v1.5.0).

## App architecture

- **Flutter app** (Dart AOT in `lib/arm64-v8a/libapp.so` + `libflutter.so`).
- Native helpers: `libnative-anc*.so` (ANC tuning), `libnative-peq.so` (parametric EQ),
  `libnative-ha.so`, `libmusic_fit_native-lib.so`.
- Per-device capability descriptors in
  `assets/flutter_assets/assets/configs/*.json` and `dev_configs/*.json`.
- Maps (Mapbox) and Firebase are bundled but irrelevant to device control.

### Device → product code map (`configs/root.json`)

| code | model        | json        | transport |
|------|--------------|-------------|-----------|
| 0005 | MOMENTUM 4   | `m4`        | BLE→Classic |
| 0007 | **ACCENTUM Wireless** | `acc1` | **Bluetooth Classic** |
| 0008 | **ACCENTUM Plus**     | `accPlus1` | **Bluetooth Classic** |
| 0010 | **ACCENTUM True Wireless** | `accTw1` | **Bluetooth Classic** |
| …    | CX / MTW3/4 / M5 …    | …        | BLE / Classic |

Each config lists `feature_variant_configs` (NoiseControl, Equalizer, Battery,
Sidetone, SmartPause, OnHeadDetection, Codec, …) with a `variant` number, plus the
`connection_type` per firmware version. **All ACCENTUM variants are `Classic`.**

## Transport

Sennheiser's Qualcomm-based headphones expose a **Bluetooth Classic RFCOMM / Serial
Port Profile** channel and speak **Qualcomm GAIA V3** on it. (Newer BLE-only models
use GATT services `8769c9b6-…` / `a2129ff3-…`; ACCENTUM does not.)

On macOS the channel is reached with `IOBluetooth`: SDP-query the paired device and
open the RFCOMM service. On a real **ACCENTUM** the relevant SDP record is literally
named **"GAIA"** and sits on **RFCOMM channel 15** (alongside two Hands-Free records
on channel 10), confirmed by `--services`:

```
Device: ACCENTUM  [80-c3-ba-7f-48-ca]
  • GAIA           rfcomm=15
  • Hands-Free unit rfcomm=10
```

**macOS 27:** the cached SDP records no longer carry the ServiceName (0x0100) for
the GAIA record, and ServiceClassIDList (0x0001) comes back as a bare UUID instead
of a sequence. The GAIA record is still identifiable by its service-class UUID
`a2129ff3-081b-4c45-8afe-469d9c4842ec` (the same UUID BLE models use as a GATT
service). Note channel **14** is Apple **iAP2** (`00000000-deca-fade-deca-deafdecacaff`):
opening it and sending GAIA frames makes the headset power off, so never fall back to it.

```
Device: ACCENTUM  [80-c3-ba-7f-48-ca]       (macOS 27)
  • (unnamed)        rfcomm=14  uuids=[00000000-deca-fade-deca-deafdecacaff]   iAP2
  • Hands-Free unit  rfcomm=10  uuids=[0x111e]
  • (unnamed)        rfcomm=15  uuids=[a2129ff3-081b-4c45-8afe-469d9c4842ec]   GAIA
```

## GAIA V3 frame format

```
 byte 0   0xFF                  start of frame / version
 byte 1   0x03                  flags
 byte 2-3 payload length        big-endian
 byte 4-5 vendor id             0x0495 Sennheiser · 0x001D Qualcomm core
 byte 6-7 command id            big-endian
 byte 8.. payload
```

Command-id convention: request `id`, response `id|0x0100`, async notification
`id|0x0080`, error `id|0x0180`.

### Verified captures

```
GET battery   FF 03 00 00 04 95 06 03   ->  FF 03 00 01 04 95 07 03 2A           (0x2A = 42 %)
GET ANC modes FF 03 00 00 04 95 1A 01   ->  FF 03 00 06 04 95 1B 01 01 02 02 00 03 01
GET model id  FF 03 00 00 04 95 12 06   ->  FF 03 00 0D 04 95 13 06 "MMMMBT Black\0"
GET codec     FF 03 00 00 04 95 08 00   ->  FF 03 00 01 04 95 09 00 05            (5 = aptX-HD)
```

## Command catalog (vendor 0x0495 unless noted)

| feature | op | request id | response/notif |
|---|---|---|---|
| Noise-control mode | SET `[mode,state]` | `1A00` | `1B00` |
| Noise-control mode | GET | `1A01` | `1B01` / notif `1A81` |
| ANC on/off | SET `[0/1]` / GET | `1A04` / `1A05` | `1B04` / `1B05` |
| Transparency level | SET `[lvl]` / GET | `1A02` / `1A03` | `1B02` / `1B03` |
| Battery % | GET | `0603` | `0703` / notif `0683` |
| Codec in use | GET | `0800` | `0900` |
| Model id (string) | GET | `1206` | `1306` |
| Firmware version (3×u16) | GET | `1201` | `1301` |
| Sidetone level 0–5 | SET / GET | `0805` / `0806` | `0905` / `0906` |
| Smart Pause | SET `[0/1]` / GET | `080C` / `080D` | `090C` / `090D` |
| On-Head Detection | SET `[0/1]` / GET | `0400` / `0401` | `0500` / `0501` |
| Register notification | INVOKE `[featureID]` | `0007` | `0107` |
| Core: supported features | INVOKE | `001D:0001` | `001D:0101` |

### ACCENTUM noise control (verified on real hardware)

The combined-mode property `1A00/1B01` is a MOMENTUM-4-ism. On **ACCENTUM** it
reports all-zero and ignores writes. ACCENTUM instead uses two independent boolean
toggles, confirmed by driving the device and watching its notifications:

| control | SET | GET → resp | notif |
|---|---|---|---|
| **ANC on/off** | `1A04 [0/1]` → `1B04` | `1A05` → `1B05` | `1A85` |
| **Transparency on/off** | `1804 [0/1]` → `1904` | `1805` → `1905` | `1885` |
| Transparency level | `1A02 [lvl]` | `1A03` → `1B03` | `1A83` |

The audible mode is derived: transparency-on ⇒ Transparency, else ANC-on ⇒ ANC,
else Off. To switch cleanly the app drives both toggles, e.g. ANC =
`1804 00` + `1A04 01`. Captured exchange:

```
>> ff03000104951a0400   (ANC off)   << 1b04   << 1a85 00
>> ff03000104951a0401   (ANC on)    << 1b04   << 1a85 01
>> ff0300010495180401   (transp on) << 1904   << 1a83 64
```

> Note: the older `1A00/1B01` "three (mode,state) pairs" encoding
> (`mode` 1 = anti-wind, 2 = transparency, 3 = adaptive; `state` 0/1/2) still
> applies to MOMENTUM 4.

**Register-notification feature ids** (Sennheiser, via `0x0007 [featureID]`):
battery = 3, genericAudio = 4, userEQ = 8, versions = 9, deviceManagement = 10,
mmi = 11, transparentHearing = 12, ANC = 13. After subscribing, the device emits the
matching `…81/…83/…85` notification frames on every change.

### Equalizer (UserEq, feature 8, base 0x1000)

Confirmed against the same Sennheiser GAIA stack (HDB 630). 5-band graphic EQ:

| cmd | op | payload |
|---|---|---|
| `1000` | GET config | → `[bands, minGain_i7, maxGain_i7, …]` (gain ÷10 dB; ACCENTUM = 5 bands, ±6 dB) |
| `1001` | SET band | `[band 0-4, gain_i8]` where gain = dB×10 |
| `1002` | GET band | `[band]` → `[gain_i8]` |
| `1082` | notif | all 5 band gains (i8, dB×10) |
| `1008` / `1009` | SET/GET bass boost | `[0/1]` |

Band centres: 50 / 250 / 800 / 3000 / 8000 Hz. (A parametric path exists at
`0x100A–0x1013` — stage frequency/Q/type/gain/pre-gain — not used here.)

### Other ported commands (Sennheiser vendor 0x0495)

Sidetone `0805/0806`, Auto-Answer `080A/080B`, Comfort Call `0814/0815`,
Low Latency `0817/0818`, BT Compatibility `0405/0406`, Audio/Podcast mode
`0803/0804` (`[00, mode]`, podcast = 2), Voice/Tone prompt `0801/0802`, prompt
language `0807`, Auto Power-Off timer `0600/0601` (`[timerID 0, value_u16]`),
paired devices `1400`/`1401`/`1402`/`1403`/`1405`, HW revision `1200`,
serial `001D:0003`, factory reset `0040`.

These command ids are shared across the Sennheiser Qualcomm lineup (the m4 / acc1 /
accTw1 configs reference the same `*Gaia3FeatureVariant` handlers), so the ACCENTUM
family uses the same set.
