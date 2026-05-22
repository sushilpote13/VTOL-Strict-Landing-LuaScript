#  VTOL Strict Landing — ArduPilot Lua Script

> **A custom ArduPilot Lua script for QuadPlane VTOL that enforces a strict two-phase precision landing — freezing altitude below 7 m until the craft is centred within 35 cm of the target. No drift, no off-target landings. Plug-and-play for Pixhawk.**

---

## 📋 Table of Contents

- [What Is This?](#what-is-this)
- [Where Is It Used?](#where-is-it-used)
- [Where Is It Placed?](#where-is-it-placed)
- [Prerequisites](#prerequisites)
- [Hardware Connections](#hardware-connections)
- [Installation](#installation)
- [How It Works](#how-it-works)
- [Parameters](#parameters)
- [GCS Messages Reference](#gcs-messages-reference)
- [Code Architecture](#code-architecture)
- [What I Learned](#what-i-learned)
- [Skills Developed](#skills-developed)
- [Troubleshooting](#troubleshooting)

---

## What Is This?

This is a **custom ArduPilot Lua script** that adds intelligent, two-phase precision landing behaviour to a QuadPlane VTOL. Instead of relying on ArduPilot's built-in precision landing (which can drift slightly), this script takes **direct control of the descent rate and waypoint targeting** to guarantee that the aircraft only descends when it is properly centred over the landing pad.

```
Above 7m  →  Steer toward target + normal descent allowed
Below 7m  →  STRICT: altitude frozen unless XY offset ≤ 35 cm
```

### Key Features

| Feature | Description |
|---|---|
| 🎯 Two-Phase Logic | Free approach above 7 m, strict precision below 7 m |
| 🔒 Altitude Lock | Freezes descent if target is lost OR if XY offset > 35 cm |
| 📡 Live GCS Feedback | Every state change logged to Mission Planner / QGroundControl |
| ⚙️ Configurable Params | Key values tunable via ArduPilot parameter system (no code edits needed) |
| 🛡️ Fault-Tolerant Loop | `pcall` wrapper catches Lua errors — loop never silently dies |
| 🔀 Dual-Mode | Works in `QLAND` automatically and in `QLOITER` via RC aux switch |

---

## Where Is It Used?

This script is designed for any **QuadPlane (VTOL) aircraft** running ArduPilot Plane firmware that needs to land on a specific, known point with high accuracy.

```
Real-world use cases:

  📦 Delivery Drones         →  Land on a customer pad, not the grass beside it
  🚢 Ship / Deck Landing     →  Recovery on a moving or constrained deck
  🔋 Autonomous Charging     →  Must connect to charging pins within centimetres
  🔬 Research / Survey       →  Repeatable landings on the same GCP marker
```

---

## Where Is It Placed?

The script file must be placed on the **Pixhawk SD card** at the following exact path:

```
SD Card
└── APM/
    └── scripts/
        └── vtol_strict_landing.lua   ← place here
```

> ⚠️ **Important:** ArduPilot only loads scripts from `/APM/scripts/` at the root level. Subdirectories are ignored.

On boot, ArduPilot automatically discovers and executes all `.lua` files in that folder. No additional configuration is needed to load the script — just place it there and power on.

---

## Prerequisites

### Firmware Requirements

- **ArduPilot Plane 4.3 or later** (Lua scripting API required)
- Vehicle type: **QuadPlane** (frame class 10, 13, etc.)

### Required ArduPilot Parameters

```
SCR_ENABLE      = 1         ← enables the Lua scripting engine
SCR_HEAP_SIZE   = 131072    ← 128 KB heap for scripts (minimum)
PLND_ENABLED    = 1         ← enables precision landing subsystem
PLND_TYPE       = 3         ← set to match your sensor (3 = IR-Lock)
```

### Hardware Required

| Component | Details |
|---|---|
| **Flight Controller** | Pixhawk 4 / 6C / Cube Orange or any ArduPilot-compatible FC |
| **Precision Landing Sensor** | IR-Lock + IR Beacon, or camera with ArUco / AprilTag |
| **MicroSD Card** | FAT32 formatted — scripts load from here |
| **RC Transmitter** | One spare channel for the PRECLOITER aux switch |
| **Landing Pad / Beacon** | IR-reflective beacon or printed AprilTag marker |

### Software / Tools

- Mission Planner 1.3.80+ or QGroundControl
- A text editor (VS Code recommended) to read or modify the `.lua` file

---

## Hardware Connections

```
┌─────────────────────────────────────────────────────────┐
│                      PIXHAWK FC                         │
│                  (ArduPilot Plane)                      │
│                                                         │
│   UART/I2C ←── IR-Lock Sensor   (PLND_TYPE = 3)        │
│   PWM IN   ←── RC Receiver      (AUX CH → option 39)   │
│   SD Card  ←── /APM/scripts/    (Lua script lives here) │
│   MAVLink  ──→ Mission Planner  (GCS messages)          │
│   PWM OUT  ──→ 4× VTOL Motors   (descent rate control)  │
└─────────────────────────────────────────────────────────┘
                              ↑
                    IR Beacon on ground
                    (the landing target)
```

### RC Aux Channel Setup

In Mission Planner → Config → Extended Tuning, assign one channel to option `39`:

```
RC7_OPTION = 39    ← example using channel 7

Switch LOW  (PWM < 1200)  →  PRECLOITER OFF
Switch HIGH (PWM > 1800)  →  PRECLOITER ON  (activates in QLOITER mode)
```

---

## Installation

**Step 1 — Enable Lua Scripting**

In Mission Planner → Full Parameter List:
```
SCR_ENABLE    = 1
SCR_HEAP_SIZE = 131072
```
Reboot the flight controller.

**Step 2 — Configure Precision Landing**

```
PLND_ENABLED = 1
PLND_TYPE    = 3    ← or whichever matches your sensor
```
Reboot again after changes.

**Step 3 — Copy the Script to the SD Card**

Remove the SD card from the Pixhawk (or use USB mass storage). Navigate to `/APM/scripts/` — create it if it doesn't exist. Copy the file:

```
vtol_strict_landing.lua  →  /APM/scripts/vtol_strict_landing.lua
```

**Step 4 — Power On and Verify Load**

Re-insert the SD card and power on. Watch GCS messages — you should see:
```
PLND: UPDATED 7m LOGIC LOADED
```

**Step 5 — Confirm Parameters Appeared**

After the first boot, these parameters will appear in the Full Parameter List:
```
PLND_XY_GAIN
PLND_DESCENT_RAD
PLND_LOST_HOLD
```

**Step 6 — Set the RC Aux Channel**

```
RC7_OPTION = 39    ← assigns PRECLOITER function to channel 7
```

**Step 7 — Bench Test Target Detection**

Hold the aircraft over the landing beacon on a bench. Confirm:
```
GCS → "PLND: TARGET ACQUIRED"   ← sensor sees the beacon
GCS → "PLND: TARGET LOST"       ← when you cover the sensor
```

**Step 8 — First Flight Test**

In a safe open area, command a QLAND from 15 m above the beacon. Observe the two-phase behaviour in GCS messages. Verify touchdown is within ~35 cm of the beacon.

---

## How It Works

The script runs a **protected update loop at 10 Hz** (every 100 ms). On each tick it reads altitude, checks target visibility, and applies one of two rule-sets.

### Two-Phase Logic

```
ALTITUDE
   │
16m┤  ╔══════════════════════════════════╗
   │  ║  PHASE 1 — FREE APPROACH         ║
   │  ║  • Steer toward target if seen   ║
   │  ║  • Normal descent rate allowed   ║
 7m┤──╠══════════════════════════════════╣── threshold
   │  ║  PHASE 2 — STRICT PRECISION      ║
   │  ║  • XY correction every tick      ║
   │  ║  • Descent ONLY if within 35cm   ║
   │  ║  • Target lost → altitude FROZEN ║
 0m┤  ╚══════════════════════════════════╝
   └─────────────────────────────────────→ Time
```

### Decision Flow — Per Tick

```
update() called @ 10 Hz
│
├── PLND_ENABLED < 1?  →  ABORT (script disabled)
│
├── precision_landing_active()?
│     ├── NO  →  return (wrong mode / switch off)
│     └── YES ↓
│
├── read altitude from AHRS (NED frame, -Z = up)
│
├── update_target()
│     ├── precland:target_acquired() → update last_seen_time
│     └── have_target = (now - last_seen_time) < 500ms
│
├── current_alt > 7.0m?
│     ├── YES — PHASE 1
│     │     ├── have_target? YES → steer toward target (XY_GAIN applied)
│     │     │               NO  → no override, descend normally
│     │     └── set_descent_rate(Q_LAND_FINAL_SPD)  →  RETURN
│     │
│     └── NO — PHASE 2 (strict)
│           ├── have_target? NO → set_descent_rate(0)  HOLD  →  RETURN
│           ├── apply XY correction to next waypoint (always)
│           ├── compute xy_dist to target
│           └── xy_dist ≤ 0.35m?
│                 ├── YES → set_descent_rate(Q_LAND_FINAL_SPD)  DESCEND
│                 └── NO  → set_descent_rate(0)  HOLD ALT
```

### Key Code — Phase 2 Descent Gate

```lua
-- Below 7m: only descend when centred
if xy_dist <= PLND_DESCENT_RADIUS:get() then

    vehicle:set_land_descent_rate(Q_LAND_FINAL_SPD:get())
    gcs:send_text(MAV_SEVERITY.INFO, "PLND: CENTERED - DESCENT ENABLED (<7m)")

else
    vehicle:set_land_descent_rate(0)   -- altitude frozen
    gcs:send_text(MAV_SEVERITY.INFO,
        string.format("PLND: HOLD ALT (XY=%.2fm <7m)", xy_dist))
end
```

### Target Hysteresis

```lua
-- Target is considered "seen" for 500ms after last acquisition.
-- Prevents single-frame sensor glitches from triggering altitude holds.

have_target = (millis() - last_seen_time) < 500
```

### Fault-Tolerant Loop

```lua
-- pcall wraps the entire update so a Lua error never kills the loop.
local function protected_wrapper()
    local ok, err = pcall(update)
    if not ok then
        gcs:send_text(MAV_SEVERITY.ERROR, "PLND ERROR: " .. err)
        return protected_wrapper, 1000   -- retry in 1 second
    end
    return protected_wrapper, 100        -- normal 10 Hz rate
end
```

---

## Parameters

After first boot with the script loaded, these parameters appear in Mission Planner's Full Parameter List:

| Parameter | Default | Description |
|---|---|---|
| `PLND_XY_GAIN` | 2.5 | Amplifies XY steering correction. Higher = more aggressive. Reduce if oscillating. |
| `PLND_DESCENT_RAD` | 0.35 m | Max XY offset allowed before descent is permitted in Phase 2. |
| `PLND_LOST_HOLD` | 1 | 1 = freeze altitude when target is lost below 7 m. 0 = continue descending. |
| `PLND_ENABLED` | (from PLND) | Master on/off. If 0, script exits immediately and does nothing. |

> 💡 **Tuning tip:** If the aircraft oscillates around the target, lower `PLND_XY_GAIN` from 2.5 to 1.5. If it converges slowly, increase to 3.0. Do not exceed 4.0.

---

## GCS Messages Reference

| Message | Severity | Meaning |
|---|---|---|
| `PLND: UPDATED 7m LOGIC LOADED` | INFO | Script loaded and running on boot |
| `PLND: Disabled` | INFO | `PLND_ENABLED = 0` — script is dormant |
| `PLND: TARGET ACQUIRED` | INFO | Sensor locked onto the landing beacon |
| `PLND: TARGET LOST` | WARNING | Beacon not seen for >500 ms |
| `PLND: HOLD ALT (TARGET LOST <7m)` | WARNING | Below threshold, target gone — altitude frozen |
| `PLND: CENTERED - DESCENT ENABLED (<7m)` | INFO | XY offset ≤ 35 cm — descent active |
| `PLND: HOLD ALT (XY=X.XXm <7m)` | INFO | Too far from centre — shows current offset |
| `PLND: PRECLOITER ENABLED` | INFO | RC aux switch flipped HIGH |
| `PLND: PRECLOITER DISABLED` | INFO | RC aux switch flipped LOW |
| `PLND ERROR: <message>` | ERROR | Lua runtime exception caught — script continues |

---

## Code Architecture

```
vtol_strict_landing.lua
│
├── Constants & Mode IDs
│     ├── MODE_QLAND = 20
│     ├── MODE_QLOITER = 19
│     ├── AUX_PRECLOITER = 39
│     └── ALT_THRESHOLD = 7.0 m
│
├── Parameter Registration
│     ├── param:add_table()       — register "PLND_" namespace
│     ├── PLND_XY_GAIN            (idx 1, default 2.5)
│     ├── PLND_DESCENT_RAD        (idx 2, default 0.35)
│     └── PLND_LOST_HOLD          (idx 4, default 1)
│
├── update_target()
│     ├── precland:healthy()      — guard check
│     ├── precland:target_acquired() → update last_seen_time
│     └── have_target = (millis - last_seen_time) < 500
│
├── precision_landing_active()
│     ├── QLOITER mode → return precloiter_enabled flag
│     └── else → in_vtol_land_descent() OR QLAND mode
│
├── precloiter_check()
│     └── rc:get_aux_cached(39) → set precloiter_enabled
│
├── update()   — main 10 Hz loop
│     ├── Guard checks (enabled / active / altitude available)
│     ├── update_target()
│     ├── Phase 1 (alt > 7m)
│     │     ├── steer toward target if visible (XY_GAIN applied)
│     │     └── allow normal descent rate
│     └── Phase 2 (alt ≤ 7m)
│           ├── target lost → set_descent_rate(0)
│           ├── XY correction always applied
│           ├── centred (≤35cm) → set_descent_rate(FINAL_SPD)
│           └── off-centre → set_descent_rate(0)
│
└── protected_wrapper()
      ├── pcall(update)
      ├── error → log + retry in 1000 ms
      └── success → reschedule in 100 ms (10 Hz)
```

---

## What I Learned

**1. Embedded Lua runs differently from desktop Lua**
The ArduPilot Lua sandbox exposes a limited, aviation-specific API. Learning which functions exist, when they return `nil` vs raise errors, and how to safely guard every return value was the biggest initial challenge.

**2. Safety logic must be explicitly designed — it doesn't happen automatically**
A naive script that always descends will always land *somewhere*, but not reliably *on target*. Every edge case — target lost, sensor lag, XY drift — had to be explicitly handled with a deliberate altitude-freeze decision.

**3. The 500 ms hysteresis window prevents false altitude holds**
Without `last_seen_time`, any single-frame sensor glitch would immediately freeze altitude and interrupt the landing sequence. The 500 ms window absorbs brief occlusions while still reacting quickly to real target loss.

**4. `pcall` is mandatory in a 10 Hz aviation loop**
If any unprotected Lua error occurs, the script silently dies and leaves the vehicle without the override. Wrapping `update()` in `pcall` ensures the loop always reschedules — even if one tick throws an exception.

**5. Gain tuning matters as much as algorithm design**
`PLND_XY_GAIN = 2.5` works well in calm conditions but can cause oscillations in gusty wind or with high-latency sensors. Exposing it as a parameter rather than a hard-coded constant made field tuning possible without reflashing firmware.

**6. Coordinate frames require careful attention**
ArduPilot uses NED (North-East-Down) internally, so altitude is `-Z`. Using `ahrs:get_relative_position_NED_home()` and negating the Z component to get a positive altitude above home was a non-obvious but critical detail.

---

## Skills Developed

```
Programming & Embedded Systems
  ✦ Lua scripting in a resource-constrained embedded environment
  ✦ ArduPilot Scripting API (vehicle, ahrs, precland, rc, param, gcs)
  ✦ Error-tolerant loop design with pcall
  ✦ Parameter table registration and runtime binding

Flight Systems & Control
  ✦ VTOL QuadPlane flight dynamics
  ✦ Precision landing sensor integration (IR-Lock / vision)
  ✦ Descent rate control via set_land_descent_rate()
  ✦ Waypoint override with update_target_location()
  ✦ NED coordinate frame and altitude reference systems

Software Architecture
  ✦ Two-phase state machine design
  ✦ Hysteresis and debouncing for sensor signals
  ✦ Real-time safety system design
  ✦ Configurable parameters vs hard-coded constants trade-offs

Systems & Integration
  ✦ MAVLink GCS telemetry and severity levels
  ✦ RC aux channel reading and mode switching
  ✦ Hardware-software integration (Pixhawk, sensor, SD card)
  ✦ Flight testing methodology and iterative gain tuning
```

---

## Troubleshooting

**Script not loading — "PLND: UPDATED 7m LOGIC LOADED" never appears**

- Check `SCR_ENABLE = 1` and reboot
- Confirm file is at exactly `/APM/scripts/vtol_strict_landing.lua`
- Verify SD card is FAT32 formatted and readable

**PLND parameters don't appear after boot**

- The script likely failed to execute (Lua syntax error or heap exhaustion)
- Check GCS log for `PLND ERROR:` messages
- Increase `SCR_HEAP_SIZE` to `131072` or higher

**TARGET ACQUIRED never shows despite sensor being connected**

- Verify `PLND_TYPE` matches your sensor's driver number exactly
- Check wiring to the correct UART or I2C port
- Test sensor detection in Mission Planner's Precision Landing live view
- Check `PLND_ORIENT` if the camera is not mounted facing straight down

**Aircraft oscillates at target instead of landing**

- Reduce `PLND_XY_GAIN` from 2.5 to 1.5 or 2.0
- Check for sensor latency — high-latency sensors amplify oscillation
- Consider increasing `PLND_DESCENT_RAD` slightly to 0.5 m

**Altitude holds indefinitely below 7 m — never descends**

- Confirm the beacon is centred under the aircraft (check GCS XY distance)
- Verify `PLND_DESCENT_RAD` is set correctly (default 0.35 m)
- Check that `PLND_LOST_HOLD = 1` isn't keeping it frozen due to target loss — cover and uncover the sensor to see if `TARGET ACQUIRED` fires

---

## License

MIT — free to use, modify, and distribute. Contributions welcome.

---

*Built for precision. Lands with precision.*
