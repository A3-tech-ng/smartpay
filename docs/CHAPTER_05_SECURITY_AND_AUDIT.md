# CHAPTER 5: SECURITY ARCHITECTURE, MATHEMATICAL MODELS & FORENSIC AUDITING

---

## 5.1 CRYPTOGRAPHIC & HARDWARE SECURITY MODEL

Security in SmartPay is structured according to the **Defense-in-Depth (DiD)** cybersecurity principle. Rather than relying on a single defensive perimeter, SmartPay implements multiple concentric layers of security spanning hardware key stores, platform channels, cloud network transport, and database authorization rules.

```
+-------------------------------------------------------------------------+
|                  SMARTPAY DEFENSE-IN-DEPTH LAYER MODEL                  |
+-------------------------------------------------------------------------+
| LAYER 1: HARDWARE ISOLATION (ARM TrustZone / iOS Secure Enclave)        |
| - Biometric minutiae storage & hardware fingerprint matching             |
+-------------------------------------------------------------------------+
  v
+-------------------------------------------------------------------------+
| LAYER 2: APPLICATION GATEKEEPER (Flutter local_auth + 2FA PIN)           |
| - Dual-Factor validation before routing to sensitive UI modules          |
+-------------------------------------------------------------------------+
  v
+-------------------------------------------------------------------------+
| LAYER 3: TRANSPORT ENCRYPTION (TLS 1.3 / HTTPS REST & WebSockets)       |
| - 256-bit AES transport encryption for all payload requests             |
+-------------------------------------------------------------------------+
  v
+-------------------------------------------------------------------------+
| LAYER 4: DATABASE ACCESS CONTROL (Supabase PostgreSQL Schema Rules)     |
| - Phone normalization, unique constraints, and atomic ACID updates      |
+-------------------------------------------------------------------------+
  v
+-------------------------------------------------------------------------+
| LAYER 5: FORENSIC AUDIT TRAIL (`biometric_login_logs` Table)            |
| - Real-time cloud logging of all biometric authentication attempts       |
+-------------------------------------------------------------------------+
```

### 5.1.1 Hardware Keystore & Biometric Template Isolation
A fundamental security guarantee of SmartPay is that **raw biometric templates are never transmitted across network channels or stored in external databases**. 

- On Android, the physical fingerprint scanner records minute pattern ridge intersections (minutiae). The hardware extracts mathematical feature vectors and encrypts them using AES-256 keys bound to ARM TrustZone hardware.
- When `BiometricService.authenticate()` executes, the OS displays the native `BiometricPrompt` sandbox window. The scanner performs an internal hardware matching operation inside ARM TrustZone.
- The OS returns only a boolean match response (`true`/`false`) across the Flutter platform channel.

---

## 5.2 MATHEMATICAL FORMULATION OF BIOMETRIC AUTHENTICATION CONFIDENCE

Biometric authentication confidence is mathematically defined by evaluating two primary statistical error metrics:

1. **False Acceptance Rate (FAR):** The probability that an unauthorized user's fingerprint scan is incorrectly accepted by the biometric system as a match:
   $$\text{FAR} = \frac{\text{Number of Unauthorized Scans Accepted}}{\text{Total Unauthorized Attempts}}$$

2. **False Rejection Rate (FRR):** The probability that a legitimate enrolled user's fingerprint scan is incorrectly rejected:
   $$\text{FRR} = \frac{\text{Number of Enrolled Scans Rejected}}{\text{Total Enrolled Attempts}}$$

```
  ERROR RATE (%)
    ^
    |      \                              /  False Acceptance Rate (FAR)
    |       \  False Rejection           /
    |        \ Rate (FRR)               /
    |         \                        /
    |          \                      /
    |           \                    /
    |            \                  /
    |             \                /
    |              \   EER POINT  /
    |---------------X------------/---------------------------->
    |              / \          /   DECISION THRESHOLD ($\theta$)
    |             /   \        /
    |            /     \      /
```

The point where FAR equals FRR is designated as the **Equal Error Rate (EER)**. Lower EER values indicate higher biometric precision. Modern mobile capacitive and ultrasonic fingerprint sensors achieve an FAR $< 0.001\%$ and FRR $< 1.0\%$.

