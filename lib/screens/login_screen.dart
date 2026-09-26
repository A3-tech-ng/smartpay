import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons_flutter.dart';
import '../services/biometric_service.dart';
import '../services/supabase_service.dart';
import '../core/theme/app_theme.dart';
import '../core/config.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'admin_login_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final BiometricService _biometricService = BiometricService();
  final SupabaseService _supabaseService = SupabaseService();
  final ImagePicker _picker = ImagePicker();
  final _phoneFormKey = GlobalKey<FormState>();

  bool _isFingerprintHardwareAvailable = true;

  @override
  void initState() {
    super.initState();
    _checkFingerprintHardware();
  }

  Future<void> _checkFingerprintHardware() async {
    final hasHardware = await _biometricService.hasFingerprintHardware();
    if (mounted) {
      setState(() {
        _isFingerprintHardwareAvailable = hasHardware;
      });
    }
  }

  // State control
  bool _hasIdentified = false; // False = Enter phone, True = Choose auth method
  bool _isAuthenticating = false;
  String _authStatusMessage = '';
  double _loginProgress = 0.0;
  
  // User credentials
  String _phoneNumber = '';
  String _userId = '';
  String _fullName = '';
  String _kycTier = 'Tier 3 Verified';

  // Login variables
  int _selectedTab = 0; // 0 = PIN, 1 = Fingerprint
  String _enteredPin = '';

  // Phone input controller
  final TextEditingController _phoneController = TextEditingController();

  // Step 1: Identify Account by Phone Number
  Future<void> _identifyAccount() async {
    if (!_phoneFormKey.currentState!.validate()) return;

    setState(() {
      _isAuthenticating = true;
      _authStatusMessage = 'Finding account...';
    });

    final String inputPhone = _phoneController.text.trim();
    final String cleanPhone = inputPhone.replaceAll(RegExp(r'\D'), '');
    final String targetUserId = 'user_$cleanPhone';

    // Fetch profile from Supabase
    final profile = await _supabaseService.getProfileByPhoneNumber(inputPhone);

    setState(() {
      _isAuthenticating = false;
    });

    if (profile != null) {
      setState(() {
        _phoneNumber = inputPhone;
        _userId = profile['user_id'] ?? targetUserId;
        _fullName = profile['full_name'] ?? 'Biometric Gateway User';
        _kycTier = profile['kyc_tier'] ?? 'Tier 3 Verified';
        _hasIdentified = true;
        _enteredPin = '';
        _selectedTab = 0; // Default to PIN
      });
    } else {
      // Fallback for demo testing (e.g. John Doe's default phone number "+234 801 234 5678")
      if (inputPhone == '+234 801 234 5678' || cleanPhone == '8012345678' || cleanPhone == '08012345678') {
        setState(() {
          _phoneNumber = inputPhone;
          _userId = 'user_john_doe';
          _fullName = 'John Doe';
          _kycTier = 'Tier 3 Verified';
          _hasIdentified = true;
          _enteredPin = '';
          _selectedTab = 0;
        });
      } else {
        // Show dialog asking to register
        _showRegisterRedirectDialog(inputPhone);
      }
    }
  }

  void _showRegisterRedirectDialog(String phone) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Account Identification', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Could not immediately locate an active session for $phone on this device. Would you like to log in with your PIN or register a new account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              final String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
              setState(() {
                _phoneNumber = phone;
                _userId = 'user_$cleanPhone';
                _fullName = 'Biometric Gateway Account ($phone)';
                _kycTier = 'Tier 3 Verified';
                _hasIdentified = true;
                _enteredPin = '';
                _selectedTab = 0;
              });
            },
            child: const Text('Log In Anyway', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const RegisterScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Register', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Step 2a: PIN Verification
  Future<void> _verifyPin() async {
    setState(() {
      _isAuthenticating = true;
      _authStatusMessage = 'Verifying PIN...';
    });

    final verified = await _supabaseService.verifyPin(userId: _userId, pin: _enteredPin);

    setState(() {
      _isAuthenticating = false;
    });

    if (verified && mounted) {
      _navigateToHome();
    } else if (mounted) {
      setState(() {
        _enteredPin = '';
        _authStatusMessage = 'Incorrect security PIN. Please try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN validation failed. Try again.')),
      );
    }
  }

  // Step 2b: Fingerprint Verification
  Future<void> _authenticateWithFingerprint() async {
    // 1. Verify that biometric login has been enabled
    final bool isEnabled = await _biometricService.isBiometricEnabled(_userId);
    if (!isEnabled) {
      setState(() {
        _authStatusMessage = 'Fingerprint login has not been enabled for this account on this device.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fingerprint login is not enabled. Please log in using your PIN first, then enable it in Settings.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 2. Check device biometric availability
    final bool isBiometricAvail = await _biometricService.isBiometricAvailable();
    final bool hasHardware = await _biometricService.hasFingerprintHardware();
    if (!isBiometricAvail || !hasHardware) {
      setState(() {
        _isFingerprintHardwareAvailable = false;
        _authStatusMessage = 'this device does not have fingerprint hardware or it is currently unavailable';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('this device does not have fingerprint hardware or it is currently unavailable')),
      );
      return;
    }

    final hasEnrolled = await _biometricService.hasEnrolledFingerprints();
    if (!hasEnrolled) {
      setState(() {
        _authStatusMessage = 'Fingerprint login not configured. Please enroll fingerprints in your Android/iOS system settings first.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fingerprint enrolled on this device.')),
      );
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _authStatusMessage = 'Touch phone fingerprint sensor...';
    });

    final isAuthenticated = await _biometricService.authenticate(userId: _userId);

    setState(() {
      _isAuthenticating = false;
    });

    if (isAuthenticated && mounted) {
      _navigateToHome();
    } else if (mounted) {
      setState(() {
        _authStatusMessage = 'Fingerprint verification canceled or failed.';
      });
    }
  }


  void _navigateToHome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', true);
    await prefs.setString('logged_in_user_id', _userId);
    await prefs.setInt('last_active_time', DateTime.now().millisecondsSinceEpoch);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => HomeScreen(userId: _userId)),
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _hasIdentified ? _buildAuthSelectorScreen() : _buildPhoneInputScreen(),
          ),
        ),
      ),
    );
  }

  // SCREEN 1: Phone input screen
  Widget _buildPhoneInputScreen() {
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/imam.jpg',
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(LucideIcons.wallet, size: 48, color: AppTheme.primaryColor),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Biometric Payment Gateway Wallet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your phone number to access secure login methods.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 40),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: const Icon(LucideIcons.phone, color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.backgroundColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your phone number';
              }
              return null;
            },
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _isAuthenticating ? null : _identifyAccount,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _isAuthenticating
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Continue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(width: 8),
                      Icon(LucideIcons.arrowRight, size: 18),
                    ],
                  ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Don\'t have an account?', style: TextStyle(color: AppTheme.textSecondary)),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const RegisterScreen()),
                  );
                },
                child: const Text(
                  'Register',
                  style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
                );
              },
              icon: const Icon(LucideIcons.shieldAlert, size: 16, color: AppTheme.textSecondary),
              label: const Text(
                'Admin Portal',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // SCREEN 2: Authentication methods selector (PIN, Fingerprint)
  Widget _buildAuthSelectorScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        // Switch account / back button
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _hasIdentified = false;
              });
            },
            icon: const Icon(LucideIcons.arrowLeft, size: 16, color: AppTheme.textSecondary),
            label: const Text('Change Account', style: TextStyle(color: AppTheme.textSecondary)),
          ),
        ),
        const SizedBox(height: 10),
        // User Profile Info
        Center(
          child: CircleAvatar(
            radius: 36,
            backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
            child: const Icon(LucideIcons.user, size: 36, color: AppTheme.primaryColor),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Welcome Back,',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          _fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.shieldCheck, color: AppTheme.primaryDark, size: 13),
                const SizedBox(width: 4),
                Text(
                  _kycTier,
                  style: const TextStyle(color: AppTheme.primaryDark, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),

        // 2-Option Unlock Method Tab Bar
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(child: _buildTabButton(title: 'PIN', icon: LucideIcons.key, index: 0)),
              Expanded(child: _buildTabButton(title: 'Fingerprint', icon: LucideIcons.fingerprint, index: 1)),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Action area depending on selected tab
        _buildActiveAuthMethodView(),

        const SizedBox(height: 24),
        if (_authStatusMessage.isNotEmpty)
          Text(
            _authStatusMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _authStatusMessage.contains('failed') || _authStatusMessage.contains('Incorrect')
                  ? AppTheme.accentRed
                  : AppTheme.textSecondary,
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildTabButton({required String title, required IconData icon, required int index}) {
    final isSelected = _selectedTab == index;
    Color activeColor = AppTheme.primaryColor;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = index;
          _authStatusMessage = '';
          _enteredPin = '';
        });
        if (index == 1) {
          // Trigger fingerprint login automatically after a small delay
          Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted && _selectedTab == 1 && !_isAuthenticating) {
              _authenticateWithFingerprint();
            }
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1.5))]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? activeColor : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? activeColor : AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveAuthMethodView() {
    switch (_selectedTab) {
      case 0:
        // PIN input screen
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final hasVal = _enteredPin.length > index;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasVal ? AppTheme.primaryColor : Colors.grey.shade200,
                    border: !hasVal ? Border.all(color: Colors.grey.shade300, width: 1.5) : null,
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            _buildPinKeyboard(),
          ],
        );
      case 1:
        // Fingerprint screen
        if (!_isFingerprintHardwareAvailable) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                Icon(LucideIcons.fingerprint, size: 56, color: Colors.grey),
                SizedBox(height: 24),
                Text(
                  'this device does not have fingerprint hardware or it is currently unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppTheme.accentRed, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _authenticateWithFingerprint,
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  border: Border.all(color: AppTheme.primaryColor, width: 2),
                ),
                child: const Icon(LucideIcons.fingerprint, size: 56, color: AppTheme.primaryColor),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Tap fingerprint icon or place finger on sensor to unlock',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        );
      default:
        return Container();
    }
  }

  Widget _buildPinKeyboard() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'delete'],
    ];

    return Table(
      children: keys.map((row) {
        return TableRow(
          children: row.map((key) {
            if (key.isEmpty) {
              return const SizedBox.shrink();
            }

            final isDelete = key == 'delete';

            return GestureDetector(
              onTap: () {
                if (_isAuthenticating) return;
                setState(() {
                  if (isDelete) {
                    if (_enteredPin.isNotEmpty) {
                      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
                    }
                  } else {
                    if (_enteredPin.length < 4) {
                      _enteredPin += key;
                      if (_enteredPin.length == 4) {
                        _verifyPin();
                      }
                    }
                  }
                });
              },
              child: Container(
                margin: const EdgeInsets.all(6),
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDelete ? Colors.transparent : Colors.grey.shade50,
                ),
                child: Center(
                  child: isDelete
                      ? const Icon(LucideIcons.delete, size: 20, color: AppTheme.textPrimary)
                      : Text(
                          key,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
