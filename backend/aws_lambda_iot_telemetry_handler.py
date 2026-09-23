"""
AWS LAMBDA FUNCTION: IoT Telemetry to PostgreSQL RDS Ingestion Handler
Runtime: Python 3.10 / 3.11 / 3.12

AWS IoT Rule SQL:
  SELECT *, topic() as topic, timestamp() as msg_timestamp FROM 'devices/+/telemetry'
  (or SELECT * FROM 'devices/#' to capture status & telemetry)

Environment Variables in AWS Lambda:
  DB_HOST = safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com
  DB_NAME = safeshunt_db
  DB_USER = postgres
  DB_PASSWORD = pisolve123
  DB_PORT = 5432
"""

import os
import json
import time
import psycopg2
from psycopg2.extras import Json

DB_HOST = os.environ.get("DB_HOST", "safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com")
DB_NAME = os.environ.get("DB_NAME", "safeshunt_db")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "pisolve123")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))

def derive_paired_device(device_id, payload):
    # Check explicit field first
    if payload.get("paired_tx_id"):
        return payload["paired_tx_id"]
    if payload.get("paired_rx_id"):
        return payload["paired_rx_id"]
    if payload.get("paired_device"):
        return payload["paired_device"]

    # Match numeric suffix (e.g. TX-03 <-> RX-03, TX-01 <-> RX-01)
    if device_id.startswith("TX-") or device_id.startswith("DE-"):
        num = device_id.split("-")[1]
        return f"RX-{num}"
    elif device_id.startswith("RX-") or device_id.startswith("LD-"):
        num = device_id.split("-")[1]
        return f"TX-{num}"
    elif device_id.startswith("TX"):
        return device_id.replace("TX", "RX")
    elif device_id.startswith("RX"):
        return device_id.replace("RX", "TX")
    return "TX-01" if device_id.startswith("RX") else "RX-01"

