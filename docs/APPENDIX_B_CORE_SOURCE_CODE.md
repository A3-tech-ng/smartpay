# APPENDIX B: CORE DART SOURCE CODE LISTINGS

---

## B.1 BIOMETRIC SERVICE (`lib/services/biometric_service.dart`)

```dart
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();
  final SupabaseService _supabaseService = SupabaseService();

  /// Check if device supports biometrics generally
  Future<bool> isBiometricAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Error checking biometrics: $e');
      }
      return false;
    }
  }

  /// Check specifically if fingerprint hardware is available
  Future<bool> hasFingerprintHardware() async {
    try {
      if (!await isBiometricAvailable()) return false;
      final List<BiometricType> availableBiometrics =
          await _auth.getAvailableBiometrics();
      
      return availableBiometrics.contains(BiometricType.fingerprint) ||
             availableBiometrics.contains(BiometricType.strong) ||
             availableBiometrics.contains(BiometricType.weak);
    } on PlatformException catch (e) {
      return false;
    }
  }

  /// Authenticate using phone fingerprint hardware & log to Supabase
  Future<bool> authenticate({String userId = 'user_john_doe'}) async {
    bool isAuthenticated = false;
    try {
      isAuthenticated = await _auth.authenticate(
        localizedReason: 'Please place your finger on the phone fingerprint sensor to access Biometric Payment Gateway',
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Fingerprint Authentication Required',
            cancelButton: 'Cancel',
          ),
          IOSAuthMessages(
            cancelButton: 'Cancel',
          ),
        ],
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      isAuthenticated = false;
    }

    // Log login attempt to Supabase backend
    await _supabaseService.logBiometricLogin(
      userId: userId,
      method: 'fingerprint',
      success: isAuthenticated,
    );

    return isAuthenticated;
  }
}
```

---

## B.2 SUPABASE BACKEND SERVICE EXCERPT (`lib/services/supabase_service.dart`)

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://dvmzhkfgbrcsvnivfzjc.supabase.co';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }

  SupabaseClient get client => Supabase.instance.client;

  /// Query profile by phone number across any device
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

  /// Log biometric login attempt
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
}
```
