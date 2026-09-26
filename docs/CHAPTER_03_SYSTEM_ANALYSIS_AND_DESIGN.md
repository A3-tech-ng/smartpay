# CHAPTER 3: SYSTEM ANALYSIS & DESIGN METHODOLOGY

---

## 3.1 SOFTWARE DEVELOPMENT LIFE CYCLE (SDLC): AGILE METHODOLOGY

The development of the SmartPay mobile wallet application adopted the **Agile Software Development Methodology**, specifically leveraging the iterative Scrum framework. Agile was selected due to its flexibility in accommodating continuous feedback, incremental component construction, and parallel development of frontend UI screens, backend Supabase schema, and local hardware biometric integration.

```
+-------------------------------------------------------------------------+
|                  AGILE SDLC ITERATIVE DEVELOPMENT CYCLES                |
+-------------------------------------------------------------------------+
|  [Sprint 1: Architecture & Requirements]                                |
|  - Requirement Gathering, Wireframing, Supabase PostgreSQL Setup        |
|                                                                         |
|  [Sprint 2: Authentication & Biometrics]                                |
|  - local_auth Integration, Phone Normalization, Dual-Factor Gatekeeper |
|                                                                         |
|  [Sprint 3: Financial Ledger & Core Modules]                             |
|  - P2P Transfers, Safebox Vault, Micro-Loan Engine Implementation       |
|                                                                         |
|  [Sprint 4: Retail & Utility Hub]                                       |
|  - QR Code Scanner/Generator, Utility Payment Integration               |
|                                                                         |
|  [Sprint 5: Security Audit & Admin Control]                             |
|  - Audit Log Engine (`biometric_login_logs`), Admin Security Portal     |
|                                                                         |
|  [Sprint 6: Testing, Benchmarking & Defense Prep]                        |
|  - Unit Tests, Latency Benchmarking, UAT, Monograph Documentation       |
+-------------------------------------------------------------------------+
```

### 3.1.1 Sprint Breakdown Summary
- **Sprint 1 (Weeks 1–2):** Requirement analysis, client-server architectural design, database schema modeling in Supabase, establishing Flutter project structure.
- **Sprint 2 (Weeks 3–4):** Implementing `BiometricService` (`local_auth`), phone number normalization, login/register UI workflow, cross-device PIN verification.
- **Sprint 3 (Weeks 5–6):** Developing core financial transaction ledger, P2P fund transfer logic, Safebox savings lock/unlock mechanism, and micro-loan disbursement engine.
- **Sprint 4 (Weeks 7–8):** Integrating `mobile_scanner` and `qr_flutter` for dynamic merchant QR scan-to-pay checkout, building the multi-utility bill payment hub.
- **Sprint 5 (Weeks 9–10):** Implementing cloud security audit logging (`biometric_login_logs`), constructing Administrator security control dashboard, dynamic theme switching (Dark/Light mode).
- **Sprint 6 (Weeks 11–12):** System integration testing, performance latency benchmarking, hardware compatibility matrix verification, and compiling final project board documentation.

---

## 3.2 REQUIREMENTS ANALYSIS & SPECIFICATIONS

### 3.2.1 Functional Requirements
Functional requirements define the core operational capabilities that SmartPay must execute:

- **FR-01 (Account Registration):** The system shall allow new users to register with their full name, valid phone number, 4-digit PIN, unique account number, and optional profile avatar URL.
- **FR-02 (Cross-Device Account Discovery):** The system shall enable existing users to identify their cloud profile on any device by entering their phone number, automatically resolving international format variations.
- **FR-03 (Hardware Biometric Verification):** The system shall query host mobile hardware for fingerprint sensors and execute local biometric authentication before granting access to sensitive modules.
- **FR-04 (Dual-Factor PIN Validation):** The system shall validate user-entered PINs against stored cloud profile hashes to complete authentication.
- **FR-05 (Peer-to-Peer Transfer Engine):** The system shall process instantaneous fund transfers between SmartPay account numbers, validating sender balance sufficiency and updating sender/recipient profiles atomically.
- **FR-06 (Safebox Savings Vault):** The system shall allow users to deposit liquid funds into a locked Safebox vault balance and withdraw funds back to their main balance.
- **FR-07 (Automated Micro-Loan Engine):** The system shall disburse short-term credit directly into the user's main wallet balance while recording an equivalent liability in `loan_balance`.
- **FR-08 (Utility Bill Payment Hub):** The system shall support payment processing for Airtime, Data, Electricity, Cable TV, and Sports Betting subscriptions, debiting main wallet balances and emitting transaction receipts.
- **FR-09 (QR Code Scan-to-Pay):** The system shall generate personal account QR codes and use live camera scanning (`mobile_scanner`) to read recipient details for instant checkout.
- **FR-10 (Forensic Audit Logging):** The system shall record every login attempt (successful or failed) in the cloud table `biometric_login_logs`, capturing user ID, auth method, success flag, and target device platform metadata.
- **FR-11 (Administrator Control Portal):** The system shall provide an administrative control view allowing privileged admins to inspect user balances, platform activity, and audit logs.

### 3.2.2 Non-Functional Requirements
Non-functional requirements define the quality attributes and constraints of the system:

- **NFR-01 (Performance Latency):** Local biometric authentication and PIN validation must complete within 500 milliseconds under standard 4G/Wi-Fi conditions.
- **NFR-02 (UI Responsiveness):** The mobile application graphical user interface (GUI) must render cleanly at 60 Frames Per Second (FPS) without UI stuttering or jank.
- **NFR-03 (Security & Isolation):** Raw biometric image data must never leave local hardware key stores or be transmitted to external servers.
- **NFR-04 (Data Integrity & ACID Safety):** Database updates during financial transfers must satisfy strict ACID properties, preventing partial debits or balance corruption.
- **NFR-05 (Availability & Fault Tolerance):** If local biometric hardware is unavailable or fails, the application must provide a graceful fallback to secure PIN verification.

---

## 3.3 HIGH-LEVEL SYSTEM ARCHITECTURE

SmartPay utilizes a **Client-Server Architecture** decoupled into three primary layers: Mobile Client Layer, Platform Hardware Security Layer, and Cloud Infrastructure Layer.

```
+-------------------------------------------------------------------------+
|                        SMARTPAY SYSTEM ARCHITECTURE                     |
+-------------------------------------------------------------------------+

  [ LAYER 1: FLUTTER MOBILE CLIENT ]
  +---------------------------------------------------------------------+
  | - Presentation Layer (Material 3 UI, Google Fonts, Lucide Icons)    |
  | - Provider State Management (ThemeProvider, App State)               |
  | - Services: BiometricService, SupabaseService                       |
  +---------------------------------------------------------------------+
        |                                           |
        | Platform Channels                         | REST / WebSockets
        v                                           v
  [ LAYER 2: HARDWARE SECURITY ]            [ LAYER 3: CLOUD INFRASTRUCTURE ]
  +-----------------------------------+     +-----------------------------------+
  | Android Keystore / TrustZone      |     | Supabase PostgreSQL Database      |
  | iOS Secure Enclave Coprocessor    |     | - Profiles Table                  |
  | local_auth Biometric Hardware API |     | - Transactions Table              |
  +-----------------------------------+     | - Biometric Login Logs Table      |
                                            | - Admin Settings Table            |
                                            +-----------------------------------+
```

---

## 3.4 DATA FLOW DIAGRAMS (DFD)

Data Flow Diagrams illustrate how information enters, transforms, and persists within SmartPay.

### 3.4.1 Level 0 Context DFD
The Level 0 Context Diagram depicts the entire SmartPay system as a single central process interacting with external entities (Mobile User, System Administrator, Biometric Hardware, Supabase Cloud).

