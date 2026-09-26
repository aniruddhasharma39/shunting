# MASTER PROMPT — Shunting Firmware Codebase Migration Guide

> **PURPOSE**: This document is a ONE-TIME, COMPLETE reference for an AI coding agent assisting the hardware team in migrating or extending the Shunting Firmware codebase. It maps every AWS IoT-related component, certificate, key, topic, and provisioning flow so that **nothing that affects the cloud connection is accidentally broken**.

---

## 1. PROJECT OVERVIEW

This is a **railway shunting safety system** built on **STM32F411CEU6 (Black Pill)** + **A7670C GSM/LTE modem**, communicating over **AWS IoT Core** via **MQTT over TLS 1.2**.

The firmware lives in two STM32CubeIDE projects under one Git repository:

```
ShuntingFirmware/
├── STM_Blackpill_GSM_Transmitter/    ← TX unit (LiDAR sensor node)
└── STM_Blackpill_GSM_Receiver/       ← RX unit (HMI display + buzzer node)
```

**Communication model**: TX units publish LiDAR distance readings to AWS IoT. RX units subscribe to TX telemetry via AWS IoT wildcard topics. Both use the same AWS IoT account, same Fleet Provisioning template, same claim certificate, and the same Root CA.

---

## 2. ⛔ CRITICAL AWS INFRASTRUCTURE — ABSOLUTE DO-NOT-TOUCH ZONE

> [!CAUTION]
> The following items are **AWS IoT Core infrastructure**. Modifying, deleting, reordering, reformatting, or commenting-out ANY of these will **brick the device's cloud connection**, force re-provisioning, or permanently orphan the device from AWS IoT. The hardware team's AI agent **MUST NOT** touch these under any circumstances.

### 2.1 Files That Are 100% Off-Limits for Modification

| File (both TX and RX) | Why |
|---|---|
| `Core/Src/aws_manager.c` | Contains ALL AWS IoT provisioning logic, certificate handling, TLS configuration, MQTT topic construction, fleet provisioning state machine, and credential flash storage. **Every single function in this file is AWS-critical.** |
| `Core/Inc/aws_manager.h` | Public API for AWS IoT. Changing signatures breaks the caller chain. |
| `Core/Src/gsm_mqtt.c` | The A7670C AT-command MQTT/TLS driver. Handles SSL context, MQTT connect/subscribe/publish, URC parsing, and the incoming-message callback pipeline that feeds AWS provisioning responses. |
| `Core/Inc/gsm_mqtt.h` | Public types (`GSM_MQTT_Config`, `GSM_MQTT_IncomingCallback`, `gsm_link_state_t`) and function signatures used by aws_manager.c. |

### 2.2 Specific Code Sections — NEVER MODIFY

#### 2.2.1 AWS Root CA Certificate (identical in both TX and RX)
```
Location: aws_manager.c, lines ~114-134
Variable: static const char *AWS_ROOT_CA
```
This is the **Amazon Root CA 1** certificate. It is the trust anchor for TLS. If even one byte changes, the A7670C modem will reject the TLS handshake and the device will **never connect**.

#### 2.2.2 AWS Claim Certificate (identical in both TX and RX)
```
Location: aws_manager.c, lines ~145-165
Variable: static const char *AWS_CLAIM_CERT
```
This is the **Fleet Provisioning claim certificate** issued from AWS IoT Console. It is used ONLY during first-boot provisioning to request a permanent device certificate. **Do not replace, rotate, or regenerate this without coordinating with the AWS IoT Console admin.** If this certificate is deactivated or deleted in AWS, no new device can ever provision.

#### 2.2.3 AWS Claim Private Key (identical in both TX and RX)
```
Location: aws_manager.c, lines ~176-203
Variable: static const char *AWS_CLAIM_KEY
```
The RSA private key paired with the claim certificate above. **NEVER commit this to a public repository.** Do not change, truncate, or re-format it.

