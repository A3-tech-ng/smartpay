# CHAPTER 2: LITERATURE REVIEW & THEORETICAL FRAMEWORK

---

## 2.1 EVOLUTION OF DIGITAL FINANCIAL GATEKEEPING & MOBILE WALLETS

The transition from physical currency to digital payment mechanisms represents one of the most profound socio-technical shifts in modern economic history. Over the past three decades, retail financial infrastructure evolved through four distinct eras:

1. **Card-Based Magnetic Stripe Era (1980s–1990s):** Initial electronic retail payments relied on physical credit and debit cards storing static account numbers on magnetic stripes. These cards lacked cryptographic validation and were highly susceptible to physical cloning and skimmer devices.
2. **EMV Smart Card & Chip-and-PIN Era (2000s):** To counteract magnetic stripe cloning, Europay, Mastercard, and Visa (EMV) introduced smart cards embedded with microcontrollers capable of executing symmetric cryptographic challenge-response protocols. Authentication required inserting the physical card into a Point-of-Sale (POS) terminal and entering a 4-digit PIN.
3. **First-Generation Mobile Banking Era (2010s):** The advent of smartphones led to native mobile applications acting as web wrappers around bank servers. Authentication relied heavily on static usernames, passwords, and SMS-delivered One-Time Passwords (OTPs).
4. **Cloud-Native & Biometric Mobile Wallet Era (2020s–Present):** Modern financial systems combine native mobile application frameworks (Flutter, React Native) with hardware-backed biometric sensors and serverless cloud databases. These wallets function as consolidated financial hubs capable of instant settlement, digital wealth management, and hardware biometric gatekeeping.

Despite this technical progression, mobile payment security continues to contend with sophisticated threat vectors. As consumer financial management shifts decisively to mobile devices, security models must adapt to protect against physical theft, social engineering, credential reuse, and remote cloud compromise.

---

## 2.2 AUTHENTICATION PARADIGMS: KNOWLEDGE VS. OWNERSHIP VS. INHERENCE

Information security theory asserts that robust identity verification relies on evaluating parameters across three primary authentication factors:

$$\text{Authentication Factor Set} = \{ \mathcal{F}_{\text{Knowledge}}, \mathcal{F}_{\text{Possession}}, \mathcal{F}_{\text{Inherence}} \}$$

```
+-------------------------------------------------------------------------+
|                    AUTHENTICATION FACTOR TAXONOMY                       |
+-------------------------------------------------------------------------+
|  1. KNOWLEDGE FACTOR        | 2. POSSESSION FACTOR   | 3. INHERENCE     |
|     ("Something You Know")  |    ("Something You Have")|    ("Something   |
|                             |                        |     You Are")    |
|  - 4-Digit Numeric PIN      | - Mobile Handset IMEI  | - Capacitive     |
|  - Static Password          | - SIM Card / Phone No  |   Fingerprint    |
|  - Security Answers         | - Secure Enclave Key   | - Facial Geometry|
+-------------------------------------------------------------------------+
```

### 2.1.1 Knowledge-Based Authentication ($\mathcal{F}_{\text{Knowledge}}$)
Knowledge-based credentials (PINs, passwords) require the user to store a secret string in memory and reproduce it upon demand. While computationally trivial to implement and verify via cryptographic hashing algorithms (e.g., SHA-256, bcrypt, Argon2), knowledge factors possess major vulnerabilities:
- **Human Cognitive Limits:** Users frequently select low-entropy sequences (e.g., `1234`, `1111`) or recycle credentials across non-critical and financial applications.
- **Physical Observation:** Numeric PIN entry on touchscreens is vulnerable to shoulder surfing, thermal imaging of screen glass, and covert video recording.
- **Social Engineering:** Attackers can trick users into disclosing static credentials through phishing websites or spoofed phone calls.

### 2.1.2 Possession-Based Authentication ($\mathcal{F}_{\text{Possession}}$)
Possession factors require verifying ownership of a specific physical device or token (e.g., hardware security keys, mobile phone handsets registered to a specific IMEI or phone number). In mobile banking:
- **SMS OTP Vulnerability:** Relying on SMS as a possession token is flawed because cellular networks (SS7 protocol) are vulnerable to remote interception, and attackers frequently execute SIM-swapping attacks by tricking mobile network operators into transferring a victim's phone number to an attacker's SIM card.
- **Hardware Device Lock Constraints:** Standard device locking ties account access to a single hardware unit. If the unit is damaged or lost, the legitimate user is locked out until administrative intervention occurs.

