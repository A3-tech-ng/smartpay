# CHAPTER 7: USER MANUAL & DEPLOYMENT GUIDE

---

## 7.1 SYSTEM HARDWARE & SOFTWARE PREREQUISITES

To deploy, execute, and operate the SmartPay mobile application, host environments must satisfy minimum hardware and software prerequisites.

### 7.1.1 End-User Mobile Device Prerequisites
- **Operating System:** Android 8.0 (API Level 26) or higher / Apple iOS 13.0 or higher.
- **Biometric Hardware:** Integrated capacitive, optical, or ultrasonic fingerprint sensor (recommended for full biometric gatekeeper capabilities).
- **Camera Hardware:** Autofocus rear camera sensor (required for QR code viewfinder scanning).
- **Network Connectivity:** Active Wi-Fi, 4G LTE, or 5G cellular internet connectivity for cloud database synchronization.

### 7.1.2 Development & Deployment Prerequisites
- **Workstation OS:** Windows 10/11 64-bit, macOS Monterey (12.0+), or Linux (Ubuntu 20.04 LTS+).
- **SDK & Tools:** Flutter SDK ^3.11.5, Dart SDK ^3.11.0, Android Studio / VS Code with Flutter extensions.
- **Backend Service:** Active Supabase project account with PostgreSQL database engine.

---

## 7.2 APPLICATION INSTALLATION GUIDE

### 7.2.1 Building & Installing Android Package (APK)
1. Open terminal in project root directory:
   ```bash
   cd /home/imam/dev/flutter_apps/Biometric_payment_gateway
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Compile release APK:
   ```bash
   flutter build apk --release
   ```
4. Install generated APK onto connected mobile device:
   ```bash
   flutter install
   ```

---

## 7.3 STEP-BY-STEP USER OPERATIONAL GUIDE

```
+-------------------------------------------------------------------------+
|                  SMARTPAY OPERATIONAL WORKFLOW MAP                      |
+-------------------------------------------------------------------------+
|  [STEP 1: REGISTRATION / LOGIN]                                         |
|  - Enter Full Name, Phone Number, & Set 4-Digit PIN                     |
|                                                                         |
|  [STEP 2: DUAL-FACTOR BIOMETRIC GATEKEEPER]                             |
|  - Place finger on phone fingerprint scanner + Verify 4-Digit PIN       |
|                                                                         |
|  [STEP 3: DASHBOARD COMMAND CENTER]                                     |
|  - View Main Balance | Hide/Show Figures | Perform Financial Actions     |
|                                                                         |
|  [STEP 4: FINANCIAL OPERATIONS]                                         |
|  - Execute P2P Transfer  |  Lock Safebox Savings  |  Apply Micro-Loan   |
|  - Pay Utility Bills     |  Scan QR Merchant      |  Inspect Audit Logs |
+-------------------------------------------------------------------------+
```

### 7.3.1 Account Creation & Onboarding
1. Launch SmartPay application from mobile app drawer.
2. On the **Login Screen**, tap **"Register New Account"**.
3. Input your **Full Name**, valid **Phone Number** (e.g., `08012345678`), and set a **4-Digit Security PIN** (e.g., `1234`).
4. Tap **"Create Account"**. The app registers your profile in Supabase cloud database, generates a 10-digit wallet account number, and allocates a default starting balance of ₦10,000.00.

### 7.3.2 Authenticating via Dual-Factor Biometrics
1. Enter registered phone number on **Login Screen**.
2. Tap **"Authenticate with Fingerprint"**.
3. Place your finger on host device's fingerprint sensor when native OS `BiometricPrompt` appears.
4. Upon fingerprint match confirmation, enter your 4-digit PIN.
5. SmartPay validates credentials against cloud profiles, logs the attempt to `biometric_login_logs`, and opens the **HomeScreen Dashboard**.

### 7.3.3 Executing Peer-to-Peer (P2P) Fund Transfers
1. On the main dashboard, tap **"Transfer"**.
2. Enter recipient's **10-Digit SmartPay Account Number** and transfer **Amount** (e.g., `₦2,000`).
3. Tap **"Send Money"**.
4. SmartPay checks sender balance sufficiency, deducts funds, credits recipient profile, and displays an instant digital receipt.

### 7.3.4 Locking Funds in Safebox Savings Vault
1. On the dashboard, locate the **Safebox Savings Vault** card.
2. Tap **"Deposit to Vault"**.
3. Enter amount to lock (e.g., `₦3,000`).
4. SmartPay transfers funds from liquid main balance into `safebox_balance`, protecting capital from daily spending.

### 7.3.5 Applying for & Repaying Instant Micro-Loans
1. On the dashboard, locate the **Micro-Loan** card.
2. Tap **"Borrow Credit"**.
3. Select credit tier (e.g., `₦5,000`).
4. Tap **"Disburse Loan"**. The system instantly injects ₦5,000 into main balance while logging debt in `loan_balance`.
5. To repay, tap **"Repay Loan"**, enter repayment amount, and confirm deduction from main balance.

### 7.3.6 Merchant QR Code Scan-to-Pay
1. Tap **"Pay with QR"** on main dashboard.
2. Point camera viewfinder at merchant's dynamic QR code.
3. SmartPay parses payment target details and displays confirmation modal sheet.
4. Confirm payment to complete instant retail checkout.

---

## 7.4 ADMINISTRATOR OPERATIONAL MANUAL

1. On **Login Screen**, tap **"Admin Login"** in upper right corner.
2. Input administrator credentials (default: Username `admin`, Password `admin_password_2026`).
3. Upon access authorization, the **Admin Dashboard** displays:
   - Total System Users & Global Liquidity Metrics.
   - Total Safebox Locked Vault Capital.
   - Global Outstanding Micro-Loan Credit Liabilities.
   - Live Security Audit Stream from `biometric_login_logs` showing every fingerprint authentication attempt across target devices.

---

## 7.5 TROUBLESHOOTING GUIDE & FREQUENTLY ASKED QUESTIONS (FAQ)

- **Q1: What happens if my device lacks a physical fingerprint sensor?**  
  *Answer:* SmartPay automatically detects missing biometric hardware via `BiometricService.hasFingerprintHardware()` and seamlessly degrades to secure 4-digit PIN authentication.

- **Q2: Can I log into my account from a new mobile phone?**  
  *Answer:* Yes. SmartPay normalizes phone numbers across international formats, allowing you to access your cloud profile from any mobile phone by entering your phone number and PIN.

- **Q3: What should I do if fingerprint scanning fails repeatedly?**  
  *Answer:* Ensure your finger glass sensor is clean and dry. If hardware biometric attempts fail, tap "Cancel" on native dialog to complete authentication via PIN entry.
