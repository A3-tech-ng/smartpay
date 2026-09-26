# CHAPTER 4: SYSTEM IMPLEMENTATION & MODULE DEEP-DIVE

---

## 4.1 DEVELOPMENT ENVIRONMENT & TECHNOLOGICAL STACK SETUP

The implementation of SmartPay utilized modern, cross-platform software engineering tools to construct both the mobile client software and cloud database backend infrastructure.

```
+-------------------------------------------------------------------------+
|                  SMARTPAY TECHNOLOGICAL STACK MATRIX                     |
+-------------------------------------------------------------------------+
|  FRAMEWORK & LANGUAGE  | Flutter SDK ^3.11.5 | Dart ^3.11.0             |
|  STATE MANAGEMENT     | Provider Pattern (^6.1.5+1)                     |
|  BIOMETRIC HARDWARE   | local_auth (^3.0.1)                             |
|  CLOUD BACKEND        | Supabase Flutter (^2.8.4) & PostgreSQL Cloud     |
|  HARDWARE CAMERA & QR | mobile_scanner (^6.0.2) & qr_flutter (^4.1.0)   |
|  UI & TYPOGRAPHY      | Google Fonts (Outfit, Inter) & Lucide Icons     |
|  LOCAL STORAGE        | shared_preferences (^2.2.0)                     |
+-------------------------------------------------------------------------+
```

### 4.1.1 Dependency Configuration (`pubspec.yaml`)
The project dependencies specified in `pubspec.yaml` govern third-party integration libraries:

```yaml
name: biometric_payment_gateway
description: "Biometric Payment Gateway Mobile Application."
version: 1.0.0+1

environment:
  sdk: ^3.11.5

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  local_auth: ^3.0.1
  shared_preferences: ^2.2.0
  google_fonts: ^8.1.0
  provider: ^6.1.5+1
  lucide_icons: ^0.257.0
  supabase_flutter: ^2.8.4
  http: ^1.2.0
  image_picker: ^1.1.2
  camera: ^0.10.5
  qr_flutter: ^4.1.0
  mobile_scanner: ^6.0.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
```

---

## 4.2 CORE ARCHITECTURE & STATE MANAGEMENT

SmartPay employs the **Provider Pattern** for decoupled, reactive state management. The global state tree is governed by `ThemeProvider` (which manages Dark/Light UI dynamic themes) and reactive data listeners that bind UI widgets directly to `SupabaseService` data models.

```
+-------------------------------------------------------------------------+
|                PROVIDER STATE MANAGEMENT FLOW TOPOLOGY                  |
+-------------------------------------------------------------------------+
|  main.dart (MultiProvider Root)                                         |
|    |                                                                    |
|    +---> ThemeProvider (Notifies Dark / Light theme mutations)          |
|    |                                                                    |
|    +---> SupabaseService (Listens to PostgreSQL WAL via WebSockets)     |
|            |                                                            |
|            +---> Updates User Balance, Safebox, Loans, & Transactions   |
|            +---> Notifies HomeScreen UI Widgets for Instant Re-render   |
+-------------------------------------------------------------------------+
```