### 2.1.3 Inherence-Based Authentication ($\mathcal{F}_{\text{Inherence}}$)
Inherence factors evaluate unique physiological characteristics of the individual (fingerprint ridge patterns, facial landmark geometry, iris structures). Biometrics offer distinct advantages over knowledge and possession factors:
- **Non-Transferability:** Biometric characteristics cannot be easily shared, forgotten, or misplaced.
- **High Entropy:** Fingerprint minutiae points (ridge endings, bifurcations, dots) yield unique feature templates with extremely low probability of identical matches between different individuals.
- **Zero Exposure During Entry:** Unlike PIN entry, scanning a fingerprint does not expose a reproducible secret sequence to visual observers.

### 2.1.4 Dual-Factor Authentication (2FA) Synthesis
SmartPay synthesizes knowledge ($\mathcal{F}_{\text{Knowledge}}$) and inherence ($\mathcal{F}_{\text{Inherence}}$) factors into a mandatory Dual-Factor Authentication gatekeeper:

$$\text{Decision}_{\text{Access}} = \text{Verify}_{\text{Fingerprint}}(\text{Hardware}) \bigwedge \text{Verify}_{\text{PIN}}(\text{Cloud PostgreSQL})$$

Access is granted if and only if both local hardware fingerprint verification and encrypted cloud PIN verification yield affirmative outputs.

---

## 2.3 LOCAL BIOMETRIC HARDWARE SECURITY MODULES & API FRAMEWORKS

Modern mobile Operating Systems (Android and iOS) enforce strict separation between application software execution environments and biometric template storage. Biometric raw image data is **never** accessible to third-party mobile applications or cloud servers.

```
+-------------------------------------------------------------------------+
|                  MOBILE HARDWARE BIOMETRIC ARCHITECTURE                |
+-------------------------------------------------------------------------+
|  FLUTTER APPLICATION LAYER                                               |
|  - calls local_auth plugin: _auth.authenticate(...)                      |
+-------------------------------------------------------------------------+
                                  |
                                  v Platform Channel
+-------------------------------------------------------------------------+
|  OPERATING SYSTEM FRAMEWORK (Android BiometricPrompt / iOS LocalAuth)   |
+-------------------------------------------------------------------------+
                                  |
                                  v Hardware Abstraction Layer (HAL)
+-------------------------------------------------------------------------+
|  SECURE HARDWARE ISOLATION ZONE                                         |
|  - Android Keystore / ARM TrustZone / iOS Secure Enclave               |
|  - Stores encrypted mathematical biometric minutiae templates           |
|  - Sensor captures fingerprint -> Compares locally inside Hardware      |
|  - Returns boolean result (true/false) + cryptographic token            |
+-------------------------------------------------------------------------+
```

### 2.3.1 Android Biometric API & TrustZone Architecture
On Android devices, fingerprint sensors interface directly with ARM TrustZone or dedicated Secure Processing Units (SPUs). When a user enrolls a fingerprint in system settings:
1. The physical sensor captures raw biometric data.
2. The Hardware Abstraction Layer (HAL) extracts vector feature templates (minutiae points).
3. The template is encrypted and stored strictly within hardware-protected storage.
4. When the Flutter application calls `local_auth`, the OS presents the native `BiometricPrompt` UI dialog.
5. The hardware sensor compares the live fingerprint scan against stored templates inside ARM TrustZone.
6. The OS returns a binary success (`true`) or failure (`false`) status back to the application over a platform channel, accompanied by an optional cryptographic signature.

### 2.3.2 iOS Secure Enclave Framework
On Apple iOS devices, biometric operations (Touch ID fingerprint scanning and Face ID facial recognition) are processed by the **Secure Enclave**—a dedicated coprocessor isolated from the primary application processor. The Secure Enclave executes a secure boot process, maintains its own encrypted memory space, and evaluates biometric matches autonomously. Third-party applications using iOS `LocalAuthentication` framework receive only authentication outcomes without exposing raw mathematical templates.

---

## 2.4 SERVERLESS CLOUD DATABASE SYSTEMS & REAL-TIME LEDGER ARCHITECTURES

