"""
AWS LAMBDA FUNCTION: IoT Telemetry to PostgreSQL RDS Ingestion Handler
Runtime: Python 3.10 / 3.11 / 3.12

AWS IoT Rule SQL:
  SELECT *, topic() as topic, timestamp() as msg_timestamp FROM 'devices/+/telemetry'

Environment Variables in AWS Lambda:
  DB_HOST = safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com
  DB_NAME = safeshunt_db
  DB_USER = postgres
  DB_PASSWORD = pisolve123
  DB_PORT = 5432
"""

import os
import json
import psycopg2
from psycopg2.extras import Json

DB_HOST = os.environ.get("DB_HOST", "safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com")
DB_NAME = os.environ.get("DB_NAME", "safeshunt_db")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "pisolve123")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))

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
    diagnostics = event.get("diagnostics", {})
    readings = event.get("readings", {})
    
    battery = diagnostics.get("battery_pct") or event.get("battery_level") or event.get("battery")
    signal = diagnostics.get("gsm_rssi") or event.get("signal_rssi") or event.get("gsm_rssi") or event.get("signal")
    lat = event.get("latitude") or event.get("lat")
    lng = event.get("longitude") or event.get("lng")
    distance_cm = readings.get("distance_cm") or event.get("distance_cm")
    speed_kmh = event.get("speed_kmh") or event.get("speed")
    product_type = event.get("productType") or event.get("product_type") or "RECEIVER"

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

        # 3. Insert into legacy telemetry_data
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
