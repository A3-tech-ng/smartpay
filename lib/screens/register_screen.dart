import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons_flutter.dart';
import '../services/supabase_service.dart';
import '../services/biometric_service.dart';
import '../core/theme/app_theme.dart';
import 'home_screen.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String _pin = '';
  bool _isRegistering = false;
  String _registerMessage = 'Creating your secure account...';
  double _registerProgress = 0.0;

  // Realtime Phone Number Verification state
  String _phoneStatus = '';
  String _phoneErrorMessage = '';
  Timer? _phoneValidationDebounce;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneValidationDebounce?.cancel();
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onPhoneChanged() {
    final String val = _phoneController.text.trim();
    if (_phoneValidationDebounce?.isActive ?? false) {
      _phoneValidationDebounce!.cancel();
    }

    if (val.isEmpty) {
      setState(() {
        _phoneStatus = '';
        _phoneErrorMessage = '';
      });
      return;
    }

    // Check format first
    if (val.length != 11) {
      setState(() {
        _phoneStatus = 'invalid_format';
        _phoneErrorMessage = 'Must be exactly 11 digits';
      });
      return;
    }

    if (!val.startsWith('08') && !val.startsWith('09') && !val.startsWith('07')) {
      setState(() {
        _phoneStatus = 'invalid_format';
        _phoneErrorMessage = 'Must start with 07, 08, or 09';
      });
      return;
    }

    if (int.tryParse(val) == null) {
      setState(() {
        _phoneStatus = 'invalid_format';
        _phoneErrorMessage = 'Must contain digits only';
      });
      return;
    }

    // Format is valid! Check availability in Supabase with a 300ms debounce
    setState(() {
      _phoneStatus = 'validating';
      _phoneErrorMessage = 'Checking availability...';
    });

    _phoneValidationDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final profile = await _supabaseService.getProfileByPhoneNumber(val);
        if (!mounted) return;
        setState(() {
          if (profile != null) {
            _phoneStatus = 'taken';
            _phoneErrorMessage = 'This phone number is already registered';
          } else {
            _phoneStatus = 'available';
            _phoneErrorMessage = 'Phone number is available!';
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _phoneStatus = 'error';
          _phoneErrorMessage = 'Error checking phone number availability';
        });
      }
    });
  }

  // Handle registration process
  Future<void> _submitRegistration() async {
    setState(() {
      _isRegistering = true;
      _registerProgress = 0.05;
      _registerMessage = 'Creating secure user profile...';
    });

    final progressTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (mounted) {
        setState(() {
          if (_registerProgress < 0.90) {
            _registerProgress += 0.10;
          }
        });
      } else {
        timer.cancel();
      }
    });

    final String fullName = _nameController.text.trim();
    final String phoneNumber = _phoneController.text.trim();

    // Save Profile to Supabase Auth & public.profiles
    String? registeredUserId;
    try {
      registeredUserId = await _supabaseService.registerUser(
        fullName: fullName,
        phoneNumber: phoneNumber,
        pin: _pin,
      );
    } catch (e) {
      progressTimer.cancel();
      setState(() {
        _isRegistering = false;
      });
      final String errorMsg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration Failed: $errorMsg'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    progressTimer.cancel();
    setState(() {
      _registerProgress = 1.0;
      _isRegistering = false;
    });

    if (registeredUserId != null && mounted) {
      _showSuccessDialog(fullName, registeredUserId);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to retrieve secure profile ID. Please try again.')),
      );
    }
  }

  void _showSuccessDialog(String name, String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.checkCircle,
                  color: AppTheme.primaryColor,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Registration Complete!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Welcome, $name. Your Biometric Payment Gateway account has been secured with Fingerprint and PIN.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close Dialog
                  _promptEnableFingerprint(userId);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Go to Home', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptEnableFingerprint(String userId) async {
    final BiometricService biometricService = BiometricService();
    
    // Check if biometric is available generally
    final bool isAvailable = await biometricService.isBiometricAvailable();
    if (!isAvailable) {
      // Device does not support biometrics generally, skip to home
      _navigateToHome(userId);
      return;
    }
    
    if (!mounted) return;

    // Show Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(LucideIcons.fingerprint, color: AppTheme.primaryColor, size: 28),
              SizedBox(width: 12),
              Text('Enable Fingerprint', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Would you like to enable Fingerprint Login on this device?',
            style: TextStyle(fontSize: 14),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                _navigateToHome(userId); // Navigate to home
              },
              child: const Text('No, Thanks', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog
                await _enableFingerprintAuth(userId);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Enable', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _enableFingerprintAuth(String userId) async {
    final BiometricService biometricService = BiometricService();
    
    // Check if fingerprint hardware is available
    final bool hasHardware = await biometricService.hasFingerprintHardware();
    if (!hasHardware) {
      if (mounted) {
        _showFingerprintErrorDialog(
          title: 'Hardware Unavailable',
          message: 'This device does not have fingerprint hardware or it is currently unavailable.',
          userId: userId,
        );
      }
      return;
    }
    
    // Check if enrolled fingerprints exist
    final bool hasEnrolled = await biometricService.hasEnrolledFingerprints();
    if (!hasEnrolled) {
      if (mounted) {
        _showFingerprintErrorDialog(
          title: 'No Fingerprints Registered',
          message: 'No fingerprints are registered on this device. Please register at least one fingerprint in your device Settings and try again.',
          userId: userId,
        );
      }
      return;
    }
    
    // Launch native prompt to verify
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please authenticate using fingerprint to verify.')),
      );
    }
    
    final bool success = await biometricService.authenticate(userId: userId);
    
    if (success) {
      await biometricService.setBiometricEnabled(userId, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fingerprint login enabled successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fingerprint authentication failed or canceled. Fingerprint login has not been enabled.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    // Always navigate to home after completion
    _navigateToHome(userId);
  }

  void _showFingerprintErrorDialog({required String title, required String message, required String userId}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToHome(userId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _navigateToHome(String userId) {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => HomeScreen(userId: userId)),
      );
    }
  }

  void _validateAndSubmit() {
    if (_formKey.currentState!.validate()) {
      if (_phoneStatus != 'available') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_phoneStatus == 'taken' 
                ? 'This phone number is already registered.' 
                : _phoneStatus == 'validating' 
                    ? 'Checking phone number availability, please wait...' 
                    : 'Please enter a valid, available phone number.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      if (_pin.length != 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please complete your 4-digit security PIN.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      _submitRegistration();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Register',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isRegistering
            ? _buildLoadingState()
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildInfoFormSection(),
                      const SizedBox(height: 24),
                      const Divider(height: 1, color: AppTheme.dividerColor),
                      const SizedBox(height: 24),
                      _buildPinSetupSection(),
                      const SizedBox(height: 32),
                      _buildSubmitButton(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildInfoFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Create your Biometric Payment Gateway Wallet',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your real details. We will secure your funds using advanced biometric encryption.',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 28),
        TextFormField(
          controller: _nameController,
          keyboardType: TextInputType.name,
          decoration: InputDecoration(
            labelText: 'Full Name',
            prefixIcon: const Icon(LucideIcons.user, color: AppTheme.textSecondary),
            filled: true,
            fillColor: AppTheme.backgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your full name';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
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
            final cleanValue = value.trim();
            if (cleanValue.length != 11) {
              return 'Phone number must be exactly 11 digits';
            }
            final startsWithValid = cleanValue.startsWith('08') || 
                                    cleanValue.startsWith('09') || 
                                    cleanValue.startsWith('07');
            if (!startsWithValid) {
              return 'Phone number must start with 07, 08, or 09';
            }
            if (int.tryParse(cleanValue) == null) {
              return 'Phone number must contain digits only';
            }
            if (_phoneStatus == 'taken') {
              return 'This phone number is already registered';
            }
            return null;
          },
        ),
        if (_phoneStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 4.0),
            child: Row(
              children: [
                Icon(
                  _phoneStatus == 'available'
                      ? LucideIcons.checkCircle
                      : _phoneStatus == 'validating'
                          ? LucideIcons.loader
                          : LucideIcons.alertTriangle,
                  size: 14,
                  color: _phoneStatus == 'available'
                      ? Colors.green
                      : _phoneStatus == 'validating'
                          ? Colors.orange
                          : Colors.red,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _phoneErrorMessage,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _phoneStatus == 'available'
                          ? Colors.green
                          : _phoneStatus == 'validating'
                              ? Colors.orange
                              : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPinSetupSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Set 4-Digit Security PIN',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        const Text(
          'This PIN will be used as a backup to unlock your account and authorize transactions.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 32),
        // Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            final hasVal = _pin.length > index;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasVal ? AppTheme.primaryColor : Colors.grey.shade200,
                border: !hasVal ? Border.all(color: Colors.grey.shade300, width: 1.5) : null,
              ),
            );
          }),
        ),
        const SizedBox(height: 40),
        // Custom Numeric Keyboard
        _buildNumericKeyboard(),
      ],
    );
  }

  Widget _buildNumericKeyboard() {
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
                setState(() {
                  if (isDelete) {
                    if (_pin.isNotEmpty) {
                      _pin = _pin.substring(0, _pin.length - 1);
                    }
                  } else {
                    if (_pin.length < 4) {
                      _pin += key;
                    }
                  }
                });
              },
              child: Container(
                margin: const EdgeInsets.all(8),
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDelete ? Colors.transparent : Colors.grey.shade50,
                ),
                child: Center(
                  child: isDelete
                      ? const Icon(LucideIcons.delete, color: AppTheme.textPrimary)
                      : Text(
                          key,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: _validateAndSubmit,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Complete Registration',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(width: 8),
          Icon(
            LucideIcons.shieldCheck,
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 110,
              width: 110,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _registerProgress,
                    strokeWidth: 6,
                    color: AppTheme.primaryColor,
                    backgroundColor: Colors.grey.shade200,
                  ),
                  Text(
                    '${(_registerProgress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _registerMessage,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            const Text(
              'Please do not close the app. We are hashing credentials and setting up security.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
