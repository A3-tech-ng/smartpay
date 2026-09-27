import 'package:flutter/material.dart';
import '../core/theme/app_icons.dart';
import '../core/theme/app_theme.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  late TabController _tabController;

  // Users management state
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoadingUsers = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Admin settings state
  final _settingsFormKey = GlobalKey<FormState>();
  final TextEditingController _adminUsernameController = TextEditingController();
  final TextEditingController _adminPasswordController = TextEditingController();
  bool _isSavingSettings = false;
  bool _obscureSettingsPassword = true;

  // Stats
  int _totalUsersCount = 0;
  double _totalDeposits = 0.0;
  double _averageDeposit = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUsersData();
    _loadAdminSettingsDefaults();
  }

  Future<void> _loadAdminSettingsDefaults() async {
    // We could pre-fill with current username, but for security, keep empty or default 'admin'
    _adminUsernameController.text = 'admin';
  }

  Future<void> _loadUsersData() async {
    setState(() {
      _isLoadingUsers = true;
    });

    final users = await _supabaseService.getAllUsers();
    
    // Compute stats
    int count = users.length;
    double sum = 0.0;
    for (var u in users) {
      final bal = u['balance'];
      if (bal != null) {
        sum += (bal as num).toDouble();
      }
    }

    setState(() {
      _allUsers = users;
      _filteredUsers = users;
      _totalUsersCount = count;
      _totalDeposits = sum;
      _averageDeposit = count > 0 ? sum / count : 0.0;
      _isLoadingUsers = false;
      _filterUsers(_searchQuery);
    });
  }

  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredUsers = _allUsers;
      } else {
        _filteredUsers = _allUsers.where((user) {
          final fullName = (user['full_name'] ?? '').toString().toLowerCase();
          final phone = (user['phone_number'] ?? '').toString().toLowerCase();
          final accountNo = (user['account_no'] ?? '').toString().toLowerCase();
          final userId = (user['user_id'] ?? '').toString().toLowerCase();
          
          return fullName.contains(_searchQuery) ||
              phone.contains(_searchQuery) ||
              accountNo.contains(_searchQuery) ||
              userId.contains(_searchQuery);
        }).toList();
      }
    });
  }

  Future<void> _deleteUser(String userId, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: AppTheme.accentRed),
            SizedBox(width: 8),
            Text('Confirm Deletion', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('Are you sure you want to permanently delete the account of $userName ($userId)? This will delete all their transaction history and biometric records. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoadingUsers = true;
      });

      final success = await _supabaseService.deleteUserAccount(userId);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account for $userName successfully deleted.'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete account. Please try again.'), backgroundColor: AppTheme.accentRed),
        );
      }
      
      _loadUsersData();
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: user['full_name']);
    final phoneController = TextEditingController(text: user['phone_number']);
    final balanceController = TextEditingController(text: (user['balance'] ?? 0.0).toString());
    final accountController = TextEditingController(text: user['account_no']);
    String selectedKycTier = user['kyc_tier'] ?? 'Tier 3 Verified';

    final tiers = ['Tier 1 Basic', 'Tier 2 Semi-Verified', 'Tier 3 Verified'];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                    child: const Icon(LucideIcons.userCheck, color: AppTheme.primaryColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'User ID: ${user['user_id']}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        // Full Name
                        TextFormField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(LucideIcons.user, size: 18),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Enter full name';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Phone Number
                        TextFormField(
                          controller: phoneController,
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(LucideIcons.phone, size: 18),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Enter phone number';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Account Number
                        TextFormField(
                          controller: accountController,
                          decoration: InputDecoration(
                            labelText: 'Account Number',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(LucideIcons.creditCard, size: 18),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Enter account number';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Wallet Balance
                        TextFormField(
                          controller: balanceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Balance (₦)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(LucideIcons.coins, size: 18),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Enter balance';
                            if (double.tryParse(value) == null) return 'Enter a valid number';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // KYC Tier
                        DropdownButtonFormField<String>(
                          value: selectedKycTier,
                          decoration: InputDecoration(
                            labelText: 'KYC Tier',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(LucideIcons.shieldCheck, size: 18),
                          ),
                          items: tiers.map((tier) {
                            return DropdownMenuItem(
                              value: tier,
                              child: Text(tier),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedKycTier = val;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    final updated = await _supabaseService.updateProfileAdmin(
                      userId: user['user_id'],
                      fullName: nameController.text.trim(),
                      phoneNumber: phoneController.text.trim(),
                      balance: double.parse(balanceController.text.trim()),
                      kycTier: selectedKycTier,
                      accountNo: accountController.text.trim(),
                    );

                    if (context.mounted) {
                      Navigator.of(context).pop();
                      if (updated) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User profile updated successfully'), backgroundColor: Colors.green),
                        );
                        _loadUsersData();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to update user profile'), backgroundColor: AppTheme.accentRed),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveAdminSettings() async {
    if (!_settingsFormKey.currentState!.validate()) return;

    setState(() {
      _isSavingSettings = true;
    });

    final newUsername = _adminUsernameController.text.trim();
    final newPassword = _adminPasswordController.text.trim();

    final success = await _supabaseService.updateAdminCredentials(newUsername, newPassword);

    setState(() {
      _isSavingSettings = false;
    });

    if (success && mounted) {
      _adminPasswordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin credentials updated successfully!'), backgroundColor: Colors.green),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update credentials. Please check logs.'), backgroundColor: AppTheme.accentRed),
      );
    }
  }

  void _handleLogout() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _adminUsernameController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.shield, color: Colors.white),
            SizedBox(width: 8),
            Text('Biometric Gateway Admin Panel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, color: Colors.white),
            tooltip: 'Reload Database Data',
            onPressed: _loadUsersData,
          ),
          IconButton(
            icon: const Icon(LucideIcons.logOut, color: Colors.white),
            tooltip: 'Logout Admin',
            onPressed: _handleLogout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.6),
          tabs: const [
            Tab(icon: Icon(LucideIcons.users), text: 'Manage Users'),
            Tab(icon: Icon(LucideIcons.settings), text: 'Security Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsersManagementTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

  Widget _buildUsersManagementTab() {
    return Column(
      children: [
        // Premium Summary Cards Section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primaryColor.withOpacity(0.08), AppTheme.secondaryColor.withOpacity(0.04)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: 'Total Accounts',
                      value: _totalUsersCount.toString(),
                      icon: LucideIcons.users,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      title: 'Total Reserves',
                      value: '₦${_totalDeposits.toStringAsFixed(0)}',
                      icon: LucideIcons.coins,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Search Bar
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppTheme.dividerColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextFormField(
                    controller: _searchController,
                    onChanged: _filterUsers,
                    decoration: InputDecoration(
                      hintText: 'Search users by name, phone, or account...',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      prefixIcon: const Icon(LucideIcons.search, color: AppTheme.textSecondary, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, color: AppTheme.textSecondary, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                _filterUsers('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Users list view
        Expanded(
          child: _isLoadingUsers
              ? const Center(child: CircularProgressIndicator())
              : _filteredUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.users, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty ? 'No accounts found in system.' : 'No matches found for "$_searchQuery"',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        return _buildUserCard(user);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final String fullName = user['full_name'] ?? 'No Name';
    final String phoneNumber = user['phone_number'] ?? 'No Phone';
    final String accountNo = user['account_no'] ?? 'No Account';
    final double balance = (user['balance'] ?? 0.0).toDouble();
    final String kycTier = user['kyc_tier'] ?? 'Tier 3 Verified';
    final String profilePictureUrl = user['profile_picture_url'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
              backgroundImage: profilePictureUrl.isNotEmpty ? NetworkImage(profilePictureUrl) : null,
              child: profilePictureUrl.isEmpty
                  ? const Icon(LucideIcons.user, color: AppTheme.primaryColor, size: 24)
                  : null,
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Phone: $phoneNumber',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  Text(
                    'Acct: $accountNo',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          kycTier,
                          style: const TextStyle(color: AppTheme.primaryDark, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₦${balance.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Actions
            Column(
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.edit, color: AppTheme.primaryColor, size: 20),
                  onPressed: () => _editUser(user),
                  tooltip: 'Edit Profile',
                ),
                IconButton(
                  icon: const Icon(LucideIcons.trash2, color: AppTheme.accentRed, size: 20),
                  onPressed: () => _deleteUser(user['user_id'], fullName),
                  tooltip: 'Delete User Account',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.shieldCheck, color: Colors.white, size: 40),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Security Manager',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Update login name and password for the administrative account.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppTheme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _settingsFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Change Credentials',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 20),
                    // New Username
                    TextFormField(
                      controller: _adminUsernameController,
                      decoration: InputDecoration(
                        labelText: 'Admin Username',
                        prefixIcon: const Icon(LucideIcons.user, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter new username';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    // New Password
                    TextFormField(
                      controller: _adminPasswordController,
                      obscureText: _obscureSettingsPassword,
                      decoration: InputDecoration(
                        labelText: 'New Admin Password',
                        prefixIcon: const Icon(LucideIcons.lock, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureSettingsPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureSettingsPassword = !_obscureSettingsPassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter new password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters long';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isSavingSettings ? null : _saveAdminSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSavingSettings
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.save, size: 20),
                                SizedBox(width: 8),
                                Text('Save New Credentials', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 30),
          // Additional developer instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.info, color: Colors.orange.shade800, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Supabase Integration Tip',
                      style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Changes here will sync to the public.admin_settings table in Supabase. A local persistent fallback will be updated to guarantee offline access if database communication is interrupted.',
                  style: TextStyle(color: Colors.orange.shade900, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