#### 2.2.4 Flash Credential Storage (identical in both TX and RX)
```
Location: aws_manager.c, lines ~30-56
Defines:
  - AWS_FLASH_STORAGE_ADDR = 0x08040000U (Flash Sector 6)
  - AWS_FLASH_SECTOR = FLASH_SECTOR_6
  - AWS_CREDENTIALS_MAGIC = 0x41575343U
Struct: AWS_StoredCredentials_t
```
After Fleet Provisioning succeeds, the device-specific certificate + private key are written to **STM32 internal flash Sector 6**. The struct layout, magic number, CRC algorithm, and flash address are all tightly coupled. Changing any of these will:
- Corrupt stored credentials on already-deployed devices
- Force every device to re-provision (which may fail if the Thing already exists in AWS)

**Functions that manage this (DO NOT TOUCH):**
- `AWS_CertStorage_Exists()`
- `AWS_CertStorage_Load()`
- `AWS_CertStorage_Save()`
- `AWS_CertStorage_Erase()`
- `CalculateCRC32()`

#### 2.2.5 Modem Certificate Download & SSL Configuration
```
Functions (DO NOT TOUCH):
  - DownloadCertToModem()       — uploads PEM data to A7670C via AT+CCERTDOWN
  - ConfigureModemSSL()         — sets TLS version, auth mode, and cert filenames via AT+CSSLCFG
```
These configure the modem's internal TLS engine. The filenames `"root_ca.pem"`, `"clientcert.pem"`, and `"clientkey.pem"` are referenced by the modem's SSL context. Renaming them or changing the SSL context index (0) will break TLS.

#### 2.2.6 Fleet Provisioning State Machine
```
Functions (DO NOT TOUCH):
  - AWS_IncomingCallback()      — handles $aws/certificates/create/json/accepted|rejected
                                   and $aws/provisioning-templates/.../provision/json/accepted|rejected
  - AWS_Init()                  — orchestrates the entire provisioning flow:
                                   1. Check flash for stored cert
                                   2. If none: connect with claim cert → request new cert → register thing → save to flash
                                   3. If found: connect with stored cert directly
                                   4. If stored cert rejected: erase and fall back to claim on next boot
  - find_json_val_end()         — JSON string parser for provisioning responses
```

#### 2.2.7 MQTT Topic Construction
```
Topic patterns (constructed in InitIdentity(), DO NOT TOUCH):
  - devices/{DEVICE_ID}/telemetry
  - devices/{DEVICE_ID}/status
  - devices/{DEVICE_ID}/commands
  - devices/{DEVICE_ID}/config
  - devices/{DEVICE_ID}/register
```
These topic patterns are mirrored in AWS IoT Rules, Lambda functions, and the Ikigai backend. Changing the pattern will silently disconnect the device from the entire data pipeline.

#### 2.2.8 Provisioning Topics (AWS Reserved)
```
$aws/certificates/create/json
$aws/certificates/create/json/accepted
$aws/certificates/create/json/rejected
$aws/provisioning-templates/ShuntingFleetTemplate/provision/json
$aws/provisioning-templates/ShuntingFleetTemplate/provision/json/accepted
$aws/provisioning-templates/ShuntingFleetTemplate/provision/json/rejected
```
These are **AWS IoT reserved system topics**. They are hardcoded and must match the provisioning template name exactly.

---

## 3. ⚠️ CONFIGURATION FILE — MODIFY WITH EXTREME CARE

### 3.1 `device_config.h` (exists in both TX and RX)

This is the **ONLY file you should edit for per-device identity**. It is the single source of truth for device identity.

#### Safe to change (per physical unit, before flashing):
```c
#define DEVICE_ID              "TX-03"          // or "RX-03"
#define DEVICE_SERIAL_NUMBER   "SN-TX-03"       // or "SN-RX-03"
#define DEVICE_NAME            "Shunting Transmitter Test"
#define DEVICE_HW_VERSION      "1.0"
#define DEVICE_FW_VERSION      "2.0.0"
#define DEVICE_MFG_DATE        "2026-09-01"
#define DEVICE_APN             "airtelgprs.com"  // Change for different SIM provider
```

#### ⛔ NEVER change these (AWS infrastructure):
```c
#define AWS_BROKER_URL         "tcp://a18ey7y7yi6gdo-ats.iot.ap-south-1.amazonaws.com:8883"
#define AWS_TEMPLATE_NAME      "ShuntingFleetTemplate"
#define MQTT_TOPIC_PREFIX      "devices"
```

