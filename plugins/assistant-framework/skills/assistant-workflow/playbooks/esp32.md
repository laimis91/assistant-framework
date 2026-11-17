# ESP32 / Embedded (PlatformIO)

**Architecture:** Layered — HAL → Services → Application → main

## Folder structure
```
project/
  src/
    main.cpp              # Setup + loop, wires everything
    app/                  # Application logic, state machines
    services/             # WiFi, MQTT, sensor reading, LED control
    hal/                  # Hardware abstraction (pin configs, drivers)
  include/
    config.h              # All pin assignments, thresholds, timing constants
  lib/                    # Project-specific libraries
  test/                   # Unity (C test framework) tests
  platformio.ini
```

## Typical Discovery Q&A
```
1. Board?
   a) ESP32-DevKitC  b) ESP32-S3  c) ESP32-C3  d) Other
2. Framework?
   a) Arduino (faster start, recommended)
   b) ESP-IDF (full control, FreeRTOS)
3. Connectivity?
   a) WiFi only  b) WiFi + BLE  c) BLE only  d) None
4. Communication protocol?
   a) MQTT  b) HTTP REST  c) WebSocket  d) ESPNow
5. Power mode?
   a) Always on (USB)  b) Deep sleep (battery)  c) Light sleep
```

## Architecture rules (Plan phase)
- hal/: ONLY pin definitions and hardware-specific drivers
- services/: never directly access GPIO — go through hal/
- app/: state machines and logic — no hardware calls
- main.cpp: only wires dependencies and runs the loop
- All magic numbers in config.h (#define or constexpr)
- Pin assignments never hardcoded in logic files
- ISR handlers: minimal work, set flag, process in loop
- No blocking delays in app/ — use millis()-based timing

## Design rules
N/A — no UI. If device has display (OLED, TFT), define screen layouts in a display service under services/.

## Build/test
```
pio run                          # Build
pio run --target upload          # Flash
pio device monitor --baud 115200 # Serial monitor
pio test -e native               # Logic tests (no device)
pio test -e esp32dev             # On-device tests
```
