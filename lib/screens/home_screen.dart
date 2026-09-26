import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/theme/app_theme.dart';
import '../core/config.dart';
import '../services/supabase_service.dart';
import '../services/biometric_service.dart';
import 'login_screen.dart';


class HomeScreen extends StatefulWidget {
  final String userId;
  const HomeScreen({Key? key, this.userId = 'user_john_doe'}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final SupabaseService _supabaseService = SupabaseService();
  final ImagePicker _picker = ImagePicker();
  final BiometricService _biometricService = BiometricService();
  bool _isBalanceVisible = true;
  int _currentTabIndex = 0;
  Map<String, dynamic>? _profile;
  bool _isLoadingProfile = true;
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoadingTransactions = true;
  bool _fingerprintEnabled = false;
  double _transactionProgress = 0.0;
  bool _isAwardingReward = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    final prefs = await SharedPreferences.getInstance();
    if (state == AppLifecycleState.paused) {
      // User is exiting / backgrounding the app, mark last active timestamp
      await prefs.setInt('last_active_time', DateTime.now().millisecondsSinceEpoch);
    } else if (state == AppLifecycleState.resumed) {
      // User returned to the app, check if they were out for >= 5 minutes
      final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      if (isLoggedIn) {
        final int lastActive = prefs.getInt('last_active_time') ?? 0;
        final int now = DateTime.now().millisecondsSinceEpoch;
        final int diff = now - lastActive;

        if (lastActive > 0 && diff >= 5 * 60 * 1000) {
          // Log out user
          await prefs.setBool('is_logged_in', false);
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Session timed out. Please log in again.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        } else {
          // Update last active time to now since they are active again
          await prefs.setInt('last_active_time', now);
          _loadUserProfile();
        }
      }
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final profileData = await _supabaseService.getUserProfile(widget.userId);
      final transactionData = await _supabaseService.getRecentTransactions(widget.userId);
      final fingerprintEnabled = await _biometricService.isBiometricEnabled(widget.userId);
      setState(() {
        _profile = profileData;
        _transactions = transactionData;
        _fingerprintEnabled = fingerprintEnabled;
        _isLoadingProfile = false;
        _isLoadingTransactions = false;
      });
      _checkAndAwardDailyReward(transactionData);
    } catch (e) {
      setState(() {
        _isLoadingProfile = false;
        _isLoadingTransactions = false;
      });
    }
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return '0.00';
    double amount = 0.0;
    if (value is num) {
      amount = value.toDouble();
    } else if (value is String) {
      amount = double.tryParse(value) ?? 0.0;
    }
    
    final RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String valueStr = amount.toStringAsFixed(2);
    List<String> parts = valueStr.split('.');
    parts[0] = parts[0].replaceAllMapped(reg, (Match m) => '${m[1]},');
    return parts.join('.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: _buildTabBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildTabBody() {
    switch (_currentTabIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildRewardsTab();
      case 2:
        return _buildFinanceTab();
      case 3:
        return _buildCardsTab();
      case 4:
        return _buildProfileTab();
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildHomeTab() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        _buildAppBar(),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBalanceCard(),
                const SizedBox(height: 16),
                _buildPrimaryActionsCard(),
                const SizedBox(height: 16),
                _buildActionGrid(),
                const SizedBox(height: 16),
                _buildPromoBanner(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Helper to load profile image from base64 or network URL
  ImageProvider? _getProfileImageProvider(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('data:image')) {
      try {
        final String base64Content = url.split(',').last;
        return MemoryImage(base64Decode(base64Content));
      } catch (e) {
        return null;
      }
    }
    return NetworkImage(url);
  }

  // Profile Picture Upload Bottom Sheet
  Future<void> _updateProfilePicture() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(LucideIcons.camera, color: AppTheme.primaryColor),
                title: const Text('Take Profile Photo (Camera)'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSaveProfilePicture(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.image, color: AppTheme.primaryColor),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSaveProfilePicture(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.dice5, color: AppTheme.primaryColor),
                title: const Text('Generate Random Avatar'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSaveProfilePicture(null);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndSaveProfilePicture(ImageSource? source) async {
    try {
      String? dataUrl;
      if (source == null) {
        final int rand = DateTime.now().millisecondsSinceEpoch;
        dataUrl = 'https://api.dicebear.com/7.x/adventurer/png?seed=User$rand';
      } else {
        final XFile? picked = await _picker.pickImage(
          source: source,
          maxWidth: 300,
          maxHeight: 300,
          imageQuality: 80,
        );
        if (picked == null) return;
        final File file = File(picked.path);
        final bytes = await file.readAsBytes();
        final base64String = base64Encode(bytes);
        dataUrl = 'data:image/jpeg;base64,$base64String';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updating profile picture...')),
      );

      await _supabaseService.client.from('profiles').update({
        'profile_picture_url': dataUrl,
      }).eq('user_id', widget.userId);

      _loadUserProfile();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating profile picture: $e')),
      );
    }
  }

  // --- APP BAR ACTIONS HELPERS ---
  void _showNotificationsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('All notifications marked as read')),
                        );
                        Navigator.pop(context);
                      },
                      child: const Text('Mark all read', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: _transactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.bellOff, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            const Text('No notifications yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                          ],
                        ),
                      )
                    : ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        children: [
                          _buildNotificationItem(
                            icon: LucideIcons.shieldAlert,
                            iconColor: Colors.orange,
                            bgColor: Colors.orange.shade50,
                            title: 'Biometric Access Secured',
                            body: 'Fingerprint verification successfully validated during active session.',
                            time: 'Just now',
                          ),
                          ..._transactions.map((tx) {
                            final bool isDebit = tx['is_debit'] ?? false;
                            return _buildNotificationItem(
                              icon: isDebit ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft,
                              iconColor: isDebit ? Colors.red : Colors.green,
                              bgColor: isDebit ? Colors.red.shade50 : Colors.green.shade50,
                              title: tx['title'] ?? 'Transaction Alert',
                              body: '${tx['subtitle'] ?? ''} - Amount: ${tx['amount'] ?? ''}',
                              time: 'Today',
                            );
                          }).toList(),
                          _buildNotificationItem(
                            icon: LucideIcons.partyPopper,
                            iconColor: AppTheme.primaryColor,
                            bgColor: AppTheme.primaryColor.withOpacity(0.08),
                            title: 'Welcome to Biometric Payment Gateway',
                            body: 'Start sending transfers, saving in Safebox, or request a quick cash loan!',
                            time: '1 day ago',
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationItem({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String body,
    required String time,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                    ),
                    Text(
                      time,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSupportBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Biometric Gateway Live Support',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(LucideIcons.sparkles, color: Colors.amber, size: 18),
                              SizedBox(width: 8),
                              Text('AI Concierge active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Need immediate resolution on transactions, loans, or transfers?',
                            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F172A),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(LucideIcons.messageCircle, size: 16),
                            label: const Text('Start Chat', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.pop(context);
                              _startLiveChatDialog();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Frequently Asked Questions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),
                    _buildFAQItem('How long does a bank transfer take?', 'Transfers from Biometric Gateway to other banks are instant and settle in seconds.'),
                    _buildFAQItem('What are the loan interest rates?', 'Biometric Gateway loans are disbursed with a competitive rate of 5.5% fixed interest per month.'),
                    _buildFAQItem('How does Safebox savings work?', 'Safebox is a wallet vault that locks savings away from daily expenses, helping you compound interest.'),
                    const SizedBox(height: 24),
                    const Text('Direct Lines', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0.5,
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                          child: const Icon(LucideIcons.phoneCall, color: AppTheme.primaryColor, size: 18),
                        ),
                        title: const Text('+234 800-BIOMETRIC', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Emergency support lines (Toll Free)'),
                        trailing: const Icon(LucideIcons.chevronRight, size: 16),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Calling Biometric Payment Gateway support line...')),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFAQItem(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ExpansionTile(
        title: Text(question, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Text(answer, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4)),
          ),
        ],
      ),
    );
  }

  void _startLiveChatDialog() {
    final TextEditingController chatController = TextEditingController();
    final List<Map<String, dynamic>> messages = [
      {'isUser': false, 'text': 'Hello! I am your Biometric Gateway Assistant. How can I help you today?'},
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setChatState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: EdgeInsets.zero,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.white,
                            radius: 16,
                            child: Icon(LucideIcons.sparkles, color: AppTheme.primaryColor, size: 18),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Support Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                SizedBox(height: 2),
                                Text('Online - AI Agent', style: TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final bool isUser = msg['isUser'] ?? false;
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isUser ? AppTheme.primaryColor : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isUser ? 16 : 0),
                                  bottomRight: Radius.circular(isUser ? 0 : 16),
                                ),
                              ),
                              child: Text(
                                msg['text'] ?? '',
                                style: TextStyle(color: isUser ? Colors.white : AppTheme.textPrimary, fontSize: 13, height: 1.4),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: chatController,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Type your message...',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppTheme.primaryColor)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final text = chatController.text.trim();
                              if (text.isEmpty) return;
                              setChatState(() {
                                messages.add({'isUser': true, 'text': text});
                                chatController.clear();
                              });

                              Future.delayed(const Duration(milliseconds: 600), () {
                                String reply = 'Thank you for reaching out! A ticket has been raised with ID #${DateTime.now().millisecondsSinceEpoch % 1000000}. Our team is reviewing this.';
                                if (text.toLowerCase().contains('loan')) {
                                  reply = 'To get a loan, simply tap "Cash Loan" on the Home Screen. You can apply for up to ₦150,000 instantly.';
                                } else if (text.toLowerCase().contains('transfer')) {
                                  reply = 'If a transfer is pending, please share the transaction reference from the transaction receipt or wait 5 minutes.';
                                } else if (text.toLowerCase().contains('safebox')) {
                                  reply = 'Safebox allows you to lock money. Select "Safebox" on the Home Screen to move funds or withdraw them back to your wallet.';
                                }
                                setChatState(() {
                                  messages.add({'isUser': false, 'text': reply});
                                });
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle),
                              child: const Icon(LucideIcons.send, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showQRScanBottomSheet() {
    final String accountNo = _profile?['account_no'] ?? 'N/A';
    final String fullName = _profile?['full_name'] ?? 'Biometric Gateway User';
    // QR data format: biometricgateway://<account_no>/<full_name>
    final String qrData = 'biometricgateway://$accountNo/$fullName';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _QRBottomSheet(
          accountNo: accountNo,
          fullName: fullName,
          qrData: qrData,
          onAccountScanned: (scannedAccountNo, scannedName) {
            Navigator.pop(context);
            _showScannedAccountDialog(scannedAccountNo, scannedName);
          },
        );
      },
    );
  }

  void _showScannedAccountDialog(String accountNo, String name) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.checkCircle2, color: AppTheme.primaryColor, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'QR Code Scanned',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Account details found',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.user, size: 18, color: Colors.grey.shade500),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Account Name', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            const SizedBox(height: 2),
                            Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Icon(LucideIcons.creditCard, size: 18, color: Colors.grey.shade500),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Account Number', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            const SizedBox(height: 2),
                            Text(accountNo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                          ],
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: accountNo));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Account number copied!')),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(LucideIcons.copy, size: 16, color: AppTheme.primaryColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: AppTheme.primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Close', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showTransferBottomSheet();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Send Money', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppTheme.cardColor,
      pinned: true,
      elevation: 0.5,
      title: Row(
        children: [
          GestureDetector(
            onTap: _updateProfilePicture,
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.cardColor,
                    backgroundImage: _getProfileImageProvider(_profile?['profile_picture_url']),
                    child: _getProfileImageProvider(_profile?['profile_picture_url']) == null
                        ? const Icon(LucideIcons.user, color: AppTheme.textSecondary, size: 20)
                        : null,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.cardColor, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Hi, ${_profile?['full_name']?.split(' ')[0] ?? 'User'}',
            style: const TextStyle(
              fontSize: 16, 
              fontWeight: FontWeight.bold, 
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.refreshCw, color: AppTheme.textSecondary, size: 20),
          onPressed: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Refreshing wallet data...'),
                duration: Duration(milliseconds: 1000),
              ),
            );
            await _loadUserProfile();
          },
          tooltip: 'Refresh Wallet Data',
        ),
        IconButton(
          icon: const Icon(LucideIcons.headphones, color: AppTheme.textSecondary, size: 22),
          onPressed: _showSupportBottomSheet,
          tooltip: 'Customer Support',
        ),
        IconButton(
          icon: const Icon(LucideIcons.scanLine, color: AppTheme.textSecondary, size: 22),
          onPressed: _showQRScanBottomSheet,
          tooltip: 'Scan QR Code',
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(LucideIcons.bell, color: AppTheme.textSecondary, size: 22),
              onPressed: _showNotificationsBottomSheet,
              tooltip: 'Notifications',
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryColor],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Available Balance & Transaction History
          Row(
            children: [
              const Icon(LucideIcons.shieldCheck, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              const Text(
                'Available Balance',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isBalanceVisible = !_isBalanceVisible;
                  });
                },
                child: Icon(
                  _isBalanceVisible ? LucideIcons.eye : LucideIcons.eyeOff,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _showTransactionHistoryBottomSheet,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Transaction History',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(width: 2),
                    Icon(LucideIcons.chevronRight, color: Colors.white, size: 14),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Row 2: Amount & Add Money Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Balance text with caret
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _isBalanceVisible ? '₦${_formatCurrency(_profile?['balance'])}' : '₦ ****',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(LucideIcons.chevronRight, color: Colors.white, size: 20),
                ],
              ),
              // Add Money Button
              ElevatedButton.icon(
                onPressed: _showAddMoneyBottomSheet,
                icon: const Icon(LucideIcons.plus, color: AppTheme.primaryColor, size: 14),
                label: const Text(
                  'Add Money',
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryActionsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildPrimaryActionButton(
            icon: LucideIcons.userCheck,
            title: 'To Gateway',
            onTap: _showTransferBottomSheet,
          ),
          _buildPrimaryActionButton(
            icon: LucideIcons.landmark,
            title: 'To Bank',
            onTap: _showBankTransferBottomSheet,
          ),
          _buildPrimaryActionButton(
            icon: LucideIcons.arrowUpRight,
            title: 'Withdraw',
            onTap: _showWithdrawBottomSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryActionButton({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1), // light Indigo bg
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: AppTheme.primaryColor, // Indigo icon
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Row 1
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildServiceItem(LucideIcons.smartphone, 'Airtime', AppTheme.primaryColor),
              _buildServiceItem(
                LucideIcons.repeat, 
                'Data', 
                AppTheme.primaryColor, 
                badge: 'Up to 6%',
              ),
              _buildServiceItem(LucideIcons.activity, 'Betting', AppTheme.primaryColor),
              _buildServiceItem(LucideIcons.tv, 'TV', AppTheme.primaryColor),
            ],
          ),
          const SizedBox(height: 20),
          // Row 2
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildServiceItem(LucideIcons.wallet, 'Safebox', AppTheme.primaryColor),
              _buildServiceItem(LucideIcons.coins, 'Loan', AppTheme.primaryColor),
              _buildServiceItem(LucideIcons.gift, 'Refer & Earn', AppTheme.primaryColor),
              _buildServiceItem(LucideIcons.layoutGrid, 'More', AppTheme.primaryColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServiceItem(IconData icon, String label, Color color, {String? badge}) {
    return InkWell(
      onTap: () => _onServiceItemTap(label),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9), // light grey background
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: color, // modern icon color
                    size: 22,
                  ),
                ),
                if (badge != null)
                  Positioned(
                    top: -8,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444), // red badge
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF334155),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoBanner() {
    return GestureDetector(
      onTap: _showReferAndEarnDialog,
      child: Container(
        padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9), // light grey background
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.megaphone,
                  color: AppTheme.primaryColor, // Indigo megaphone
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cash up for grabs!',
                      style: TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Invite friends and earn up to ₦5,600 Bonus',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Carousel Indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 3,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ],
      ),
    ),);
  }

  Widget _buildRecentTransactions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Transactions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              InkWell(
                onTap: _loadUserProfile,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                  child: Row(
                    children: [
                      Text(
                        'Refresh',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                      ),
                      SizedBox(width: 4),
                      Icon(LucideIcons.refreshCw, size: 14, color: AppTheme.primaryColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingTransactions)
            const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          else if (_transactions.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No transactions yet.', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _transactions.length,
              separatorBuilder: (context, index) => const Divider(height: 24, color: AppTheme.dividerColor),
              itemBuilder: (context, index) {
                final tx = _transactions[index];
                final String title = tx['title'] ?? 'Transfer';
                final String subtitle = tx['subtitle'] ?? 'Biometric Payment Gateway';
                final String amount = tx['amount'] ?? '0.00';
                final bool isDebit = tx['is_debit'] ?? true;
                final String status = tx['status'] ?? 'Successful';

                IconData txIcon = LucideIcons.arrowUpRight;
                Color txIconColor = AppTheme.accentRed;

                if (!isDebit) {
                  txIcon = LucideIcons.arrowDownLeft;
                  txIconColor = AppTheme.primaryColor;
                } else if (title.contains('Airtime')) {
                  txIcon = LucideIcons.phoneCall;
                  txIconColor = Colors.blue;
                }

                return _buildTransactionItem(
                  title: title,
                  subtitle: subtitle,
                  amount: amount,
                  isDebit: isDebit,
                  icon: txIcon,
                  iconColor: txIconColor,
                  status: status,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem({
    required String title,
    required String subtitle,
    required String amount,
    required bool isDebit,
    required IconData icon,
    required Color iconColor,
    required String status,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(
                        color: AppTheme.primaryDark,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isDebit ? AppTheme.textPrimary : AppTheme.primaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.cardColor,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.textSecondary,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        currentIndex: _currentTabIndex,
        onTap: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.trendingUp), label: 'Rewards'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.pieChart), label: 'Finance'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.creditCard), label: 'Cards'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.user), label: 'Me'),
        ],
      ),
    );
  }

  // Helper to count non-reward transactions today
  int _getTodayTransactionsCount() {
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    return _transactions.where((tx) {
      final String? createdAt = tx['created_at'];
      if (createdAt == null) return false;
      return createdAt.startsWith(todayStr) && tx['title'] != 'Daily Transaction Reward';
    }).length;
  }

  // Helper to check if today's reward has been claimed
  bool _isDailyRewardAwarded() {
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    return _transactions.any((tx) {
      final String? createdAt = tx['created_at'];
      if (createdAt == null) return false;
      return createdAt.startsWith(todayStr) && tx['title'] == 'Daily Transaction Reward';
    });
  }

  // Parse transaction formatted text amount to double
  double _parseTransactionAmount(String amountStr) {
    final clean = amountStr.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  // Group inflow or outflow sums
  double _getFinanceSummary({required bool getDebit}) {
    double total = 0.0;
    for (var tx in _transactions) {
      final bool isDebit = tx['is_debit'] ?? false;
      if (isDebit == getDebit) {
        total += _parseTransactionAmount(tx['amount'] ?? '');
      }
    }
    return total;
  }

  // Reward Checker Logic triggered automatically
  Future<void> _checkAndAwardDailyReward(List<Map<String, dynamic>> transactions) async {
    if (_isAwardingReward) return;

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    
    // Check if the user already received the reward today
    final alreadyReceived = transactions.any((tx) {
      final String? createdAt = tx['created_at'];
      if (createdAt == null) return false;
      return createdAt.startsWith(todayStr) && tx['title'] == 'Daily Transaction Reward';
    });
    
    if (alreadyReceived) return;
    
    // Count transactions today (excluding the reward itself)
    final todayTxnsCount = transactions.where((tx) {
      final String? createdAt = tx['created_at'];
      if (createdAt == null) return false;
      return createdAt.startsWith(todayStr) && tx['title'] != 'Daily Transaction Reward';
    }).length;
    
    if (todayTxnsCount >= 3) {
      setState(() {
        _isAwardingReward = true;
      });

      try {
        final profile = _profile;
        if (profile == null) return;
        final double currentBalance = (profile['balance'] as num? ?? 0.0).toDouble();
        final double newBalance = currentBalance + 100.00;
        
        // 1. Update profiles table
        await _supabaseService.client.from('profiles').update({
          'balance': newBalance,
        }).eq('user_id', widget.userId);
        
        // 2. Insert transaction entry
        await _supabaseService.client.from('transactions').insert({
          'user_id': widget.userId,
          'title': 'Daily Transaction Reward',
          'subtitle': 'Completed 3 transactions today',
          'amount': '+ ₦100.00',
          'is_debit': false,
          'status': 'Successful',
          'created_at': DateTime.now().toIso8601String(),
        });
        
        if (mounted) {
          _showRewardCelebrationDialog();
          _loadUserProfile();
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error awarding daily transaction reward: $e');
        }
      } finally {
        setState(() {
          _isAwardingReward = false;
        });
      }
    }
  }

  void _showRewardCelebrationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.partyPopper, size: 64, color: Colors.amber),
              ),
              const SizedBox(height: 24),
              const Text(
                'Congratulations!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'You have successfully completed 3 transactions today!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade100),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.coins, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '+ ₦100.00 Added',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
                child: const Text('Awesome!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRewardsTab() {
    final int todayCount = _getTodayTransactionsCount();
    final bool rewarded = _isDailyRewardAwarded();
    final double progressPercent = (todayCount / 3).clamp(0.0, 1.0);
    
    // Get reward history
    final rewardHistory = _transactions.where((tx) => tx['title'] == 'Daily Transaction Reward').toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Biometric Gateway Rewards', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppTheme.cardColor,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Daily Streak Progress Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Daily Transaction Goal',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          rewarded ? 'Goal Met!' : 'Active',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rewarded 
                      ? '₦100 rewarded to your wallet balance!' 
                      : 'Complete 3 transactions in a day to earn ₦100 instantly.',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$todayCount of 3 completed',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${(progressPercent * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progressPercent,
                      backgroundColor: Colors.white.withOpacity(0.15),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Winnings List
            const Text(
              'Reward Earnings History',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            rewardHistory.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: Column(
                      children: [
                        Icon(LucideIcons.award, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        const Text(
                          'No rewards claimed yet today.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Transactions reset daily at midnight.',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: rewardHistory.map((tx) {
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: AppTheme.dividerColor),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade50,
                            child: const Icon(LucideIcons.gift, color: Colors.green, size: 20),
                          ),
                          title: Text(tx['title'] ?? 'Reward', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(tx['subtitle'] ?? 'Promo Bonus', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          trailing: const Text(
                            '+ ₦100.00',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: 24),
            
            // Invite Friends Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.users, color: AppTheme.primaryColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Refer & Earn',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Invite friends and earn ₦500 per signup.',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'BIOMETRIC-500K',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontSize: 14, letterSpacing: 1),
                        ),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(const ClipboardData(text: 'BIOMETRIC-500K'));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Referral code copied to clipboard!')),
                            );
                          },
                          child: const Row(
                            children: [
                              Icon(LucideIcons.copy, size: 14, color: AppTheme.primaryColor),
                              SizedBox(width: 4),
                              Text(
                                'Copy',
                                style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceTab() {
    final double totalInflow = _getFinanceSummary(getDebit: false);
    final double totalOutflow = _getFinanceSummary(getDebit: true);

    // Get last 6 transactions to plot in chart
    final chartTxns = _transactions.take(6).toList().reversed.toList();
    
    // Find maximum amount for chart scaling
    double maxAmount = 1000.0;
    for (var tx in chartTxns) {
      final amt = _parseTransactionAmount(tx['amount'] ?? '');
      if (amt > maxAmount) maxAmount = amt;
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Finance Analyzer', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppTheme.cardColor,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cashflow Overview Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Monthly Cashflow Summary',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(LucideIcons.arrowDownLeft, color: Colors.green, size: 14),
                                ),
                                const SizedBox(width: 8),
                                const Text('Total Inflow', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₦${_formatCurrency(totalInflow)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: AppTheme.dividerColor),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(LucideIcons.arrowUpRight, color: Colors.red, size: 14),
                                ),
                                const SizedBox(width: 8),
                                const Text('Total Outflow', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₦${_formatCurrency(totalOutflow)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Bar Chart Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Transaction Amount History',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 24),
                  chartTxns.isEmpty
                      ? Container(
                          height: 150,
                          alignment: Alignment.center,
                          child: const Text('No transactions to plot.', style: TextStyle(color: AppTheme.textSecondary)),
                        )
                      : Column(
                          children: [
                            // Chart Bars
                            SizedBox(
                              height: 160,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: chartTxns.map((tx) {
                                  final double amount = _parseTransactionAmount(tx['amount'] ?? '');
                                  final bool isDebit = tx['is_debit'] ?? false;
                                  
                                  final double normalizedHeight = (amount / maxAmount) * 130;
                                  final double barHeight = normalizedHeight.clamp(12.0, 130.0);
                                  
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        '₦${amount >= 1000 ? (amount / 1000).toStringAsFixed(1) + "k" : amount.toStringAsFixed(0)}',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isDebit ? Colors.red : Colors.green),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        width: 18,
                                        height: barHeight,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: isDebit 
                                              ? [Colors.red.shade400, Colors.red.shade600]
                                              : [Colors.green.shade400, Colors.green.shade600],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Icon(
                                        isDebit ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft,
                                        size: 10,
                                        color: isDebit ? Colors.red : Colors.green,
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                            const Divider(height: 24),
                            // X-Axis Labels
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: chartTxns.map((tx) {
                                final String title = tx['title'] ?? '';
                                final String shortTitle = title.length > 8 ? title.substring(0, 7) + '.' : title;
                                return SizedBox(
                                  width: 45,
                                  child: Text(
                                    shortTitle,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 8, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Financial Advice Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.1)),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.lightbulb, color: AppTheme.primaryColor, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tip: Move your surplus balance to Safebox to secure locked high-yield interests and limit impulse outflow.',
                      style: TextStyle(color: AppTheme.primaryDark, fontSize: 11, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardsTab() {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('SmartCards', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppTheme.cardColor,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Premium card mockup
              Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 0.65,
                    child: Container(
                      width: 320,
                      height: 190,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF334155)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Biometric Gateway Visa',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                              ),
                              Icon(LucideIcons.contact, color: Colors.amber.shade200, size: 28),
                            ],
                          ),
                          const Text(
                            '••••  ••••  ••••  ••••',
                            style: TextStyle(color: Colors.white70, fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.bold),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _profile?['full_name']?.toString().toUpperCase() ?? 'BIOMETRIC USER',
                                style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1),
                              ),
                              const Text(
                                '00 / 00',
                                style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Coming Soon Glass Card Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.clock, color: AppTheme.primaryColor, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Coming Soon',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              const Text(
                'Personalized Virtual & Physical Cards',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 12),
              const Text(
                'We are preparing physical and virtual Visa cards linked directly to your wallet balance. Shop globally with zero-fee transactions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    if (_isLoadingProfile) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }

    final String name = _profile?['full_name'] ?? 'Biometric Gateway User';
    final String phone = _profile?['phone_number'] ?? '';
    final String accountNo = _profile?['account_no'] ?? 'Not Assigned';
    final String kycTier = _profile?['kyc_tier'] ?? 'Tier 3 Verified';
    final String profilePic = _profile?['profile_picture_url'] ?? 'https://api.dicebear.com/7.x/adventurer/png?seed=BiometricGateway';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Me', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppTheme.cardColor,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // User Header Info Card
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: _updateProfilePicture,
                          child: Container(
                            padding: const EdgeInsets.all(4), // outer theme ring
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: _getProfileImageProvider(_profile?['profile_picture_url']),
                              child: _getProfileImageProvider(_profile?['profile_picture_url']) == null
                                  ? const Icon(LucideIcons.user, color: Colors.grey, size: 48)
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: GestureDetector(
                            onTap: _updateProfilePicture,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.camera, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    phone,
                    style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  // KYC Status Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.shieldCheck, color: AppTheme.primaryColor, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          kycTier,
                          style: const TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Account Number Display Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF6366F1)], // Indigo Gradient
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Biometric Gateway Account',
                              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              accountNo,
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                            ),
                          ],
                        ),
                        Material(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: accountNo));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Account number copied to clipboard!')),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(10.0),
                              child: Icon(LucideIcons.copy, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Settings Section: Biometrics & Security
            _buildSettingsGroup(
              title: 'Security & Biometrics',
              items: [
                _buildSettingsTile(
                  icon: LucideIcons.fingerprint,
                  title: 'Fingerprint Lock',
                  subtitle: 'Use system enrolled fingerprint to secure access',
                  trailing: Switch(
                    value: _fingerprintEnabled,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) async {
                      if (val) {
                        // User wants to enable fingerprint
                        // 1. Check hardware availability
                        final bool hasHardware = await _biometricService.hasFingerprintHardware();
                        if (!hasHardware) {
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: const Text('Hardware Unavailable', style: TextStyle(fontWeight: FontWeight.bold)),
                                content: const Text('This device does not have fingerprint hardware or it is currently unavailable.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                          return;
                        }

                        // 2. Check enrolled fingerprint
                        final bool hasEnrolled = await _biometricService.hasEnrolledFingerprints();
                        if (!hasEnrolled) {
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: const Text('No Fingerprints Registered', style: TextStyle(fontWeight: FontWeight.bold)),
                                content: const Text('No fingerprints are registered on this device. Please register at least one fingerprint in your device Settings first.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                          return;
                        }

                        // 3. Authenticate to confirm
                        final bool success = await _biometricService.authenticate(userId: widget.userId);
                        if (success) {
                          await _biometricService.setBiometricEnabled(widget.userId, true);
                          setState(() {
                            _fingerprintEnabled = true;
                          });
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
                                content: Text('Authentication failed or canceled.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } else {
                        // User wants to disable fingerprint
                        await _biometricService.setBiometricEnabled(widget.userId, false);
                        setState(() {
                          _fingerprintEnabled = false;
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Fingerprint login disabled.'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),

                _buildSettingsTile(
                  icon: LucideIcons.lock,
                  title: 'Reset Security PIN',
                  subtitle: 'Change your 4-digit transactions & login PIN',
                  onTap: _changePinDialog,
                  trailing: const Icon(LucideIcons.chevronRight, size: 18, color: Colors.grey),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Settings Section: Preferences
            _buildSettingsGroup(
              title: 'Preferences',
              items: [
                _buildSettingsTile(
                  icon: LucideIcons.bell,
                  title: 'Push Notifications',
                  subtitle: 'Alerts for transaction status & updates',
                  trailing: Switch(
                    value: true,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) {},
                  ),
                ),

              ],
            ),

            const SizedBox(height: 12),

            // Settings Section: Support & Exit
            _buildSettingsGroup(
              title: 'Support & Options',
              items: [
                _buildSettingsTile(
                  icon: LucideIcons.helpCircle,
                  title: 'Contact Help Center',
                  subtitle: '24/7 live assistance for account inquiries',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Connecting to Customer Support...')),
                    );
                  },
                ),
                _buildSettingsTile(
                  icon: LucideIcons.logOut,
                  iconColor: Colors.redAccent,
                  title: 'Log Out',
                  titleColor: Colors.redAccent,
                  subtitle: 'Sign out of the current secure session',
                  onTap: _logout,
                ),
                _buildSettingsTile(
                  icon: LucideIcons.trash2,
                  iconColor: Colors.red,
                  title: 'Delete Account',
                  titleColor: Colors.red,
                  subtitle: 'Permanently close and delete your account',
                  onTap: _showDeleteAccountConfirmation,
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsGroup({required String title, required List<Widget> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 1.0),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFF1F5F9)),
              bottom: BorderSide(color: Color(0xFFF1F5F9)),
            ),
          ),
          child: Column(
            children: items,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    Color iconColor = AppTheme.primaryColor,
    required String title,
    Color titleColor = AppTheme.textPrimary,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: titleColor),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }



  Future<void> _changePinDialog() async {
    final TextEditingController pinController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reset Security PIN', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter a new 4-digit PIN for securing transactions and app login verification.',
                  style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '••••',
                    counterText: '',
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.length != 4 || int.tryParse(val) == null) {
                      return 'Must be exactly 4 digits';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final String newPin = pinController.text;
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Updating security PIN...')),
                  );

                  final success = await _supabaseService.updatePin(widget.userId, newPin);

                  if (success) {
                    setState(() {
                      if (_profile != null) {
                        _profile!['pin'] = newPin;
                      }
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Security PIN updated successfully!')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to update PIN. Try again.')),
                    );
                  }
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }



  void _showTransferBottomSheet() {
    final TextEditingController accountController = TextEditingController();
    final TextEditingController amountController = TextEditingController();
    final TextEditingController pinController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    String? recipientName;
    bool isResolving = false;
    bool isSubmitting = false;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Send to Biometric Gateway Account',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Account Number input
                      TextFormField(
                        controller: accountController,
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        decoration: InputDecoration(
                          labelText: 'Account Number',
                          hintText: 'Enter 10-digit number',
                          counterText: '',
                          prefixIcon: const Icon(LucideIcons.user, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (val) async {
                          if (val.length == 10) {
                            setModalState(() {
                              isResolving = true;
                              recipientName = null;
                              errorMessage = null;
                            });

                            final profile = await _supabaseService.getProfileByAccountNo(val);
                            
                            setModalState(() {
                              isResolving = false;
                              if (profile != null) {
                                recipientName = profile['full_name'];
                              } else {
                                errorMessage = 'Account number not found';
                              }
                            });
                          } else {
                            setModalState(() {
                              recipientName = null;
                              errorMessage = null;
                            });
                          }
                        },
                        validator: (val) {
                          if (val == null || val.length != 10) {
                            return 'Enter a valid 10-digit account number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Resolve info text
                      if (isResolving)
                        const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                            ),
                            SizedBox(width: 8),
                            Text('Resolving recipient...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      if (recipientName != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4), // green 50
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBBF7D0)), // green 200
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Recipient: $recipientName',
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      if (errorMessage != null)
                        Text(
                          errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      const SizedBox(height: 16),

                      // Amount input
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount (₦)',
                          hintText: '0.00',
                          prefixIcon: const Icon(LucideIcons.coins, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Please enter an amount';
                          }
                          final amt = double.tryParse(val);
                          if (amt == null || amt <= 0) {
                            return 'Enter a positive amount';
                          }
                          final balance = (_profile?['balance'] as num?)?.toDouble() ?? 0.0;
                          if (amt > balance) {
                            return 'Insufficient balance (Balance: ₦${_formatCurrency(balance)})';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // PIN input
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: pinController,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              maxLength: 4,
                              decoration: InputDecoration(
                                labelText: 'Transaction PIN',
                                hintText: '••••',
                                counterText: '',
                                prefixIcon: const Icon(LucideIcons.lock, size: 20),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.length != 4 || int.tryParse(val) == null) {
                                  return 'Enter your 4-digit PIN';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            height: 54,
                            width: 54,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
                            ),
                            child: IconButton(
                              icon: const Icon(LucideIcons.fingerprint, color: AppTheme.primaryColor, size: 24),
                              tooltip: 'Verify with Fingerprint',
                              onPressed: () async {
                                final bool isFingerprintVerified = await _biometricService.authenticate(userId: widget.userId);
                                if (isFingerprintVerified && _profile != null) {
                                  setModalState(() {
                                    pinController.text = _profile?['pin'] ?? '';
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Submit button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: (isSubmitting || isResolving || recipientName == null)
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setModalState(() {
                                    isSubmitting = true;
                                  });

                                  final double amt = double.parse(amountController.text);
                                  final String targetAcc = accountController.text;
                                  final String pin = pinController.text;

                                  final result = await _supabaseService.transferFunds(
                                    senderUserId: widget.userId,
                                    receiverAccountNo: targetAcc,
                                    amount: amt,
                                    pin: pin,
                                  );

                                  if (mounted) {
                                    Navigator.pop(context); // Close bottom sheet
                                    if (result == null) {
                                      // Success! Show Receipt overlay and reload data
                                      _showReceiptDialog(
                                        recipientName: recipientName!,
                                        accountNo: targetAcc,
                                        amount: amt,
                                      );
                                      _loadUserProfile();
                                    } else {
                                      // Error
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Transfer failed: $result'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Confirm Transfer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showTransactionHistoryBottomSheet() {
    String searchQuery = '';
    String selectedFilter = 'All'; // 'All', 'Inflows', 'Outflows'

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _supabaseService.getAllTransactions(widget.userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.85,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryColor),
                ),
              );
            }

            final List<Map<String, dynamic>> allTxs = snapshot.data ?? [];

            return StatefulBuilder(
              builder: (context, setSheetState) {
                // Apply filtering logic on the transactions list
                final filteredTxs = allTxs.where((tx) {
                  final title = (tx['title'] ?? '').toString().toLowerCase();
                  final subtitle = (tx['subtitle'] ?? '').toString().toLowerCase();
                  final amount = (tx['amount'] ?? '').toString().toLowerCase();
                  final matchesSearch = title.contains(searchQuery.toLowerCase()) ||
                      subtitle.contains(searchQuery.toLowerCase()) ||
                      amount.contains(searchQuery.toLowerCase());

                  final bool isDebit = tx['is_debit'] ?? false;
                  if (selectedFilter == 'Inflows') {
                    return matchesSearch && !isDebit;
                  } else if (selectedFilter == 'Outflows') {
                    return matchesSearch && isDebit;
                  }
                  return matchesSearch;
                }).toList();

                return Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Transaction History',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.x, size: 20),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Search Bar & Filter Chips
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            // Search textfield
                            TextField(
                              onChanged: (val) {
                                setSheetState(() {
                                  searchQuery = val;
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'Search by bank, phone, or amount...',
                                prefixIcon: const Icon(LucideIcons.search, size: 18),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                fillColor: const Color(0xFFF8FAFC),
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Filter chips row
                            Row(
                              children: [
                                _buildFilterChip('All', selectedFilter, (val) {
                                  setSheetState(() => selectedFilter = val);
                                }),
                                const SizedBox(width: 8),
                                _buildFilterChip('Inflows', selectedFilter, (val) {
                                  setSheetState(() => selectedFilter = val);
                                }),
                                const SizedBox(width: 8),
                                _buildFilterChip('Outflows', selectedFilter, (val) {
                                  setSheetState(() => selectedFilter = val);
                                }),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Transactions List
                      Expanded(
                        child: filteredTxs.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(LucideIcons.receipt, size: 48, color: Colors.grey.shade300),
                                    const SizedBox(height: 12),
                                    Text(
                                      searchQuery.isEmpty
                                          ? 'No transactions found'
                                          : 'No matches for "$searchQuery"',
                                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                itemCount: filteredTxs.length,
                                itemBuilder: (context, index) {
                                  final tx = filteredTxs[index];
                                  final bool isDebit = tx['is_debit'] ?? false;
                                  final String amountStr = tx['amount'] ?? '0.00';
                                  
                                  return Card(
                                    elevation: 0.2,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                      leading: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isDebit ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isDebit ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft,
                                          color: isDebit ? Colors.red : Colors.green,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        tx['title'] ?? 'Transaction',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            tx['subtitle'] ?? '',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            tx['created_at'] != null
                                                ? tx['created_at'].toString().split('T')[0]
                                                : 'Recent',
                                            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                                          ),
                                        ],
                                      ),
                                      trailing: Text(
                                        amountStr,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: isDebit ? Colors.red : Colors.green,
                                        ),
                                      ),
                                      onTap: () {
                                        _showTransactionDetailReceipt(tx);
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String selected, ValueChanged<String> onTap) {
    final bool isSelected = label == selected;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : AppTheme.textSecondary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => onTap(label),
      selectedColor: AppTheme.primaryColor,
      backgroundColor: const Color(0xFFF1F5F9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  void _showTransactionDetailReceipt(Map<String, dynamic> tx) {
    final bool isDebit = tx['is_debit'] ?? false;
    final String amountStr = tx['amount'] ?? '₦0.00';
    final String title = tx['title'] ?? 'Transaction Successful';
    final String subtitle = tx['subtitle'] ?? '';
    final String dateStr = tx['created_at'] != null 
        ? tx['created_at'].toString().replaceAll('T', ' ').split('.')[0]
        : 'Recent';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDebit ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDebit ? LucideIcons.arrowUpRight : LucideIcons.check,
                  size: 40,
                  color: isDebit ? Colors.red : Colors.green,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                amountStr,
                style: TextStyle(
                  fontSize: 26, 
                  fontWeight: FontWeight.w800, 
                  color: isDebit ? Colors.red : Colors.green
                ),
              ),
              const SizedBox(height: 20),
              const Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 12),
              
              _buildReceiptRow('Description', subtitle),
              const SizedBox(height: 8),
              _buildReceiptRow('Status', tx['status'] ?? 'Successful'),
              const SizedBox(height: 8),
              _buildReceiptRow('Date & Time', dateStr),
              const SizedBox(height: 8),
              _buildReceiptRow('Transaction ID', tx['id']?.toString().substring(0, 18) ?? 'TXN-UNKNOWN'),
              const SizedBox(height: 12),
              const Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 20),
              
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  minimumSize: const Size(double.infinity, 44),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close Receipt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReceiptDialog({
    required String recipientName,
    required String accountNo,
    required double amount,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Success Checkmark Animation placeholder
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7), // green 100
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.check, size: 48, color: Colors.green),
              ),
              const SizedBox(height: 20),
              const Text(
                'Transfer Successful',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '₦${_formatCurrency(amount)}',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.green),
              ),
              const SizedBox(height: 20),
              const Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 12),
              
              _buildReceiptRow('Recipient', recipientName),
              const SizedBox(height: 8),
              _buildReceiptRow('Account Number', accountNo),
              const SizedBox(height: 8),
              _buildReceiptRow('Bank Name', 'Biometric Payment Gateway'),
              const SizedBox(height: 8),
              _buildReceiptRow('Transaction ID', 'TXN-${DateTime.now().millisecondsSinceEpoch}'),
              const SizedBox(height: 12),
              const Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 20),
              
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary)),
      ],
    );
  }

  // --- ADD FUNDS BOTTOM SHEET ---
  void _showAddMoneyBottomSheet() {
    final TextEditingController amountController = TextEditingController();
    String selectedMethod = 'Debit Card';
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Add Money to Wallet',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Predefined Amounts
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [1000, 5000, 10000, 20000].map((amt) {
                          return OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.3)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              amountController.text = amt.toString();
                            },
                            child: Text('₦${_formatCurrency(amt).split('.')[0]}'),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // Amount Input
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount (₦)',
                          hintText: '0.00',
                          prefixIcon: const Icon(LucideIcons.coins, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Enter an amount';
                          final d = double.tryParse(val);
                          if (d == null || d <= 0) return 'Enter a positive amount';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Method Selection
                      DropdownButtonFormField<String>(
                        value: selectedMethod,
                        decoration: InputDecoration(
                          labelText: 'Payment Method',
                          prefixIcon: const Icon(LucideIcons.creditCard, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: ['Debit Card', 'Bank Transfer', 'USSD'].map((method) {
                          return DropdownMenuItem(
                            value: method,
                            child: Text(method),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedMethod = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setModalState(() {
                                    isSubmitting = true;
                                  });
                                  final double amt = double.parse(amountController.text);
                                  final res = await _supabaseService.addFunds(
                                    userId: widget.userId,
                                    amount: amt,
                                    method: selectedMethod,
                                  );
                                  if (mounted) {
                                    Navigator.pop(context);
                                    if (res == null) {
                                      _showReceiptDialog(
                                        recipientName: 'My Wallet',
                                        accountNo: _profile?['account_no'] ?? 'Wallet',
                                        amount: amt,
                                      );
                                      _loadUserProfile();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $res'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Add Money', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- TO BANK TRANSFER BOTTOM SHEET ---
  void _showBankTransferBottomSheet() {
    final TextEditingController accountController = TextEditingController();
    final TextEditingController amountController = TextEditingController();
    final TextEditingController pinController = TextEditingController();
    String selectedBank = 'GTBank';
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Transfer to Bank Account',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Bank dropdown
                      DropdownButtonFormField<String>(
                        value: selectedBank,
                        decoration: InputDecoration(
                          labelText: 'Select Bank',
                          prefixIcon: const Icon(LucideIcons.landmark, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: ['GTBank', 'Zenith Bank', 'Access Bank', 'UBA', 'OPay', 'Kuda Bank'].map((bank) {
                          return DropdownMenuItem(value: bank, child: Text(bank));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedBank = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Account number
                      TextFormField(
                        controller: accountController,
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        decoration: InputDecoration(
                          labelText: 'Account Number',
                          hintText: 'Enter 10-digit number',
                          counterText: '',
                          prefixIcon: const Icon(LucideIcons.user, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length != 10 || int.tryParse(val) == null) {
                            return 'Enter a valid 10-digit account number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Amount
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount (₦)',
                          hintText: '0.00',
                          prefixIcon: const Icon(LucideIcons.coins, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Please enter an amount';
                          final amt = double.tryParse(val);
                          if (amt == null || amt <= 0) return 'Enter a positive amount';
                          final balance = (_profile?['balance'] as num?)?.toDouble() ?? 0.0;
                          if (amt > balance) return 'Insufficient balance';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Transaction PIN
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: pinController,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              maxLength: 4,
                              decoration: InputDecoration(
                                labelText: 'Transaction PIN',
                                hintText: '••••',
                                counterText: '',
                                prefixIcon: const Icon(LucideIcons.lock, size: 20),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.length != 4 || int.tryParse(val) == null) {
                                  return 'Enter your 4-digit PIN';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            height: 54,
                            width: 54,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
                            ),
                            child: IconButton(
                              icon: const Icon(LucideIcons.fingerprint, color: AppTheme.primaryColor, size: 24),
                              tooltip: 'Verify with Fingerprint',
                              onPressed: () async {
                                final bool isFingerprintVerified = await _biometricService.authenticate(userId: widget.userId);
                                if (isFingerprintVerified && _profile != null) {
                                  setModalState(() {
                                    pinController.text = _profile?['pin'] ?? '';
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setModalState(() {
                                    isSubmitting = true;
                                  });

                                  final double amt = double.parse(amountController.text);
                                  final String acc = accountController.text;
                                  final String pin = pinController.text;

                                  final result = await _supabaseService.bankTransfer(
                                    userId: widget.userId,
                                    bankName: selectedBank,
                                    accountNo: acc,
                                    amount: amt,
                                    pin: pin,
                                  );

                                  if (mounted) {
                                    Navigator.pop(context);
                                    if (result == null) {
                                      _showReceiptDialog(
                                        recipientName: '$selectedBank Transfer',
                                        accountNo: acc,
                                        amount: amt,
                                      );
                                      _loadUserProfile();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $result'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Send Money', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- WITHDRAW FUNDS BOTTOM SHEET ---
  void _showWithdrawBottomSheet() {
    final TextEditingController amountController = TextEditingController();
    final TextEditingController pinController = TextEditingController();
    String selectedChannel = 'ATM withdrawal';
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Withdraw Cash',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Channel dropdown
                      DropdownButtonFormField<String>(
                        value: selectedChannel,
                        decoration: InputDecoration(
                          labelText: 'Withdrawal Method',
                          prefixIcon: const Icon(LucideIcons.arrowUpRight, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: ['ATM withdrawal', 'OPay Agent Cashout', 'Bank Branch'].map((ch) {
                          return DropdownMenuItem(value: ch, child: Text(ch));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedChannel = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Amount
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount (₦)',
                          hintText: '0.00',
                          prefixIcon: const Icon(LucideIcons.coins, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Please enter an amount';
                          final amt = double.tryParse(val);
                          if (amt == null || amt <= 0) return 'Enter a positive amount';
                          final balance = (_profile?['balance'] as num?)?.toDouble() ?? 0.0;
                          if (amt > balance) return 'Insufficient balance';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Transaction PIN
                      TextFormField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'Transaction PIN',
                          hintText: '••••',
                          counterText: '',
                          prefixIcon: const Icon(LucideIcons.lock, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length != 4 || int.tryParse(val) == null) {
                            return 'Enter your 4-digit PIN';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setModalState(() {
                                    isSubmitting = true;
                                  });

                                  final double amt = double.parse(amountController.text);
                                  final String pin = pinController.text;

                                  final result = await _supabaseService.withdrawFunds(
                                    userId: widget.userId,
                                    method: selectedChannel,
                                    amount: amt,
                                    pin: pin,
                                  );

                                  if (mounted) {
                                    Navigator.pop(context);
                                    if (result == null) {
                                      _showReceiptDialog(
                                        recipientName: 'Cash Withdrawal',
                                        accountNo: selectedChannel,
                                        amount: amt,
                                      );
                                      _loadUserProfile();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $result'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Withdraw Cash', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- SERVICE ACTIONS ROUTER ---
  void _onServiceItemTap(String label) {
    switch (label) {
      case 'Airtime':
        _showAirtimeBottomSheet();
        break;
      case 'Data':
        _showDataBottomSheet();
        break;
      case 'Betting':
        _showBettingBottomSheet();
        break;
      case 'TV':
        _showTVBottomSheet();
        break;
      case 'Safebox':
        _showSafeboxBottomSheet();
        break;
      case 'Loan':
        _showLoanBottomSheet();
        break;
      case 'Refer & Earn':
        _showReferAndEarnDialog();
        break;
      case 'More':
        _showMoreServicesBottomSheet();
        break;
    }
  }

  // --- AIRTIME PURCHASE BOTTOM SHEET ---
  void _showAirtimeBottomSheet() {
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController amountController = TextEditingController();
    final TextEditingController pinController = TextEditingController();
    String selectedNetwork = 'MTN';
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Buy Airtime',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Network Selection
                      DropdownButtonFormField<String>(
                        value: selectedNetwork,
                        decoration: InputDecoration(
                          labelText: 'Mobile Operator',
                          prefixIcon: const Icon(LucideIcons.smartphone, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: ['MTN', 'Airtel', 'Glo', '9mobile'].map((net) {
                          return DropdownMenuItem(value: net, child: Text(net));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedNetwork = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Phone number
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        maxLength: 11,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: 'Enter 11-digit mobile number',
                          counterText: '',
                          prefixIcon: const Icon(LucideIcons.phone, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length != 11 || int.tryParse(val) == null) {
                            return 'Enter a valid 11-digit mobile number';
                          }
                          if (!val.startsWith('08') && !val.startsWith('09') && !val.startsWith('07')) {
                            return 'Number must start with 07, 08, or 09';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Amount
                      TextFormField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Amount (₦)',
                          hintText: '0.00',
                          prefixIcon: const Icon(LucideIcons.coins, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Enter an amount';
                          final amt = double.tryParse(val);
                          if (amt == null || amt <= 0) return 'Enter a positive amount';
                          final balance = (_profile?['balance'] as num?)?.toDouble() ?? 0.0;
                          if (amt > balance) return 'Insufficient balance';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Transaction PIN
                      TextFormField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'Transaction PIN',
                          hintText: '••••',
                          counterText: '',
                          prefixIcon: const Icon(LucideIcons.lock, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length != 4 || int.tryParse(val) == null) {
                            return 'Enter your 4-digit PIN';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setModalState(() {
                                    isSubmitting = true;
                                  });

                                  final double amt = double.parse(amountController.text);
                                  final String phone = phoneController.text;
                                  final String pin = pinController.text;

                                  final result = await _supabaseService.purchaseUtility(
                                    userId: widget.userId,
                                    type: 'Airtime',
                                    provider: selectedNetwork,
                                    identifier: phone,
                                    amount: amt,
                                    pin: pin,
                                  );

                                  if (mounted) {
                                    Navigator.pop(context);
                                    if (result == null) {
                                      _showReceiptDialog(
                                        recipientName: '$selectedNetwork Airtime',
                                        accountNo: phone,
                                        amount: amt,
                                      );
                                      _loadUserProfile();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $result'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Buy Airtime', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- DATA PLAN BOTTOM SHEET ---
  void _showDataBottomSheet() {
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController pinController = TextEditingController();
    String selectedNetwork = 'MTN';
    String selectedPlan = '1.5GB - 30 Days (₦1,200)';
    double selectedAmount = 1200.00;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    final plans = {
      '1.5GB - 30 Days (₦1,200)': 1200.00,
      '3GB - 30 Days (₦1,800)': 1800.00,
      '10GB - 30 Days (₦3,500)': 3500.00,
      '25GB - 30 Days (₦6,500)': 6500.00,
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Buy Mobile Data',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Operator Selection
                      DropdownButtonFormField<String>(
                        value: selectedNetwork,
                        decoration: InputDecoration(
                          labelText: 'Mobile Operator',
                          prefixIcon: const Icon(LucideIcons.smartphone, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: ['MTN', 'Airtel', 'Glo', '9mobile'].map((net) {
                          return DropdownMenuItem(value: net, child: Text(net));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedNetwork = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Data Bundle Plans
                      DropdownButtonFormField<String>(
                        value: selectedPlan,
                        decoration: InputDecoration(
                          labelText: 'Select Data Plan',
                          prefixIcon: const Icon(LucideIcons.repeat, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: plans.keys.map((plan) {
                          return DropdownMenuItem(value: plan, child: Text(plan));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedPlan = val;
                              selectedAmount = plans[val]!;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Phone number
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        maxLength: 11,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: 'Enter 11-digit mobile number',
                          counterText: '',
                          prefixIcon: const Icon(LucideIcons.phone, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length != 11 || int.tryParse(val) == null) {
                            return 'Enter a valid 11-digit mobile number';
                          }
                          if (!val.startsWith('08') && !val.startsWith('09') && !val.startsWith('07')) {
                            return 'Number must start with 07, 08, or 09';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Transaction PIN
                      TextFormField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'Transaction PIN',
                          hintText: '••••',
                          counterText: '',
                          prefixIcon: const Icon(LucideIcons.lock, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length != 4 || int.tryParse(val) == null) {
                            return 'Enter your 4-digit PIN';
                          }
                          final balance = (_profile?['balance'] as num?)?.toDouble() ?? 0.0;
                          if (selectedAmount > balance) {
                            return 'Insufficient balance for this bundle';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setModalState(() {
                                    isSubmitting = true;
                                  });

                                  final String phone = phoneController.text;
                                  final String pin = pinController.text;

                                  final result = await _supabaseService.purchaseUtility(
                                    userId: widget.userId,
                                    type: 'Data Bundle',
                                    provider: selectedNetwork,
                                    identifier: phone,
                                    amount: selectedAmount,
                                    pin: pin,
                                    extraDetails: selectedPlan.split(' - ')[0],
                                  );

                                  if (mounted) {
                                    Navigator.pop(context);
                                    if (result == null) {
                                      _showReceiptDialog(
                                        recipientName: '$selectedNetwork Data Bundle',
                                        accountNo: phone,
                                        amount: selectedAmount,
                                      );
                                      _loadUserProfile();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $result'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Buy Data (₦${_formatCurrency(selectedAmount).split('.')[0]})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- BETTING BILLS BOTTOM SHEET ---
  void _showBettingBottomSheet() {
    final TextEditingController idController = TextEditingController();
    final TextEditingController amountController = TextEditingController();
    final TextEditingController pinController = TextEditingController();
    String selectedProvider = 'Bet9ja';
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Fund Betting Account',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Provider Select
                      DropdownButtonFormField<String>(
                        value: selectedProvider,
                        decoration: InputDecoration(
                          labelText: 'Betting Operator',
                          prefixIcon: const Icon(LucideIcons.activity, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: ['Bet9ja', 'SportyBet', '1xBet', 'BetKing'].map((prov) {
                          return DropdownMenuItem(value: prov, child: Text(prov));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedProvider = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // User Customer ID
                      TextFormField(
                        controller: idController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Customer User ID',
                          hintText: 'Enter account player ID',
                          prefixIcon: const Icon(LucideIcons.user, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Enter your Customer ID';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Amount
                      TextFormField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Amount (₦)',
                          hintText: '0.00',
                          prefixIcon: const Icon(LucideIcons.coins, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Enter an amount';
                          final amt = double.tryParse(val);
                          if (amt == null || amt <= 0) return 'Enter a positive amount';
                          final balance = (_profile?['balance'] as num?)?.toDouble() ?? 0.0;
                          if (amt > balance) return 'Insufficient balance';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Transaction PIN
                      TextFormField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'Transaction PIN',
                          hintText: '••••',
                          counterText: '',
                          prefixIcon: const Icon(LucideIcons.lock, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length != 4 || int.tryParse(val) == null) {
                            return 'Enter your 4-digit PIN';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setModalState(() {
                                    isSubmitting = true;
                                  });

                                  final double amt = double.parse(amountController.text);
                                  final String player = idController.text;
                                  final String pin = pinController.text;

                                  final result = await _supabaseService.purchaseUtility(
                                    userId: widget.userId,
                                    type: 'Betting',
                                    provider: selectedProvider,
                                    identifier: player,
                                    amount: amt,
                                    pin: pin,
                                  );

                                  if (mounted) {
                                    Navigator.pop(context);
                                    if (result == null) {
                                      _showReceiptDialog(
                                        recipientName: '$selectedProvider Funding',
                                        accountNo: player,
                                        amount: amt,
                                      );
                                      _loadUserProfile();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $result'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Fund Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- TV SUBSCRIPTION BOTTOM SHEET ---
  void _showTVBottomSheet() {
    final TextEditingController smartcardController = TextEditingController();
    final TextEditingController pinController = TextEditingController();
    String selectedProvider = 'DSTV';
    String selectedPackage = 'DSTV Compact (₦12,500)';
    double selectedAmount = 12500.00;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    final packages = {
      'DSTV Compact (₦12,500)': 12500.00,
      'DSTV Premium (₦29,500)': 29500.00,
      'GOTV Max (₦4,850)': 4850.00,
      'Startimes Classic (₦3,500)': 3500.00,
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Pay TV Subscription',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Provider
                      DropdownButtonFormField<String>(
                        value: selectedProvider,
                        decoration: InputDecoration(
                          labelText: 'TV Provider',
                          prefixIcon: const Icon(LucideIcons.tv, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: ['DSTV', 'GOTV', 'Startimes'].map((prov) {
                          return DropdownMenuItem(value: prov, child: Text(prov));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedProvider = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Package Bundles
                      DropdownButtonFormField<String>(
                        value: selectedPackage,
                        decoration: InputDecoration(
                          labelText: 'Select Package',
                          prefixIcon: const Icon(LucideIcons.package, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: packages.keys.map((pkg) {
                          return DropdownMenuItem(value: pkg, child: Text(pkg));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedPackage = val;
                              selectedAmount = packages[val]!;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Smartcard Number
                      TextFormField(
                        controller: smartcardController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Smartcard / IUC Number',
                          hintText: 'Enter Smartcard number',
                          prefixIcon: const Icon(LucideIcons.creditCard, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Enter Smartcard/IUC Number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Transaction PIN
                      TextFormField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'Transaction PIN',
                          hintText: '••••',
                          counterText: '',
                          prefixIcon: const Icon(LucideIcons.lock, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length != 4 || int.tryParse(val) == null) {
                            return 'Enter your 4-digit PIN';
                          }
                          final balance = (_profile?['balance'] as num?)?.toDouble() ?? 0.0;
                          if (selectedAmount > balance) return 'Insufficient balance';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setModalState(() {
                                    isSubmitting = true;
                                  });

                                  final String smartcard = smartcardController.text;
                                  final String pin = pinController.text;

                                  final result = await _supabaseService.purchaseUtility(
                                    userId: widget.userId,
                                    type: 'TV Subscription',
                                    provider: selectedProvider,
                                    identifier: smartcard,
                                    amount: selectedAmount,
                                    pin: pin,
                                    extraDetails: selectedPackage.split(' (')[0],
                                  );

                                  if (mounted) {
                                    Navigator.pop(context);
                                    if (result == null) {
                                      _showReceiptDialog(
                                        recipientName: '$selectedProvider Subscription',
                                        accountNo: smartcard,
                                        amount: selectedAmount,
                                      );
                                      _loadUserProfile();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $result'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Pay ₦${_formatCurrency(selectedAmount).split('.')[0]}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- SAFEBOX SAVINGS BOTTOM SHEET ---
  void _showSafeboxBottomSheet() {
    final TextEditingController amountController = TextEditingController();
    final TextEditingController pinController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final double safeboxVal = (_profile?['safebox_balance'] as num? ?? 0.0).toDouble();
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Safebox Savings Vault',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Text('Current Savings Vault Balance', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 6),
                            Text(
                              '₦${_formatCurrency(safeboxVal)}',
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Amount input
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount to Lock (₦)',
                          hintText: '0.00',
                          prefixIcon: const Icon(LucideIcons.coins, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Enter an amount to lock';
                          final amt = double.tryParse(val);
                          if (amt == null || amt <= 0) return 'Enter a positive amount';
                          final balance = (_profile?['balance'] as num?)?.toDouble() ?? 0.0;
                          if (amt > balance) return 'Insufficient balance in main wallet';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Transaction PIN
                      TextFormField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'Transaction PIN',
                          hintText: '••••',
                          counterText: '',
                          prefixIcon: const Icon(LucideIcons.lock, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length != 4 || int.tryParse(val) == null) {
                            return 'Enter your 4-digit PIN';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setModalState(() {
                                    isSubmitting = true;
                                  });

                                  final double amt = double.parse(amountController.text);
                                  final String pin = pinController.text;

                                  final result = await _supabaseService.saveToSafebox(
                                    userId: widget.userId,
                                    amount: amt,
                                    pin: pin,
                                  );

                                  if (mounted) {
                                    Navigator.pop(context);
                                    if (result == null) {
                                      _showReceiptDialog(
                                        recipientName: 'Locked Vault Savings',
                                        accountNo: 'Vault Account',
                                        amount: amt,
                                      );
                                      _loadUserProfile();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $result'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Lock Funds Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- LOAN DISBURSEMENT BOTTOM SHEET ---
  void _showLoanBottomSheet() {
    final TextEditingController amountController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final double currentLoan = (_profile?['loan_balance'] as num? ?? 0.0).toDouble();
            const double maxEligible = 150000.00;
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Request Cash Loan',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  const Text('Outstanding Loan', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₦${_formatCurrency(currentLoan)}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  const Text('Max Loan Limit', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₦${_formatCurrency(maxEligible)}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Amount Input
                      TextFormField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Request Amount (₦)',
                          hintText: 'Enter loan amount requested',
                          prefixIcon: const Icon(LucideIcons.coins, size: 20),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Enter an amount';
                          final amt = double.tryParse(val);
                          if (amt == null || amt <= 0) return 'Enter a positive amount';
                          if (amt > (maxEligible - currentLoan)) {
                            return 'Requested loan exceeds eligible limit of ₦${_formatCurrency(maxEligible - currentLoan)}';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'By requesting this loan, you agree to our 1.5% monthly interest rate and standard auto-repayment terms from your main wallet.',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setModalState(() {
                                    isSubmitting = true;
                                  });

                                  final double amt = double.parse(amountController.text);
                                  final result = await _supabaseService.requestLoan(
                                    userId: widget.userId,
                                    amount: amt,
                                  );

                                  if (mounted) {
                                    Navigator.pop(context);
                                    if (result == null) {
                                      _showReceiptDialog(
                                        recipientName: 'Loan Disbursed',
                                        accountNo: 'Main Wallet Account',
                                        amount: amt,
                                      );
                                      _loadUserProfile();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed: $result'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Disburse Loan Instantly', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- REFER & EARN DIALOG ---
  void _showReferAndEarnDialog() {
    const String referralCode = 'SMPAY-84440EDB';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFEFF6FF), // blue 50
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.gift, size: 48, color: AppTheme.primaryColor),
              ),
              const SizedBox(height: 20),
              const Text(
                'Refer & Earn ₦500',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Share your referral code with your friends and get rewarded instantly when they sign up and secure their account!',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      referralCode,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor, letterSpacing: 1.2),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.copy, size: 20, color: Colors.grey),
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: referralCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Referral code copied!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- MORE SERVICES BOTTOM SHEET ---
  void _showMoreServicesBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'All Services & Utilities',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                mainAxisSpacing: 20,
                crossAxisSpacing: 12,
                children: [
                  _buildMoreServiceTile(LucideIcons.smartphone, 'Airtime'),
                  _buildMoreServiceTile(LucideIcons.repeat, 'Data'),
                  _buildMoreServiceTile(LucideIcons.activity, 'Betting'),
                  _buildMoreServiceTile(LucideIcons.tv, 'TV Bill'),
                  _buildMoreServiceTile(LucideIcons.wallet, 'Safebox'),
                  _buildMoreServiceTile(LucideIcons.coins, 'Cash Loan'),
                  _buildMoreServiceTile(LucideIcons.gift, 'Referral'),
                  _buildMoreServiceTile(LucideIcons.landmark, 'Bank Send'),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMoreServiceTile(IconData icon, String label) {
    return InkWell(
      onTap: () {
        Navigator.pop(context); // Close bottom sheet
        String targetLabel = label;
        if (label == 'TV Bill') targetLabel = 'TV';
        if (label == 'Cash Loan') targetLabel = 'Loan';
        if (label == 'Referral') targetLabel = 'Refer & Earn';
        
        if (label == 'Bank Send') {
          _showBankTransferBottomSheet();
        } else {
          _onServiceItemTap(targetLabel);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
    await prefs.remove('logged_in_user_id');
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged out of secure session successfully.')),
      );
    }
  }

  void _showDeleteAccountConfirmation() {
    final double balance = double.tryParse(_profile?['balance']?.toString() ?? '0.0') ?? 0.0;
    final double safeboxBalance = double.tryParse(_profile?['safebox_balance']?.toString() ?? '0.0') ?? 0.0;
    final double loanBalance = double.tryParse(_profile?['loan_balance']?.toString() ?? '0.0') ?? 0.0;

    if (loanBalance > 0.0) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Account Deletion Blocked', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          content: Text('You cannot delete your account because you have an outstanding loan balance of ₦${loanBalance.toStringAsFixed(2)}. Please repay your loan first.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (balance > 0.0 || safeboxBalance > 0.0) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Account Deletion Blocked', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          content: Text(
            'You cannot delete your account because you have remaining funds in your wallet:\n\n'
            '- Main Balance: ₦${balance.toStringAsFixed(2)}\n'
            '- Safebox Balance: ₦${safeboxBalance.toStringAsFixed(2)}\n\n'
            'Please transfer out all your funds (all balances must be 0) before closing your account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Account Deletion', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you absolutely sure you want to permanently delete your Biometric Payment Gateway account?\n\n'
          'This action is irreversible. All of your profile credentials and transaction histories will be completely purged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteAccountProgress();
            },
            child: const Text('Delete Permanently', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _deleteAccountProgress() async {
    double progress = 0.05;
    final progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          if (progress < 0.90) {
            progress += 0.05;
          }
        });
      } else {
        timer.cancel();
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Timer.periodic(const Duration(milliseconds: 100), (t) {
            if (mounted) {
              setDialogState(() {});
            } else {
              t.cancel();
            }
          });

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 100,
                    width: 100,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 6,
                          color: Colors.red,
                          backgroundColor: Colors.grey.shade200,
                        ),
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Deleting Biometric Gateway Account',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Purging credentials, transaction history, and closing vault...',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );



    final bool deleted = await _supabaseService.deleteUserAccount(widget.userId);
    progressTimer.cancel();

    if (mounted) {
      Navigator.of(context).pop();
      if (deleted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', false);
        await prefs.remove('logged_in_user_id');
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your account and biometric data have been permanently deleted.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete account. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ─── QR Bottom Sheet Widget (Tabbed: My QR Code / Scan QR) ───
class _QRBottomSheet extends StatefulWidget {
  final String accountNo;
  final String fullName;
  final String qrData;
  final void Function(String accountNo, String name) onAccountScanned;

  const _QRBottomSheet({
    required this.accountNo,
    required this.fullName,
    required this.qrData,
    required this.onAccountScanned,
  });

  @override
  State<_QRBottomSheet> createState() => _QRBottomSheetState();
}

class _QRBottomSheetState extends State<_QRBottomSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  MobileScannerController? _scannerController;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _scannerController == null) {
        setState(() {
          _scannerController = MobileScannerController(
            facing: CameraFacing.back,
            detectionSpeed: DetectionSpeed.normal,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_hasScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? raw = barcode.rawValue;
      if (raw != null && raw.startsWith('biometricgateway://')) {
        _hasScanned = true;
        _scannerController?.stop();
        // Parse: biometricgateway://<account_no>/<full_name>
        final parts = raw.replaceFirst('biometricgateway://', '').split('/');
        final String accNo = parts.isNotEmpty ? parts[0] : 'Unknown';
        final String name = parts.length > 1 ? parts.sublist(1).join('/') : 'Biometric Gateway User';
        widget.onAccountScanned(accNo, name);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('QR Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              tabs: const [
                Tab(text: 'My QR Code'),
                Tab(text: 'Scan QR'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMyQRTab(),
                _buildScanQRTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyQRTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'Let others scan this code to get your account details',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
          ),
          const SizedBox(height: 28),
          // QR Code Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // User avatar and name
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.fullName.isNotEmpty ? widget.fullName[0].toUpperCase() : 'S',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.fullName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Biometric Gateway Account',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 20),
                // Actual QR Code
                QrImageView(
                  data: widget.qrData,
                  version: QrVersions.auto,
                  size: 200,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0F172A),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF0F172A),
                  ),
                  gapless: true,
                ),
                const SizedBox(height: 20),
                // Account number display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.creditCard, size: 16, color: Colors.grey.shade500),
                      const SizedBox(width: 8),
                      Text(
                        widget.accountNo,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), letterSpacing: 1.2),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: widget.accountNo));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Account number copied!')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(LucideIcons.copy, size: 14, color: AppTheme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.shieldCheck, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(
                'Secured with Biometric Gateway encryption',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanQRTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'Point your camera at a Biometric Gateway QR code to see the account details',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  if (_scannerController != null)
                    MobileScanner(
                      controller: _scannerController!,
                      onDetect: _onBarcodeDetected,
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.camera, size: 48, color: Colors.grey.shade500),
                            const SizedBox(height: 12),
                            Text(
                              'Initializing camera...',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Overlay border frame
                  Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.primaryColor, width: 3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  // Corner accents
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.scanLine, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(
                'Scanning for Biometric Gateway QR codes...',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