- `AWS_BROKER_URL`: This is the AWS IoT Core ATS endpoint for the `ap-south-1` region. It is tied to the specific AWS account. Changing it disconnects from AWS entirely.
- `AWS_TEMPLATE_NAME`: Must match the Fleet Provisioning template created in the AWS IoT Console. Changing it means provisioning will fail with "template not found".
- `MQTT_TOPIC_PREFIX`: Used throughout the codebase for topic construction.

#### Safe to change (timeouts, tuning):
```c
#define TIMEOUT_MODEM_BOOT_MS       40000
#define TIMEOUT_SIM_READY_MS        10000
#define TIMEOUT_NETWORK_REG_MS      60000
#define TIMEOUT_APN_DATA_MS         15000
#define TIMEOUT_MQTT_CONNECT_MS     30000
#define TIMEOUT_PROVISIONING_MS     15000
#define TIMEOUT_OVERALL_PROV_MS     300000
#define TIMEOUT_FLASH_SAVE_MS       5000
#define TELEMETRY_INTERVAL_MS       10000
#define STATUS_HEARTBEAT_INTERVAL_MS 20000  // TX only
#define DEVICE_PRESENCE_TIMEOUT_MS   65000  // RX only
```

---

## 4. ✅ SAFE-TO-MODIFY ZONES — Hardware Team's Workspace

### 4.1 TRANSMITTER (`STM_Blackpill_GSM_Transmitter/`)

| File | Purpose | Safe to Modify? | Notes |
|---|---|---|---|
| `Core/Src/main.c` | Main loop, peripheral init | ✅ YES | Add new peripheral inits, sensors. Do NOT change `AWS_Init()` or `GSM_MQTT_Poll()` call patterns. |
| `Core/Inc/main.h` | HAL config, pin definitions | ✅ YES | Add new GPIO/UART/I2C/SPI handles as needed. |
| `Core/Src/tf02pro.c` | TF02-Pro LiDAR driver | ✅ YES | Sensor driver. Fully independent of AWS. |
| `Core/Inc/tf02pro.h` | TF02-Pro header | ✅ YES | |
| `Core/Src/cmd_router.c` | Command routing | ✅ YES | Not currently wired into main loop. |
| `Core/Inc/cmd_router.h` | Command routing header | ✅ YES | |
| `Core/Src/device_sm.c` | Device state machine | ✅ YES | Not currently wired into main loop. |
| `Core/Inc/device_sm.h` | Device SM header | ✅ YES | |
| `Core/Src/message.c` | Message formatting | ✅ YES | |
| `Core/Inc/message.h` | Message header | ✅ YES | |
| `Core/Src/logger.c` | Logging utility | ✅ YES | |
| `Core/Inc/logger.h` | Logger header | ✅ YES | |
| `Core/Src/stm32f4xx_hal_msp.c` | HAL MSP init (GPIO/UART pin mapping) | ✅ YES | Add new peripheral MSP inits. |
| `Core/Src/stm32f4xx_it.c` | Interrupt handlers | ✅ YES | Add new IRQ handlers. |
| `STM_Blackpill_GSM_Transmitter.ioc` | STM32CubeMX config | ✅ YES | Add new peripherals via CubeMX. |
| `*.ld` (linker scripts) | Flash/RAM layout | ⚠️ CAREFUL | Do NOT move Sector 6 (0x08040000) — that's where AWS credentials are stored. |

### 4.2 RECEIVER (`STM_Blackpill_GSM_Receiver/`)