```
                 +-----------------------+
                 |  Mobile User / Client |
                 +-----------------------+
                   |                 ^
  Credentials /    |                 | Balance Updates /
  Biometric Scan   v                 | Digital Receipts
         +----------------------------------+
         |  0.0 SMARTPAY MOBILE SYSTEM      |
         +----------------------------------+
           |       ^              ^      |
  Audit    |       | Raw Biometric|      | Query /
  Queries  v       | Results      |      v Updates
+------------------+  +--------------------+  +----------------------+
| System Admin     |  | Biometric Hardware |  | Supabase Cloud DB    |
+------------------+  +--------------------+  +----------------------+
```

### 3.4.2 Level 1 System DFD
Level 1 decomposes the main system into primary operational processes:

```
+-------------------------------------------------------------------------+
|                     LEVEL 1 DATA FLOW DIAGRAM (DFD)                     |
+-------------------------------------------------------------------------+

[User Input] ---> (1.0 Phone Discovery & Auth) <---> [Store D1: profiles]
                         |
                         v (Verified Session)
                  (2.0 Financial Ledger Engine) <---> [Store D2: transactions]
                     |           |          |
                     v           v          v
              (2.1 P2P)   (2.2 Safebox)  (2.3 Loans)
                         |
                         v
             (3.0 Security Audit Engine) <---> [Store D3: biometric_login_logs]
                         |
                         v
             (4.0 Admin Control Dashboard) <---> [Store D4: admin_settings]
```

---

## 3.5 UNIFIED MODELING LANGUAGE (UML) MODELING

### 3.5.1 Use Case Diagram
The Use Case Diagram defines the interactions between human actors (**Mobile User**, **System Administrator**) and local hardware (**Fingerprint Sensor**).

```
+-------------------------------------------------------------------------+
|                       SMARTPAY USE CASE DIAGRAM                         |
+-------------------------------------------------------------------------+

    MOBILE USER                                  SYSTEM ADMINISTRATOR
  +--------------+                              +--------------------+
  |              |                              |                    |
  |  (User)      |                              |  (Admin)           |
  +--------------+                              +--------------------+
         |                                                 |
         +---> (UC-01: Register Cloud Account)             |
         +---> (UC-02: Authenticate via Fingerprint & PIN) |
         +---> (UC-03: View Balance & Hide/Show Toggle)    |
         +---> (UC-04: Execute P2P Fund Transfer)          |
         +---> (UC-05: Deposit / Withdraw Safebox Vault)   |
         +---> (UC-06: Request & Repay Micro-Loan)         |
         +---> (UC-07: Pay Utility Bills)                 |
         +---> (UC-08: Scan & Generate QR Checkout)        |
         +---> (UC-09: Toggle Dark / Light Theme)          |
                                                           |
                                                           +---> (UC-10: Admin Login)
                                                           +---> (UC-11: Inspect System Balances)
                                                           +---> (UC-12: View Biometric Audit Logs)

  BIOMETRIC FINGERPRINT SENSOR
  +----------------------------+
  | (Hardware)                 |---> (UC-02: Authenticate via Fingerprint)
  +----------------------------+
```

### 3.5.2 Sequence Diagrams

#### Sequence Diagram 1: Dual-Factor Authentication Flow
```
User             Flutter UI            BiometricService        local_auth         Supabase DB
 |                   |                        |                    |                   |
 |-- 1. Enter Phone ->|                        |                    |                   |
 |                   |-- 2. Query Profile --->|------------------->|------------------>|
 |                   |<- 3. Profile Found ----|<-------------------|-------------------|
 |                   |                        |                    |                   |
 |-- 4. Press Auth ->|                        |                    |                   |
 |                   |-- 5. Trigger Scan ---->|-- 6. Check Auth -->|                   |
 |                   |                        |<- 7. Return Result-|<-- Sensors Scan   |
 |                   |<-- 8. Fingerprint OK --|                    |                   |
 |                   |                        |                    |                   |
 |-- 9. Enter PIN -->|                        |                    |                   |
 |                   |-- 10. Validate PIN -------------------------------------------->|
 |                   |<- 11. PIN Match OK ---------------------------------------------|
 |                   |                        |                    |                   |
 |                   |-- 12. Log Audit Attempt --------------------------------------->|
 |                   |    (Method: Fingerprint, Success: True)                         |
 |                   |                                                                 |
 |<-- 13. Grant Access Dashboard ------------------------------------------------------+
```