def lambda_handler(event, context):
    print("Incoming AWS IoT Telemetry Event:", json.dumps(event, default=str))

    # Extract device ID
    device_id = event.get("deviceId") or event.get("device_id") or event.get("deviceCode") or event.get("SerialNumber")
    topic = event.get("topic", f"devices/{device_id}/telemetry" if device_id else "devices/unknown/telemetry")

    if not device_id and "topic" in event:
        parts = event["topic"].split("/")
        if len(parts) >= 2 and parts[0] == "devices":
            device_id = parts[1]

    if not device_id:
        print("ERROR: No deviceId found in event or topic.")
        return {"statusCode": 400, "body": "Missing deviceId"}

    # Extract metrics
    diagnostics = event.get("diagnostics", {}) if isinstance(event.get("diagnostics"), dict) else {}
    readings = event.get("readings", {}) if isinstance(event.get("readings"), dict) else {}
    
    battery = diagnostics.get("battery_pct") if diagnostics.get("battery_pct") is not None else (event.get("battery_level") or event.get("battery"))
    signal = diagnostics.get("gsm_rssi") if diagnostics.get("gsm_rssi") is not None else (event.get("signal_rssi") or event.get("gsm_rssi") or event.get("signal"))
    lat = event.get("latitude") or event.get("lat")
    lng = event.get("longitude") or event.get("lng")
    
    # Distance in cm
    distance_cm = readings.get("distance_cm")
    if distance_cm is None:
        distance_cm = event.get("distance_cm")
    if distance_cm is None and event.get("distance") is not None:
        try:
            distance_cm = round(float(event["distance"]) * 100)
        except Exception:
            distance_cm = None

    speed_kmh = event.get("speed_kmh") or event.get("speed")
    product_type = event.get("productType") or event.get("product_type") or ("TRANSMITTER" if device_id.startswith("TX") else "RECEIVER")

    conn = None
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            port=DB_PORT,
            sslmode="require"
        )
        cur = conn.cursor()

        # 1. Insert into device_telemetry
        insert_telemetry_sql = """
            INSERT INTO device_telemetry (
                device_id, topic, payload, battery_level, signal_rssi, latitude, longitude, distance_cm, speed_kmh, recorded_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
            RETURNING id;
        """
        cur.execute(insert_telemetry_sql, (
            device_id,
            topic,
            Json(event),
            battery,
            signal,
            lat,
            lng,
            distance_cm,
            speed_kmh
        ))
        telemetry_id = cur.fetchone()[0]
        print(f"Saved to device_telemetry with ID: {telemetry_id}")

        # 2. Upsert into device_registry
        upsert_registry_sql = """
            INSERT INTO device_registry (
                device_id, device_name, serial_number, product_type, hardware_version, firmware_version, health_status, last_reading_timestamp, updated_at
            ) VALUES (
                %s, %s, %s, %s, '1.0', '1.0.0', 'ONLINE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            )
            ON CONFLICT (device_id) DO UPDATE SET
                health_status = 'ONLINE',
                last_reading_timestamp = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP;
        """
        cur.execute(upsert_registry_sql, (device_id, device_id, device_id, product_type))

        # 3. Handle Pairing and Live Session State Machine
        event_type = event.get("event")
        status = event.get("status")
        paired_device = derive_paired_device(device_id, event)
        rx_id = device_id if (device_id.startswith("RX") or device_id.startswith("LD")) else paired_device
        tx_id = device_id if (device_id.startswith("TX") or device_id.startswith("DE")) else paired_device

        # If explicit /status topic or pair events
        if "/status" in topic or event_type in ["PAIR_START", "PAIR_END", "UNEXPECTED_DISCONNECT"]:
            if event_type == "PAIR_START" or status == "PAIRED":
                cur.execute(
                    "SELECT id FROM shunting_sessions WHERE (rx_device_id = %s OR ld_code = %s) AND (status = 'LIVE' OR session_status = 'LIVE')",
                    (rx_id, rx_id)
                )
                existing = cur.fetchall()
                if not existing:
                    session_code = f"SES-{str(int(time.time()))[-6:]}-{rx_id}"
                    cur.execute("""
                        INSERT INTO shunting_sessions (
                            session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
                            session_start, start_time, session_status, status, distance_trajectory, created_at, updated_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, NOW(), NOW(), 'LIVE', 'LIVE', '[]'::jsonb, NOW(), NOW())
                    """, (session_code, session_code, rx_id, rx_id, tx_id, tx_id))
                    print(f"Started session: {rx_id} <--> {tx_id}")
            elif event_type == "PAIR_END" or status == "IDLE":
                final_val = event.get("final_distance_cm") or distance_cm or 0
                cur.execute("""
                    UPDATE shunting_sessions
                    SET 
                        session_end = NOW(),
                        end_time = NOW(),
                        session_status = 'COMPLETED',
                        status = 'COMPLETED',
                        final_distance_cm = %s,
                        final_placement_distance = %s / 100.0,
                        updated_at = NOW()
                    WHERE (rx_device_id = %s OR ld_code = %s OR tx_device_id = %s OR de_code = %s) 
                      AND (status = 'LIVE' OR session_status = 'LIVE')
                """, (final_val, final_val, rx_id, rx_id, tx_id, tx_id))
                print(f"Ended session for: {rx_id} / {tx_id}")
            elif event_type == "UNEXPECTED_DISCONNECT" or status == "OFFLINE":
                cur.execute("""
                    UPDATE shunting_sessions
                    SET 
                        session_end = NOW(),
                        end_time = NOW(),
                        session_status = 'TIMED_OUT',
                        status = 'TIMED_OUT',
                        manual_close_reason = 'Hardware Unexpected Disconnect / LWT',
                        updated_at = NOW()
                    WHERE (rx_device_id = %s OR ld_code = %s OR tx_device_id = %s OR de_code = %s)
                      AND (status = 'LIVE' OR session_status = 'LIVE')
                """, (rx_id, rx_id, tx_id, tx_id))
                print(f"Timed out session for: {rx_id} / {tx_id}")

        # 4. If distance reading is present, update trajectory or auto-create session
        if distance_cm is not None:
            point = json.dumps({
                "t": event.get("cloud_timestamp") or int(time.time() * 1000),
                "d_cm": distance_cm,
                "speed_kmh": speed_kmh or 0.0,
                "battery": battery,
                "signal": signal
            })

            cur.execute("""
                UPDATE shunting_sessions
                SET 
                    distance_trajectory = COALESCE(distance_trajectory, '[]'::jsonb) || %s::jsonb,
                    final_distance_cm = %s,
                    final_placement_distance = %s / 100.0,
                    minimum_distance = LEAST(COALESCE(minimum_distance, %s / 100.0), %s / 100.0),
                    updated_at = NOW()
                WHERE (tx_device_id = %s OR de_code = %s OR rx_device_id = %s OR ld_code = %s)
                  AND (status = 'LIVE' OR session_status = 'LIVE')
            """, (point, distance_cm, distance_cm, distance_cm, distance_cm, tx_id, tx_id, rx_id, rx_id))

            if cur.rowcount == 0:
                # Auto create live session for this pair
                session_code = f"SES-{str(int(time.time()))[-6:]}-{rx_id}"
                cur.execute("""
                    INSERT INTO shunting_sessions (
                        session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
                        session_start, start_time, session_status, status, final_distance_cm, final_placement_distance,
                        minimum_distance, distance_trajectory, created_at, updated_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, NOW(), NOW(), 'LIVE', 'LIVE', %s, %s / 100.0, %s / 100.0, %s::jsonb, NOW(), NOW())
                """, (session_code, session_code, rx_id, rx_id, tx_id, tx_id, distance_cm, distance_cm, distance_cm, json.dumps([json.loads(point)])))
                print(f"Auto-started live shunting session: {rx_id} <--> {tx_id}")

        # 5. Insert into legacy telemetry_data for backward compatibility
        try:
            cur.execute(
                "INSERT INTO telemetry_data (device_id, payload, recorded_at) VALUES (%s, %s, CURRENT_TIMESTAMP)",
                (device_id, Json(event))
            )
        except Exception:
            pass

        conn.commit()
        cur.close()
        return {"statusCode": 200, "body": json.dumps({"success": True, "id": telemetry_id})}
    except Exception as e:
        print("Database Error in Lambda:", str(e))
        if conn:
            conn.rollback()
        return {"statusCode": 500, "body": str(e)}
    finally:
        if conn:
            conn.close()
