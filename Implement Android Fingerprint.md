### Implement Android Fingerprint Authentication for SmartPay

Implement secure fingerprint authentication for the SmartPay Flutter application using Android's native biometric authentication framework.

## Objective

Replace any custom fingerprint implementation with Android's secure biometric authentication. The application must never capture, store, or process fingerprint images or templates. All fingerprint verification must be performed by the Android operating system.

## Requirements

### Registration

1. After a user successfully creates an account using username, phone number, password, and face registration, ask the user:

   **"Would you like to enable Fingerprint Login on this device?"**

2. If the device supports biometrics:

   * Check whether fingerprint authentication hardware is available.
   * Check whether at least one fingerprint is enrolled on the device.
   * Display appropriate messages if hardware is unavailable or no fingerprints are enrolled.

3. If the user agrees:

   * Launch Android's native biometric prompt.
   * Require successful fingerprint authentication.
   * Store only a secure flag indicating that biometric login is enabled for this user on this device.
   * Do not store fingerprint images or fingerprint templates.

### Login

1. On the login screen display:

   * Login with Username and Password
   * Login with Face Recognition
   * Login with Fingerprint

2. When the user selects Fingerprint Login:

   * Verify that biometric login has been enabled.
   * Check device biometric availability.
   * Launch Android's native biometric prompt.
   * Wait for Android to authenticate the fingerprint.

3. If authentication succeeds:

   * Retrieve the user's secure login credentials or refresh token.
   * Authenticate the user.
   * Navigate to the application dashboard.

4. If authentication fails:

   * Allow additional attempts according to Android's biometric policy.
   * Show an appropriate error message.
   * Never bypass authentication.

### Security Requirements

* Never access raw fingerprint data.
* Never save fingerprint images.
* Never transmit fingerprint information to the backend.
* Never store fingerprint templates in the database.
* Never implement a custom fingerprint recognition algorithm.
* Use only Android's secure biometric authentication APIs.

### Backend

The Python FastAPI backend must not perform fingerprint recognition.

The backend should only:

* Verify the user's authenticated session.
* Validate secure access tokens.
* Return user information after successful authentication.
* Record login events.

### Flutter Implementation

Implement:

* Biometric capability detection.
* Hardware availability checks.
* Enrolled fingerprint checks.
* Native biometric prompt.
* Authentication state management.
* Secure storage for biometric preference.
* Proper error handling.
* Automatic fallback to password login if biometrics are unavailable.

### User Experience

* Show clear instructions during authentication.
* Display meaningful error messages.
* Support dark mode.
* Handle device rotation.
* Prevent duplicate authentication requests.
* Maintain smooth animations.

### Code Quality

* Separate biometric services from authentication logic.
* Follow clean architecture principles.
* Write reusable, well-documented code.
* Include comprehensive error handling and unit tests.