#### Sequence Diagram 2: Peer-to-Peer Transfer Execution
```
Sender Client          Supabase Cloud DB          Recipient Client
     |                         |                         |
     |-- 1. Execute Transfer ->|                         |
     |   (Sender ID, Recipient Account, Amount)          |
     |                         |-- 2. Validate Balance ->|
     |                         |-- 3. Atomic Transaction:|
     |                         |   - Debit Sender        |
     |                         |   - Credit Recipient    |
     |                         |   - Insert Transaction  |
     |                         |     Ledger Entry        |
     |                         |                         |
     |<- 4. Return Receipt ----|                         |
     |   (Status: Successful)  |-- 5. Broadcast Sync --->|
     |                         |   (Realtime WS Update)  |
```

---

## 3.6 DATABASE MODELING & ENTITY-RELATIONSHIP DIAGRAM (ERD)

The database design enforces relational integrity across account profiles, ledger transactions, security audit logs, and administrative settings.

```
+-------------------------------------------------------------------------+
|                ENTITY-RELATIONSHIP DIAGRAM (ERD)                        |
+-------------------------------------------------------------------------+

   +------------------------+                  +------------------------+
   |        PROFILES        |                  |      TRANSACTIONS      |
   +------------------------+                  +------------------------+
   | PK  user_id (TEXT)     |<----+            | PK  id (UUID)          |
   |     full_name (TEXT)   |     |            | FK  user_id (TEXT) ----+
   | UK  phone_number (TEXT)|     +----------->|     title (TEXT)       |
   |     pin (TEXT)         |     (1 to Many)  |     subtitle (TEXT)    |
   | UK  account_no (TEXT)  |                  |     amount (TEXT)      |
   |     balance (NUMERIC)  |                  |     is_debit (BOOLEAN) |
   |     safebox (NUMERIC)  |                  |     status (TEXT)      |
   |     loan (NUMERIC)     |                  |     created_at (TS)    |
   |     kyc_tier (TEXT)    |                  +------------------------+
   |     created_at (TS)    |
   +------------------------+                  +------------------------+
              ^                                |  BIOMETRIC_LOGIN_LOGS  |
              |                                +------------------------+
              |                                | PK  id (UUID)          |
              +--------------------------------| FK  user_id (TEXT)     |
                         (1 to Many)           |     auth_method (TEXT) |
                                               |     is_successful (BOOL|
                                               |     device_info (TEXT) |
                                               |     created_at (TS)    |
                                               +------------------------+

   +------------------------+
   |     ADMIN_SETTINGS     |
   +------------------------+
   | PK  id (INT = 1)       |
   |     username (TEXT)    |
   |     password (TEXT)    |
   |     updated_at (TS)    |
   +------------------------+
```

---

## 3.7 DATABASE SCHEMA DESIGN & DATA DICTIONARIES

### 3.7.1 Data Dictionary: `profiles` Table
Stores user cloud accounts, authentication PINs, wallet balances, and KYC metadata.

**Table 3.3: Data Dictionary for `profiles` Table**
| Column Name | Data Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `user_id` | `TEXT` | `PRIMARY KEY` | Unique cloud user identifier (UUID string). |
| `full_name` | `TEXT` | `NOT NULL` | Registered customer full legal name. |
| `phone_number` | `TEXT` | `UNIQUE, NOT NULL` | Primary phone contact and cloud discovery key. |
| `pin` | `TEXT` | `NOT NULL` | Encrypted 4-digit security PIN. |
| `account_no` | `TEXT` | `UNIQUE, NOT NULL` | Generated 10-digit wallet account number. |
| `profile_picture_url` | `TEXT` | `NULLABLE` | DiceBear avatar URL or image path. |
| `kyc_tier` | `TEXT` | `DEFAULT 'Tier 3 Verified'` | Customer identity verification level. |
| `balance` | `NUMERIC(15,2)`| `DEFAULT 10000.00` | Main liquid spending balance. |
| `safebox_balance` | `NUMERIC(15,2)`| `DEFAULT 0.00` | Locked Safebox savings vault balance. |
| `loan_balance` | `NUMERIC(15,2)`| `DEFAULT 0.00` | Outstanding micro-credit liability balance. |
| `created_at` | `TIMESTAMPTZ` | `DEFAULT now()` | Account creation UTC timestamp. |
| `updated_at` | `TIMESTAMPTZ` | `DEFAULT now()` | Last profile mutation UTC timestamp. |