### 5.2.1 Dual-Factor Security Entropy Equation
In SmartPay, authentication security combines knowledge ($\mathcal{F}_{\text{Knowledge}}$) and inherence ($\mathcal{F}_{\text{Inherence}}$).

Let $H(\text{PIN})$ represent the numerical entropy of a 4-digit PIN:
$$H(\text{PIN}) = \log_2(10^4) = \log_2(10000) \approx 13.297 \text{ bits}$$

Let $H(\text{Bio})$ represent the statistical entropy of a fingerprint minutiae template match:
$$H(\text{Bio}) = -\log_2(\text{FAR}) \approx -\log_2(10^{-5}) \approx 16.61 \text{ bits}$$

The total joint security entropy $H(\text{Total})$ for SmartPay's Dual-Factor gatekeeper is:
$$H(\text{Total}) = H(\text{Bio}) + H(\text{PIN}) \approx 16.61 + 13.297 = 29.907 \text{ bits}$$

This mathematical formulation demonstrates that combining fingerprint verification with PIN entry increases authentication security by over $65,000\times$ compared to standalone PIN verification.

---

## 5.3 ROW LEVEL SECURITY (RLS) & DATABASE ACCESS CONTROL EVALUATION

PostgreSQL features **Row Level Security (RLS)**, allowing database administrators to specify declarative policies restricting which data rows can be queried or modified based on user authorization tokens.

In SmartPay's production configuration:
- Tables `profiles`, `transactions`, `biometric_login_logs`, and `admin_settings` execute strict constraint validation rules (e.g., regex phone format validation `^(07|08|09)[0-9]{9}$`).
- Multi-row updates are protected by transaction boundaries:
  ```sql
  BEGIN;
    UPDATE profiles SET balance = balance - 5000 WHERE user_id = 'sender_uuid';
    UPDATE profiles SET balance = balance + 5000 WHERE account_no = '9023456781';
    INSERT INTO transactions (user_id, title, subtitle, amount, is_debit)
    VALUES ('sender_uuid', 'Transfer to John', 'SmartPay • 9023456781', '- ₦5,000.00', true);
  COMMIT;
  ```

---

## 5.4 PREVENTION OF COMMON CYBERSECURITY VULNERABILITIES

SmartPay's security architecture proactively neutralizes major financial threat vectors:

1. **Shoulder Surfing Protection:**  
   The main wallet balance features privacy masking toggles (`isBalanceVisible`), replacing financial figures with opaque symbols (`••••••••`) when navigating in public spaces.

2. **Replay & Man-In-The-Middle (MITM) Attack Prevention:**  
   All HTTP REST queries and WebSocket channels connecting the Flutter client to Supabase are encrypted using Transport Layer Security (TLS 1.3) with 256-bit AES encryption. Attackers capturing network packets cannot read or replay credentials.

3. **SIM-Swapping & Device Theft Mitigation:**  
   If an attacker steals a user's physical SIM card or phone handset, they cannot access SmartPay without passing the hardware biometric fingerprint scanner, which validates biological minutiae stored isolated within ARM TrustZone.

---

## 5.5 CLOUD FORENSIC AUDIT LOGGING FRAMEWORK (`biometric_login_logs`)

To ensure accountability, SmartPay records every authentication attempt in the `biometric_login_logs` cloud table.

```sql
CREATE TABLE IF NOT EXISTS public.biometric_login_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT REFERENCES public.profiles(user_id) ON DELETE CASCADE,
    auth_method TEXT NOT NULL, -- 'fingerprint' or 'pin'
    is_successful BOOLEAN NOT NULL,
    device_info TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);
```

### 5.5.1 Audit Record Data Structure
Each log entry captures:
- `user_id`: Target cloud user profile.
- `auth_method`: Specific authentication type invoked (`fingerprint` vs `pin`).
- `is_successful`: Binary outcome (`true` for granted, `false` for rejected).
- `device_info`: Hardware platform metadata (e.g., `TargetPlatform.android`, `TargetPlatform.iOS`).
- `created_at`: Precise UTC timestamp.

Privileged system administrators monitor this stream in real-time via the `AdminDashboardScreen`, enabling immediate detection of brute-force PIN attempts or unauthorized biometric presentations across target devices.
