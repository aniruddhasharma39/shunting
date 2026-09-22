# SafeShunt Database Setup & Testing Guide

## 1. Immediate Login Credentials (Active Now)

The requested credentials have been created and enabled on the active database:

| Employee ID | Plaintext Password | Designation / Role | Assigned Yards |
| :--- | :--- | :--- | :--- |
| **`YD-1010`** | `yard123` | **Yard Administrator** (`yard_admin`) | North Yard, South Yard |
| **`AN-1010`** | `admin123` | **Super Administrator** (`super_admin`) | All Yards (System-wide) |

> **Verification:** You can now enter either `YD-1010` / `yard123` or `AN-1010` / `admin123` on the login screen of the Flutter app, and you will immediately be logged in.

---

## 2. Setting Up a New Database

If you want a fresh, isolated database for development and testing according to the schema, you have two simple options:

### Option A: Create a New Database on AWS RDS (Recommended)

Since the backend is already configured to talk to AWS RDS PostgreSQL (`safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com`), you can spin up a new database on the same RDS cluster in seconds without installing anything locally:

1. Open a terminal in `backend/`.
2. Run the automated setup script with your new database name (e.g., `safeshunt_dev`):
   ```bash
   node setup_database.js safeshunt_dev
   ```
   *This automatically connects to RDS, executes `CREATE DATABASE safeshunt_dev`, applies [complete_schema.sql](file:///c:/Users/PC/Desktop/Internship/shunting/backend/complete_schema.sql), and seeds all users, yards, lines, devices, and sessions.*

3. Update `backend/.env`:
   ```env
   DB_NAME=safeshunt_dev
   ```

4. Restart your backend server (`npm start` or `npm run dev`).

---

### Option B: Run a Local PostgreSQL Database (Docker or Local Postgres)

If you prefer to work completely offline:

1. **Start PostgreSQL via Docker**:
   ```bash
   docker run --name safeshunt-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=safeshunt_db -p 5432:5432 -d postgres:15
   ```

2. **Update `backend/.env` for Local**:
   ```env
   PORT=5000
   DB_USER=postgres
   DB_PASSWORD=postgres
   DB_HOST=localhost
   DB_NAME=safeshunt_db
   DB_PORT=5432
   DB_SSL=false
   JWT_SECRET=super_secret_jwt_key_for_safeshunt_app
   ```

3. **Initialize Schema & Seed Data**:
   ```bash
   npm run db:setup
   ```

---

## 3. Database Schema Overview

The complete database schema is organized into 16 relational entities in [complete_schema.sql](file:///c:/Users/PC/Desktop/Internship/shunting/backend/complete_schema.sql):

1. **`users`**: Authentication, roles (`super_admin`, `yard_admin`, `maintenance_user`, `viewer`), active status.
2. **`yards`**: Yard code, yard name, station, division, zone, status.
3. **`user_yard_assignments`**: Maps yard administrators to specific yards.
4. **`yard_lines`**: Pit lines, stabling lines, washing lines with approach direction and warning/slow/stop limits.
5. **`devices`**: Dead-End Units (DE), Loco Units (LD), Portable Devices (PD), Coupling Devices (CD).
6. **`device_sim_details`**: SIM operator, ICCID, recharge validity.
7. **`device_line_assignments`**: Tracks DE unit installed at a line's buffer/dead-end.
8. **`device_issue_returns`**: Tracks portable LD/PD issuance to loco pilots/shunters.
9. **`device_heartbeats`**: Heartbeat logs for online status, battery, RF, GSM.
10. **`device_health_status`**: Aggregated health metrics.
11. **`shunting_sessions`**: Active and completed LD-DE shunting operations.
12. **`session_events`**: Live distance, speed, and zone alerts during shunting.
13. **`alerts`**: Operational, device, and administrative alerts.
14. **`maintenance_records`**: Scheduled maintenance, parts replaced, costs.
15. **`audit_logs`**: System audit trail of logins, creates, updates.
16. **`report_history`**: Generated and downloaded reports.