### 3.7.2 Data Dictionary: `transactions` Table
Stores all wallet debit and credit ledger entries.

**Table 3.4: Data Dictionary for `transactions` Table**
| Column Name | Data Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | `UUID` | `PRIMARY KEY, DEFAULT gen_random_uuid()` | Unique transaction entry ID. |
| `user_id` | `TEXT` | `FOREIGN KEY -> profiles(user_id)` | Account owner user ID. |
| `title` | `TEXT` | `NOT NULL` | Primary description (e.g., "Transfer to John"). |
| `subtitle` | `TEXT` | `NOT NULL` | Transaction details (e.g., "SmartPay • 9023456781"). |
| `amount` | `TEXT` | `NOT NULL` | Formatted string (e.g., "- ₦5,000.00"). |
| `is_debit` | `BOOLEAN` | `NOT NULL` | `true` for outflow (debit), `false` for inflow (credit). |
| `status` | `TEXT` | `DEFAULT 'Successful'` | Completion state ("Successful", "Failed"). |
| `created_at` | `TIMESTAMPTZ` | `DEFAULT now()` | ISO-8601 execution timestamp. |

### 3.7.3 Data Dictionary: `biometric_login_logs` Table
Stores forensic security audit logs for all authentication events.

**Table 3.5: Data Dictionary for `biometric_login_logs` Table**
| Column Name | Data Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | `UUID` | `PRIMARY KEY, DEFAULT gen_random_uuid()` | Unique audit log entry ID. |
| `user_id` | `TEXT` | `FOREIGN KEY -> profiles(user_id)` | Target user account ID. |
| `auth_method` | `TEXT` | `NOT NULL` | Type of authentication ("fingerprint" or "pin"). |
| `is_successful` | `BOOLEAN` | `NOT NULL` | `true` if passed, `false` if rejected. |
| `device_info` | `TEXT` | `NULLABLE` | Operating system platform metadata. |
| `created_at` | `TIMESTAMPTZ` | `DEFAULT now()` | UTC timestamp of authentication attempt. |

### 3.7.4 Data Dictionary: `admin_settings` Table
Stores administrative credentials and system settings.

**Table 3.6: Data Dictionary for `admin_settings` Table**
| Column Name | Data Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | `INT` | `PRIMARY KEY, CHECK (id = 1)` | Enforces single-row configuration constraint. |
| `username` | `TEXT` | `NOT NULL, DEFAULT 'admin'` | Administrator login username. |
| `password` | `TEXT` | `NOT NULL, DEFAULT 'admin_password_2026'` | Administrator access credential. |
| `updated_at` | `TIMESTAMPTZ` | `DEFAULT now()` | Last configuration update timestamp. |

---

## 3.8 UI/UX NAVIGATION ARCHITECTURE

SmartPay's graphical interface employs a modern Glassmorphism aesthetics model built with Flutter Material 3, incorporating dark indigo cards, vibrant accent gradients, Google Fonts (`Outfit` and `Inter`), and Lucide icons. 

The screen navigation hierarchy comprises:
- `SplashScreen`: App initialization & Supabase check.
- `LoginScreen`: Cross-device phone discovery & PIN login.
- `RegisterScreen`: New profile onboarding & account creation.
- `FaceScannerScreen` / Biometric Gatekeeper: Hardware fingerprint verification prompt.
- `HomeScreen`: Financial command dashboard, P2P transfers, Safebox vault, Loans, Utility hub, QR Scan-to-pay.
- `AdminLoginScreen` & `AdminDashboardScreen`: Administrator monitoring portal and audit trail inspector.