| File | Purpose | Safe to Modify? | Notes |
|---|---|---|---|
| `Core/Src/main.c` | Main loop, peripheral init | ✅ YES | Add new peripherals. Do NOT change `AWS_Init()` or `GSM_MQTT_Poll()` call patterns. |
| `Core/Inc/main.h` | HAL config | ✅ YES | |
| `Core/Src/screen_sm.c` | Screen state machine (DWIN HMI) | ✅ YES | UI logic, fully independent of AWS. |
| `Core/Inc/screen_sm.h` | Screen SM header | ✅ YES | |
| `Core/Src/dwin_hmi.c` | DWIN display UART driver | ✅ YES | |
| `Core/Inc/dwin_hmi.h` | DWIN header | ✅ YES | |
| `Core/Inc/hmi_map.h` | HMI address/page mapping | ✅ YES | |
| `Core/Src/hmi_state.c` | HMI shared state | ✅ YES | |
| `Core/Inc/hmi_state.h` | HMI state header | ✅ YES | |
| `Core/Src/buzzer.c` | Buzzer/alarm driver (TIM2 PWM) | ✅ YES | |
| `Core/Inc/buzzer.h` | Buzzer header | ✅ YES | |
| `Core/Src/battery_soc.c` | INA226 battery SOC tracking | ✅ YES | |
| `Core/Inc/battery_soc.h` | Battery SOC header | ✅ YES | |
| `Core/Src/ina226.c` | INA226 I2C driver | ✅ YES | |
| `Core/Inc/ina226.h` | INA226 header | ✅ YES | |
| `Core/Src/charger_detect.c` | Charger detection (ADC + TIM3) | ✅ YES | |
| `Core/Inc/charger_detect.h` | Charger detect header | ✅ YES | |
| `Core/Src/tf02pro.c` | LiDAR driver (unused in RX but present) | ✅ YES | |
| `Core/Inc/tf02pro.h` | LiDAR header | ✅ YES | |
| `Core/Src/cmd_router.c` | Command routing | ✅ YES | |
| `Core/Src/device_sm.c` | Device state machine | ✅ YES | |
| `Core/Src/message.c` | Message formatting | ✅ YES | |
| `Core/Src/logger.c` | Logging | ✅ YES | |
| `Core/Src/stm32f4xx_hal_msp.c` | HAL MSP init | ✅ YES | |
| `Core/Src/stm32f4xx_it.c` | Interrupt handlers | ✅ YES | |
| `STM_Blackpill_GSM_Receiver.ioc` | CubeMX config | ✅ YES | |
| `*.ld` (linker scripts) | Flash/RAM layout | ⚠️ CAREFUL | Do NOT move Sector 6 (0x08040000). |

---

## 5. ARCHITECTURAL DATA FLOW — DO NOT BREAK THESE CONTRACTS

### 5.1 Transmitter Data Flow
```
┌─────────────┐    UART6     ┌──────────┐
│  TF02-Pro   │────────────→│  main.c  │
│   LiDAR     │  distance_cm │          │
└─────────────┘              │          │
                             │   calls  │
                             ▼          │
                   ┌─────────────────┐  │
                   │ AWS_PublishTelemetry() │
                   │ (aws_manager.c) │  │
                   └────────┬────────┘  │
                            │           │
                            ▼           │
                   ┌─────────────────┐  │
                   │ GSM_MQTT_PublishTopic() │
                   │ (gsm_mqtt.c)    │  │
                   └────────┬────────┘  │
                            │ AT+CMQTT  │
                            ▼           │
                   ┌─────────────────┐  │
                   │   A7670C Modem  │  │
                   │  (USART2 UART)  │  │
                   └────────┬────────┘  │
                            │ TLS/MQTT  │
                            ▼           │
                   ┌─────────────────┐  │
                   │  AWS IoT Core   │  │
                   │  ap-south-1     │  │
                   └─────────────────┘  
```