Traditional mobile application architectures relied heavily on multi-tiered custom backends (e.g., Node.js/Express, Spring Boot, or Django application servers managing connections to a relational database). While mature, traditional monolithic backends introduce significant operational overhead, latency bottlenecks, and maintenance complexity for mobile engineering teams.

```
TRADITIONAL MONOLITHIC ARCHITECTURE:
Mobile Client  <--->  API Gateway  <--->  Application Server  <--->  Relational DB
                                         (Node/Django/Java)

MODERN SERVERLESS CLOUD ARCHITECTURE (SMARTPAY):
Mobile Client  <=================================================>  Supabase Cloud
(Flutter SDK)           HTTPS REST / WebSockets / PostgREST       (PostgreSQL DB)
```

### 2.4.1 Supabase Architecture & Serverless PostgreSQL
Supabase is an open-source serverless cloud platform built directly on top of PostgreSQL—the world's most advanced open-source relational database management system. Supabase provides:
- **PostgREST Engine:** Automatically turns PostgreSQL database schemas into secure, low-latency RESTful APIs.
- **Realtime Engine:** Listens to PostgreSQL Write-Ahead Logs (WAL) and broadcasts database mutations (INSERT, UPDATE, DELETE) to subscribed mobile clients via WebSockets.
- **GoTrue Auth Engine:** Handles user registration, JWT token generation, password hashing, and session management.

By connecting the Flutter mobile app directly to Supabase over HTTPS and WebSockets, SmartPay eliminates intermediate server bottlenecks while maintaining atomic transaction safety and ACID guarantees (Atomicity, Consistency, Isolation, Durability) for financial operations.

---

## 2.5 CROSS-DEVICE AUTHENTICATION & SESSION PORTABILITY

A major innovation of SmartPay is resolving the conflict between hardware biometrics and multi-device cloud login.

In standard applications:
- **Approach A (Device-Locked):** The app generates a local cryptographic key pair bound to the phone's hardware key store. The public key is sent to the server. Login is only possible from that specific physical phone.
- **Approach B (Unrestricted Cloud Login):** The user logs in with phone/password from any device, but the app fails to enforce hardware biometric scanning during remote sign-ins.

### 2.5.1 SmartPay Hybrid Cross-Device Model
SmartPay resolves this trade-off through a two-tiered cloud identification and local validation mechanism:
1. **Cloud Profile Discovery:** When a user launches SmartPay on any mobile phone, they enter their phone number. The app normalizes international digits (`+234 801 234 5678` $\rightarrow$ `08012345678`) and queries the cloud `profiles` table to locate the account profile.
2. **Local Biometric Challenge:** Once the cloud profile is identified, SmartPay checks if the current host device possesses functional fingerprint hardware (`local_auth`). If available, it prompts the user for local fingerprint authentication.
3. **Cloud PIN Validation:** Following local biometric approval (or fallback), the app verifies the entered 4-digit PIN against the encrypted `pin` hash stored in the cloud profile.
4. **Audit Log Registration:** The system logs the authentication outcome, method (`fingerprint` or `pin`), success flag, and current target device metadata (`defaultTargetPlatform`) to the cloud `biometric_login_logs` table.

This model achieves true account portability across any mobile phone while enforcing local hardware biometric gatekeeping whenever hardware biometrics are present.

---

## 2.6 VALUE-ADDED FINANCIAL TOOLS IN MODERN MICRO-FINTECH

Modern mobile payment gateways must transcend basic transfer capabilities to foster user retention and promote financial discipline. SmartPay integrates two core value-added financial management tools:

### 2.6.1 Safebox Locked Savings Vault
A common behavioral challenge in personal finance is liquidity management: when liquid funds remain visible and accessible in a main wallet balance, users are prone to impulse spending. SmartPay solves this by implementing a **Safebox Savings Vault**.
- **Mechanism:** Users transfer excess funds from their main liquid balance into a dedicated `safebox_balance` partition.
- **Locking Logic:** Safebox balances are segregated from daily spending checkouts (P2P transfers, utility payments, QR payments cannot debit the Safebox balance directly).
- **Yield Accrual:** Funds residing in the Safebox accrue interest over time, incentivizing long-term capital preservation.

