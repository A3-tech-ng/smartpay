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
      
      if (kDebugMode) {
        print('Available biometrics: $availableBiometrics');
      }

      return availableBiometrics.contains(BiometricType.fingerprint) ||
             availableBiometrics.contains(BiometricType.strong) ||
             availableBiometrics.contains(BiometricType.weak);
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Error checking fingerprint hardware: $e');
      }
      return false;
    }
  }

  /// Check if the user has actually enrolled fingerprints on this device
  Future<bool> hasEnrolledFingerprints() async {
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final List<BiometricType> available = await _auth.getAvailableBiometrics();
      return available.contains(BiometricType.fingerprint) ||
             available.contains(BiometricType.strong) ||
             available.contains(BiometricType.weak);
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Error checking enrolled fingerprints: $e');
      }
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
      if (kDebugMode) {
        print('Error authenticating with fingerprint: $e');
      }
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

  /// Save user's preference for biometric login on this device
  Future<void> setBiometricEnabled(String userId, bool enabled) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometric_enabled_$userId', enabled);
    } catch (e) {
      if (kDebugMode) {
        print('Error setting biometric preference: $e');
      }
    }
  }

  /// Get user's preference for biometric login on this device
  Future<bool> isBiometricEnabled(String userId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool('biometric_enabled_$userId') ?? false;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting biometric preference: $e');
      }
      return false;
    }
  }
}