### 5.2 Receiver Data Flow
```
                   ┌─────────────────┐
                   │  AWS IoT Core   │
                   └────────┬────────┘
                            │ TLS/MQTT
                            ▼
                   ┌─────────────────┐
                   │   A7670C Modem  │
                   │  (USART2 UART)  │
                   └────────┬────────┘
                            │ +CMQTTRX URC
                            ▼
                   ┌─────────────────┐
                   │ GSM_MQTT_Poll() │──→ printIncoming() ──→ s_incomingCallback()
                   │ (gsm_mqtt.c)    │                            │
                   └─────────────────┘                            │
                                                                  ▼
                   ┌──────────────────────────────────────────────────┐
                   │ AWS_IncomingCallback()  (aws_manager.c)          │
                   │  ├─ /status topic    → GSM_MarkDeviceOnline()   │
                   │  ├─ /telemetry topic → GSM_SetLatestDistance()  │
                   │  ├─ provisioning topics → internal state machine│
                   │  └─ /commands, /config → (future use)           │
                   └──────────────────────────────┬───────────────────┘
                                                  │
                                    ┌─────────────▼─────────────┐
                                    │   g_hmi (hmi_state.h)     │
                                    │   ├─ distance_m           │
                                    │   ├─ connected_device_num │
                                    │   ├─ battery_pct          │
                                    │   └─ charger_plugged      │
                                    └─────────────┬─────────────┘
                                                  │
                                    ┌─────────────▼─────────────┐
                                    │  ScreenSM_Tick()          │
                                    │  (screen_sm.c)            │
                                    │  → DWIN HMI display       │
                                    │  → Buzzer alarms          │
                                    └───────────────────────────┘
```

### 5.3 MQTT Topic Subscriptions (Receiver)
The Receiver subscribes to these wildcard topics in `AWS_RestoreSubscriptions()`:
```
devices/{RX_DEVICE_ID}/commands     ← commands for this receiver
devices/{RX_DEVICE_ID}/config       ← config for this receiver
devices/+/status                    ← presence heartbeats from ALL devices
devices/+/telemetry                 ← telemetry from ALL transmitters
```

### 5.4 MQTT Topic Publishes (Both)
```
Transmitter publishes to:
  devices/{TX_ID}/telemetry     ← distance, battery, diagnostics
  devices/{TX_ID}/status        ← heartbeat (ONLINE)
  devices/{TX_ID}/register      ← device registration payload
  devices/{TX_ID}/config        ← device config payload

Receiver publishes to:
  devices/{RX_ID}/telemetry     ← aggregated distance, battery, diagnostics
  devices/{RX_ID}/status        ← heartbeat (ONLINE)
  devices/{RX_ID}/register      ← device registration payload
  devices/{RX_ID}/config        ← device config payload
```

---

## 6. HARDWARE INTERFACE MAP

### 6.1 Transmitter Peripherals
| Peripheral | STM32 Pins | Purpose | UART Handle |
|---|---|---|---|
| A7670C Modem | PA2 (TX), PA3 (RX) | GSM/LTE/MQTT | `huart2` |
| TF02-Pro LiDAR | PA11 (TX), PA12 (RX) | Distance measurement | `huart6` |
| Status LED | PC13 | Link activity indicator | GPIO |

### 6.2 Receiver Peripherals
| Peripheral | STM32 Pins | Purpose | Handle |
|---|---|---|---|
| A7670C Modem | PA2 (TX), PA3 (RX) | GSM/LTE/MQTT | `huart2` |
| DWIN HMI Display | PA9 (TX), PA10 (RX) | Touchscreen display | `huart1` |
| Buzzer | PA0 | Distance alarm (TIM2 CH1 PWM) | `htim2` |
| INA226 Battery | PB6 (SCL), PB7 (SDA) | Battery SOC via I2C | `hi2c1` |
| Charger Detect | PA1 (ADC1 CH1) | USB charger voltage sense | `hadc1` |
| Charger Timer | — | Periodic ADC sampling | `htim3` |
| Status LED | PC13 | Link activity indicator | GPIO |

---

## 7. RULES FOR ADDING NEW FEATURES

### ✅ ALLOWED — Adding New Sensors/Peripherals
1. Add new `.c`/`.h` files in `Core/Src/` and `Core/Inc/`
2. Add CubeMX peripheral configuration in the `.ioc` file
3. Initialize in `main.c` after existing inits
4. Call your sensor read functions in the `while(1)` loop

### ✅ ALLOWED — Adding New Telemetry Fields
If you want to send additional sensor data to AWS:
1. **DO NOT** modify `AWS_PublishTelemetry()` signature or its JSON structure
2. Instead, create a **new publish function** in your own `.c` file that calls `GSM_MQTT_PublishTopic()` with your own topic and payload
3. Or, propose a new telemetry function to the firmware team who maintains `aws_manager.c`