### 2.6.2 Automated Micro-Credit & Loan Engine
For users encountering temporary liquidity shortages, traditional micro-finance institutions require manual paper applications, guarantor approvals, and multi-day processing delays. SmartPay embeds an **Automated Micro-Loan Engine**:
- **Disbursement Algorithm:** Qualified users select a micro-credit tier (e.g., ₦5,000, ₦10,000, ₦20,000). The engine immediately increases the user's main wallet `balance` while logging an equivalent liability in `loan_balance`.
- **Atomic Execution:** The disbursement occurs within an atomic database update, instantly providing spending liquidity.
- **Repayment Tracking:** Users repay outstanding loans directly from their main balance, instantly updating `loan_balance` and logging audit transaction receipts.

---

## 2.7 COMPARATIVE REVIEW OF EXISTING MOBILE PAYMENT PLATFORMS

To evaluate SmartPay's architectural contributions, Table 2.1 presents a comparative feature analysis against existing commercial and academic mobile payment platforms.

**Table 2.1: Comparative Feature Analysis of Mobile Payment Systems**

| System / Platform | Hardware Biometric Gatekeeper | Cross-Device Portability | Integrated Safebox Vault | Micro-Loan Disbursement Engine | Native QR Checkout | Cloud Forensic Audit Logs | Backend Infrastructure |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Traditional Banking Apps** | Single-Factor PIN / OTP | Low (Device Locked) | No (Separate App) | Manual Application | Limited | Internal / Opaque | Legacy Monolithic Server |
| **Standard Mobile Wallets** | Fingerprint (Optional) | Medium (SMS Reset) | No | No | Basic Static QR | None (User-facing) | Cloud Microservices |
| **Commercial Fintech Apps** | Biometric / PIN | High | Savings Pocket | Third-Party Credit | Vendor Dependent | Limited History | Custom API Gateways |
| **SmartPay (This Project)** | **Strict Dual-Factor (Fingerprint + PIN)** | **High (Cloud Normalized Phone Discovery)** | **Integrated High-Yield Safebox Vault** | **Instant Embedded Micro-Loan Engine** | **Dynamic QR Scanner & Generator** | **Real-Time Cloud Audit Trail (`biometric_login_logs`)** | **Serverless Supabase PostgreSQL** |

---

## 2.8 CONCEPTUAL & THEORETICAL FRAMEWORK OF SMARTPAY

SmartPay's design is anchored in **Zero-Trust Security Architecture** and **Event-Driven Reactive Reactive Data Models**.

```
+-------------------------------------------------------------------------+
|                  SMARTPAY CONCEPTUAL THEORETICAL FRAMEWORK              |
+-------------------------------------------------------------------------+
|  CLIENT INPUT LAYER                                                     |
|  - Phone Number Input  |  Biometric Fingerprint Scan  |  4-Digit PIN     |
+-------------------------------------------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|  GATEKEEPER SECURITY LAYER                                             |
|  - local_auth Hardware Fingerprint Verification                         |
|  - Device Platform Metadata Extraction (Android/iOS)                    |
+-------------------------------------------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|  CLOUD TRANSACTION & AUDIT LAYER (SUPABASE)                             |
|  - Phone Normalization & Profile Querying (`profiles`)                  |
|  - Encrypted PIN Verification                                           |
|  - Financial Ledger Execution (P2P / Safebox / Loans / Utilities)       |
|  - Real-Time Audit Log Emission (`biometric_login_logs`)                |
+-------------------------------------------------------------------------+
```

---

## 2.9 SUMMARY OF GAPS IN EXISTING LITERATURE

The review of current literature and existing commercial platforms reveals three major gaps:
1. **Lack of Enforced Dual-Factor Biometric Security:** Most apps treat biometrics as a convenience shortcut replacing passwords, rather than enforcing a strict dual-factor requirement combining local inherence with cloud knowledge verification.
2. **Inadequate User-Facing Forensic Transparency:** Payment apps record transaction amounts but fail to log device-level authentication attempts (fingerprint successes/failures, platform metadata) in an accessible database format.
3. **Architectural Complexity of Custom Backend Middleware:** Existing mobile fintech platforms overcomplicate cross-device synchronization by building heavy intermediate middleware servers rather than utilizing modern serverless PostgreSQL cloud architectures with Row Level Security.

SmartPay addresses all three gaps through its dual-factor local_auth gatekeeper, serverless Supabase PostgreSQL database, and cloud audit logging system.