### 4.2.1 Application Entrypoint (`lib/main.dart`)
The main entry point initializes Supabase cloud connections, loads system themes, and configures application route handlers:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const SmartPayApp(),
    ),
  );
}
```

---

## 4.3 CLIENT-SIDE SERVICE IMPLEMENTATIONS

### 4.3.1 Biometric Authentication Service (`lib/services/biometric_service.dart`)
`BiometricService` acts as the interface between the Flutter app layer and native mobile platform biometric hardware (`local_auth`). It handles hardware availability checks, fingerprint enrollment checks, prompt invocation, and automatic logging of authentication outcomes to Supabase.

#### Key Methods in `BiometricService`:

1. **Hardware Availability Check (`isBiometricAvailable`):**
   ```dart
   Future<bool> isBiometricAvailable() async {
     try {
       final bool canCheck = await _auth.canCheckBiometrics;
       final bool isSupported = canCheck || await _auth.isDeviceSupported();
       return isSupported;
     } on PlatformException catch (e) {
       return false;
     }
   }
   ```

2. **Fingerprint Hardware Sensor Verification (`hasFingerprintHardware`):**
   ```dart
   Future<bool> hasFingerprintHardware() async {
     try {
       if (!await isBiometricAvailable()) return false;
       final List<BiometricType> available = await _auth.getAvailableBiometrics();
       return available.contains(BiometricType.fingerprint) ||
              available.contains(BiometricType.strong) ||
              available.contains(BiometricType.weak);
     } catch (e) {
       return false;
     }
   }
   ```

3. **Biometric Prompt Execution & Audit Logging (`authenticate`):**
   ```dart
   Future<bool> authenticate({String userId = 'user_john_doe'}) async {
     bool isAuthenticated = false;
     try {
       isAuthenticated = await _auth.authenticate(
         localizedReason: 'Please place your finger on the sensor to access SmartPay',
         authMessages: const <AuthMessages>[
           AndroidAuthMessages(
             signInTitle: 'Fingerprint Authentication Required',
             cancelButton: 'Cancel',
           ),
           IOSAuthMessages(cancelButton: 'Cancel'),
         ],
         biometricOnly: true,
         persistAcrossBackgrounding: true,
       );
     } catch (e) {
       isAuthenticated = false;
     }

     // Log attempt to cloud database table biometric_login_logs
     await _supabaseService.logBiometricLogin(
       userId: userId,
       method: 'fingerprint',
       success: isAuthenticated,
     );

     return isAuthenticated;
   }
   ```

---

### 4.3.2 Supabase Backend Service (`lib/services/supabase_service.dart`)
`SupabaseService` encapsulates all RESTful and Realtime WebSocket operations communicating with the Supabase cloud database instance.

#### Key Capabilities Implemented in `SupabaseService`:

1. **Cross-Device Phone Profile Discovery (`getProfileByPhoneNumber`):**  
   Normalizes international phone number strings, stripping non-digit characters (`+234...`, `080...`) to match cloud records across any phone handset:
   ```dart
   Future<Map<String, dynamic>?> getProfileByPhoneNumber(String phoneNumber) async {
     final String cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');
     final allProfiles = await client.from('profiles').select();
     for (final p in allProfiles) {
       final String dbPhone = (p['phone_number'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
       if (dbPhone == cleanPhone || cleanPhone.endsWith(dbPhone.substring(dbPhone.length - 8))) {
         return p;
       }
     }
     return null;
   }
   ```

2. **Peer-to-Peer Fund Transfer Engine (`transferFunds`):**  
   Executes balance transfers between sender and recipient, creating auditable transaction receipts:
   ```dart
   Future<bool> transferFunds({
     required String senderUserId,
     required String recipientAccountNo,
     required double amount,
     required String recipientName,
   }) async {
     final senderProfile = await getProfileByUserId(senderUserId);
     final currentBalance = (senderProfile['balance'] as num).toDouble();
     if (currentBalance < amount) throw Exception('Insufficient balance');

     // Deduct sender balance
     await client.from('profiles').update({
       'balance': currentBalance - amount,
       'updated_at': DateTime.now().toIso8601String(),
     }).eq('user_id', senderUserId);

     // Log debit transaction
     await client.from('transactions').insert({
       'user_id': senderUserId,
       'title': 'Transfer to $recipientName',
       'subtitle': 'SmartPay • $recipientAccountNo',
       'amount': '- ₦${amount.toStringAsFixed(2)}',
       'is_debit': true,
       'status': 'Successful',
     });
     return true;
   }
   ```

3. **Safebox Savings Deposit & Lock Engine (`depositToSafebox`):**  
   Segregates spending capital into locked savings:
   ```dart
   Future<bool> depositToSafebox(String userId, double amount) async {
     final profile = await getProfileByUserId(userId);
     final double currentBalance = (profile['balance'] as num).toDouble();
     final double currentSafebox = (profile['safebox_balance'] as num).toDouble();

     if (currentBalance < amount) throw Exception('Insufficient main balance');

     await client.from('profiles').update({
       'balance': currentBalance - amount,
       'safebox_balance': currentSafebox + amount,
     }).eq('user_id', userId);

     await client.from('transactions').insert({
       'user_id': userId,
       'title': 'Safebox Savings Deposit',
       'subtitle': 'Locked Vault Accumulation',
       'amount': '- ₦${amount.toStringAsFixed(2)}',
       'is_debit': true,
       'status': 'Successful',
     });
     return true;
   }
   ```

4. **Automated Micro-Loan Disbursement Engine (`applyForLoan`):**  
   Instantly injects credit liquidity into the user's main wallet while logging debt liabilities:
   ```dart
   Future<bool> applyForLoan(String userId, double loanAmount) async {
     final profile = await getProfileByUserId(userId);
     final double currentBalance = (profile['balance'] as num).toDouble();
     final double currentLoan = (profile['loan_balance'] as num).toDouble();

     await client.from('profiles').update({
       'balance': currentBalance + loanAmount,
       'loan_balance': currentLoan + loanAmount,
     }).eq('user_id', userId);

     await client.from('transactions').insert({
       'user_id': userId,
       'title': 'Micro-Loan Disbursed',
       'subtitle': 'Instant Credit Inflow',
       'amount': '+ ₦${loanAmount.toStringAsFixed(2)}',
       'is_debit': false,
       'status': 'Successful',
     });
     return true;
   }
   ```

5. **Cloud Biometric Audit Logger (`logBiometricLogin`):**  
   Records technical metadata for every login event:
   ```dart
   Future<bool> logBiometricLogin({
     required String userId,
     required String method,
     required bool success,
   }) async {
     final String deviceInfo = defaultTargetPlatform.toString();
     await client.from('biometric_login_logs').insert({
       'user_id': userId,
       'auth_method': method,
       'is_successful': success,
       'device_info': deviceInfo,
     });
     return true;
   }
   ```

---

## 4.4 DETAILED IMPLEMENTATION OF KEY FUNCTIONAL MODULES

### 4.4.1 Financial Assets Dashboard & Privacy Masking (`HomeScreen`)
`HomeScreen` represents the central financial hub of SmartPay. It renders three primary wallet metric cards:
1. **Main Wallet Balance Card:** Displays liquid funds available for immediate transfer, QR checkout, or utility bills. Includes an eye toggle (`isBalanceVisible`) to mask sensitive figures (`••••••••`) against physical shoulder surfing.
2. **Safebox Vault Card:** Displays locked savings balance with deposit/withdraw modal sheets.
3. **Micro-Loan Liability Card:** Displays outstanding credit debt with instant loan request and repayment buttons.

```
+-------------------------------------------------------------------------+
|                  SMARTPAY MAIN DASHBOARD WIREFRAME LAYOUT               |
+-------------------------------------------------------------------------+
|  [Header: User Avatar | Greeting | KYC Tier Badge | Dark/Light Toggle]  |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  | MAIN WALLET BALANCE                                [Eye Toggle]   |  |
|  | ₦ 10,000.00  (Account No: 9023456781)                             |  |
|  | [ + Deposit ]  [ -> Transfer ]  [ (QR) Pay ]  [ (Vault) Safebox ] |  |
|  +-------------------------------------------------------------------+  |
|                                                                         |
|  +-------------------------------+   +-------------------------------+  |
|  | SAFEBOX SAVINGS VAULT         |   | OUTSTANDING MICRO-LOAN        |  |
|  | ₦ 5,000.00                    |   | ₦ 0.00                        |  |
|  | [ Lock Funds ]                |   | [ Borrow Credit ]             |  |
|  +-------------------------------+   +-------------------------------+  |
|                                                                         |
|  [ QUICK UTILITY HUB: Airtime | Data | Power | Cable TV | Betting ]     |
|                                                                         |
|  [ RECENT TRANSACTION HISTORY LEDGER (Real-time Stream Updates) ]       |
+-------------------------------------------------------------------------+
```

---

### 4.4.2 QR Scan-to-Pay Engine (`mobile_scanner` & `qr_flutter`)
SmartPay supports instantaneous retail merchant checkout using dynamic Quick Response (QR) codes:
- **QR Generator:** Renders a high-density matrix QR code containing JSON-encoded account payload (`{"account_no": "9023456781", "name": "Imam"}`) via `qr_flutter`.
- **Camera Viewfinder Scanner:** Invokes `mobile_scanner` to capture live camera feed, scan merchant QR codes, parse payment targets, and open instant checkout modal sheets.

---

### 4.4.3 Administrative Control Panel (`AdminDashboardScreen`)
Privileged system administrators access a dedicated monitoring dashboard by entering credentials stored in `admin_settings`. The Admin Portal allows:
- Real-time inspection of all registered cloud profiles and global liquidity metrics.
- Monitoring total Safebox locked deposits and global outstanding micro-loan liabilities.
- Viewing live security audit streams from `biometric_login_logs` to detect unauthorized fingerprint attempts across host platform devices.

---

## 4.5 DYNAMIC THEME SYSTEM (DARK & LIGHT MODE)

SmartPay incorporates a dynamic Material 3 design system governed by `ThemeProvider`. Users can toggle between:
- **Dark Indigo Theme:** Sleek dark background (`#0D1117`), deep blue-grey cards (`#161B22`), glassmorphic borders, and vibrant emerald accent highlights (`#2EBD85`).
- **Light Pearl Theme:** Crisp light background (`#F6F8FA`), snow white cards (`#FFFFFF`), dark indigo headers (`#0D1117`), and crisp cobalt blue accents.