### ✅ ALLOWED — Adding New MQTT Subscriptions
You can subscribe to additional topics by calling:
```c
GSM_MQTT_SubscribeTopic("devices/MY_DEVICE/my_new_topic");
```
Do this AFTER `AWS_Init()` has returned successfully. Add it in `main.c` or in your own module.

### ✅ ALLOWED — Changing Linker Script for RAM/Flash Layout
You may adjust RAM sections, add new memory regions, etc. **BUT**:
- **Do NOT** place any code or data at `0x08040000` (Sector 6) — this is reserved for AWS credential storage
- **Do NOT** reduce the flash region below Sector 6

### ⛔ FORBIDDEN — Modifying AWS Connection Behavior
- Do NOT change the `AWS_Init()` function
- Do NOT change the `GSM_MQTT_Init()` function
- Do NOT change the MQTT connect sequence in `connectMQTT()`
- Do NOT change the SSL/TLS configuration AT commands
- Do NOT change the `AT+CCERTDOWN`, `AT+CSSLCFG`, `AT+CMQTTACCQ`, `AT+CMQTTSSLCFG`, or `AT+CMQTTCONNECT` command sequences
- Do NOT change the `AWS_IncomingCallback()` function
- Do NOT call `AWS_CertStorage_Erase()` anywhere — this will force re-provisioning
- Do NOT add `AWS_CertStorage_Erase()` to boot sequences
- Do NOT change the `fullReconnect()` function in `gsm_mqtt.c`

### ⛔ FORBIDDEN — Touching Identity/Provisioning
- Do NOT change `DEVICE_ID` format (must be `TX-XX` or `RX-XX` where XX is 01-10)
- Do NOT change the provisioning payload JSON structure
- Do NOT change `AWS_RegisterDevice()` JSON structure
- Do NOT change `InitIdentity()` topic construction patterns

---

## 8. DEVICE ID NAMING CONVENTION

The Receiver's `AWS_IncomingCallback()` parses incoming device IDs with this exact logic:
```
Format: "TX-XX" where XX is a two-digit number 01-10
```
- The callback checks `strncmp(id_str, "TX-", 3)` and validates that characters at index 3 and 4 are digits
- The parsed device number must be 1-10 (maps to Pairing Slots)
- Transmitter IDs outside this pattern are silently ignored

**If you add a new transmitter device**, it MUST follow the `TX-XX` format (e.g., `TX-04`, `TX-05`).
**Receiver device IDs** follow `RX-XX` format.

---

## 9. KNOWN CRITICAL BUGS & GOTCHAS — DO NOT RE-INTRODUCE

### 9.1 Do NOT Erase Certificates on Every Boot
A previous bug called `AWS_CertStorage_Erase()` at the top of `AWS_Init()`. This forced Fleet Provisioning on every power cycle, which AWS IoT rejects after the first time (the Thing already exists). The fix was to remove the unconditional erase and only erase when the broker actively rejects a stored certificate.

**If you see `AWS_CertStorage_Erase()` being called unconditionally at boot → THIS IS A BUG. Remove it.**

### 9.2 Do NOT Block the Main Loop Indefinitely
The Transmitter's main loop must keep running sensor reads even when AWS is disconnected. The current implementation uses non-blocking retry:
```c
if (!aws_inited) {
    if (HAL_GetTick() - lastAwsRetryTick >= 5000U) {
        lastAwsRetryTick = HAL_GetTick();
        aws_inited = AWS_Init(&huart2, "airtelgprs.com");
    }
}
```
Do NOT replace this with a blocking `while(!AWS_Init(...))` pattern.

### 9.3 UART Handle Conflict
- **USART2** is ALWAYS the A7670C modem UART on both TX and RX units. Do NOT reassign it.
- On the Receiver, **USART1** is the DWIN HMI display. Do NOT reassign it.

---

## 10. FLASH MEMORY MAP

