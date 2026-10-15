import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/l10n/app_localizations.dart';
import '../../../core/providers/locale_provider.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../providers/auth_provider.dart';

class RegisterShopScreen extends ConsumerStatefulWidget {
  const RegisterShopScreen({super.key});

  @override
  ConsumerState<RegisterShopScreen> createState() => _RegisterShopScreenState();
}

class _RegisterShopScreenState extends ConsumerState<RegisterShopScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _shopNameController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authProvider.notifier).register(
      shopName: _shopNameController.text,
      username: _usernameController.text,
      password: _passwordController.text,
      fullName: _ownerNameController.text.isNotEmpty ? _ownerNameController.text : null,
      phoneNumber: _phoneController.text.isNotEmpty ? _phoneController.text : null,
    );

    if (success && mounted) {
      final isAmharic = ref.read(localeProvider.notifier).isAmharic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAmharic ? 'መደብሩ በተሳካ ሁኔታ ተመዝግቧል!' : 'Shop registered successfully!'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      // Pop back since root router will automatically transition to MainShellScreen
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n?.registerTitle ?? 'Register New Shop',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: const [
          LanguageSwitcherButton(),
          SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Error banner if any
                if (authState.errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 20, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            authState.errorMessage!,
                            style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Shop Name
                TextFormField(
                  controller: _shopNameController,
                  decoration: InputDecoration(
                    labelText: l10n?.shopName ?? 'Shop Name',
                    hintText: l10n?.shopNameHint ?? 'e.g., Bole Mini Market',
                    prefixIcon: const Icon(Icons.store, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return isAmharic ? 'እባክዎ የመደብሩን ስም ያስገቡ' : 'Please enter shop name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Owner Name
                TextFormField(
                  controller: _ownerNameController,
                  decoration: InputDecoration(
                    labelText: l10n?.ownerFullName ?? 'Owner / Manager Name',
                    hintText: isAmharic ? 'ለምሳሌ፡ አበበ በቀለ' : 'e.g., Abebe Bekele',
                    prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),

                // Phone Number
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: l10n?.ownerPhone ?? 'Phone Number',
                    hintText: '0911234567',
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),

                // Username
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n?.username ?? 'Username',
                    hintText: isAmharic ? 'የመግቢያ ስም (ላቲን/እንግሊዝኛ)' : 'e.g., shop_admin',
                    prefixIcon: const Icon(Icons.account_circle_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return isAmharic ? 'እባክዎ የተጠቃሚ ስም ያስገቡ' : 'Please enter a username';
                    }
                    if (val.trim().length < 3) {
                      return isAmharic
                          ? 'የተጠቃሚ ስም ቢያንስ 3 ፊደላት መሆን አለበት'
                          : 'Username must be at least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: l10n?.password ?? 'Password',
                    hintText: l10n?.passwordHint ?? 'At least 6 characters',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return isAmharic ? 'እባክዎ የይለፍ ቃል ያስገቡ' : 'Please enter a password';
                    }
                    if (val.length < 6) {
                      return isAmharic
                          ? 'የይለፍ ቃል ቢያንስ 6 ፊደላት መሆን አለበት'
                          : 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Confirm Password
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: l10n?.confirmPassword ?? 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_reset, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleRegister(),
                  validator: (val) {
                    if (val != _passwordController.text) {
                      return l10n?.passwordsDoNotMatch ?? 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Submit Button
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: authState.isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: authState.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            l10n?.registerShopButton ?? 'Create Shop Account',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // Back to login prompt
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n?.hasAccount ?? 'Already have an account?',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        l10n?.signInPrompt ?? 'Sign In',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