```
STM32F411CEU6 Flash: 512 KB total

0x08000000 ┌──────────────────────┐
           │  Sector 0 (16 KB)    │  Application code
0x08004000 ├──────────────────────┤
           │  Sector 1 (16 KB)    │  Application code
0x08008000 ├──────────────────────┤
           │  Sector 2 (16 KB)    │  Application code
0x0800C000 ├──────────────────────┤
           │  Sector 3 (16 KB)    │  Application code
0x08010000 ├──────────────────────┤
           │  Sector 4 (64 KB)    │  Application code
0x08020000 ├──────────────────────┤
           │  Sector 5 (128 KB)   │  Application code
0x08040000 ├──────────────────────┤
           │  Sector 6 (128 KB)   │  ⛔ AWS CREDENTIALS STORAGE ⛔
           │                      │  DO NOT USE FOR ANYTHING ELSE
0x08060000 ├──────────────────────┤
           │  Sector 7 (128 KB)   │  Available (unused)
0x08080000 └──────────────────────┘
```

---

## 11. SUMMARY DECISION MATRIX

| Action | Allowed? | Notes |
|---|---|---|
| Add new sensor driver files | ✅ YES | Add .c/.h in Core/Src and Core/Inc |
| Add new CubeMX peripherals | ✅ YES | GPIO, UART, SPI, I2C, ADC, TIM |
| Change `device_config.h` identity fields | ✅ YES | DEVICE_ID, SERIAL, NAME, VERSION, etc. |
| Change `device_config.h` timeout values | ✅ YES | All `TIMEOUT_*` and `*_INTERVAL_MS` defines |
| Change `device_config.h` APN | ✅ YES | For different SIM provider |
| Add new MQTT publish calls using existing API | ✅ YES | Use `GSM_MQTT_PublishTopic()` |
| Add new MQTT subscriptions | ✅ YES | Use `GSM_MQTT_SubscribeTopic()` after AWS_Init |
| Modify screen_sm.c / dwin_hmi.c / buzzer.c | ✅ YES | UI/UX changes are safe |
| Modify battery_soc.c / charger_detect.c | ✅ YES | Power management is safe |
| Modify main.c (add inits, add loop logic) | ✅ YES | Keep AWS_Init/Poll calls intact |
| Modify linker scripts (add RAM sections) | ⚠️ CAREFUL | Don't touch Sector 6 at 0x08040000 |
| Change AWS_BROKER_URL | ⛔ NO | AWS account endpoint |
| Change AWS_TEMPLATE_NAME | ⛔ NO | Fleet Provisioning template |
| Change MQTT_TOPIC_PREFIX | ⛔ NO | Topic routing |
| Modify aws_manager.c | ⛔ NO | AWS provisioning/connection |
| Modify aws_manager.h | ⛔ NO | AWS API signatures |
| Modify gsm_mqtt.c | ⛔ NO | MQTT/TLS driver |
| Modify gsm_mqtt.h | ⛔ NO | MQTT types and signatures |
| Change certificate/key PEM strings | ⛔ NO | AWS authentication |
| Call AWS_CertStorage_Erase() | ⛔ NO | Will brick provisioning |
| Change topic patterns (devices/{id}/...) | ⛔ NO | Backend dependency |
| Change JSON payload structure in telemetry/register | ⛔ NO | Backend dependency |
| Change DEVICE_ID format from TX-XX/RX-XX | ⛔ NO | Receiver parsing depends on it |

---

## 12. EMERGENCY RECOVERY

If a device has been bricked by accidental changes to AWS files:

1. **Reflash with known-good firmware** from the Git repository's last working commit
2. **If the stored certificate is corrupted**: The device will automatically re-provision using the claim certificate on next boot (as long as the claim cert is valid in AWS IoT Console)
3. **If the Thing needs to be deleted from AWS IoT**: Delete it from the AWS IoT Console → Things page, then power-cycle the device to trigger fresh provisioning
4. **If the claim certificate has been revoked**: A new claim certificate must be generated in AWS IoT Console and embedded in `aws_manager.c` by the firmware team (NOT the hardware team)

---

> [!IMPORTANT]
> **This prompt is the complete reference.** If you are unsure whether a change is safe, assume it is NOT safe and ask the firmware team first. The cost of breaking AWS connectivity on deployed devices is far higher than the cost of asking.
