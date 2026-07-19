import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_config.dart';
import 'theme.dart';

class RegistrationScreen extends StatefulWidget {
  final VoidCallback onLoginTap;
  const RegistrationScreen({required this.onLoginTap, super.key});

  @override
  RegistrationScreenState createState() => RegistrationScreenState();
}

class RegistrationScreenState extends State<RegistrationScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _c1Label = TextEditingController();
  final _c1Phone = TextEditingController();
  final _c2Label = TextEditingController();
  final _c2Phone = TextEditingController();
  final _c3Label = TextEditingController();
  final _c3Phone = TextEditingController();
  bool _loading = false;

  // Input validation patterns
  static final _phoneRegex = RegExp(r'^\+?[\d\s\-]{7,15}$');
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _pass.dispose();
    _c1Label.dispose();
    _c1Phone.dispose();
    _c2Label.dispose();
    _c2Phone.dispose();
    _c3Label.dispose();
    _c3Phone.dispose();
    super.dispose();
  }

  Future<void> _openWebApp() async {
    final uri = AppConfig.webAppUri;
    if (uri == null) {
      _showSnackBar('SAFEHER_WEB_URL is not configured.');
      return;
    }
    if (!await canLaunchUrl(uri)) {
      _showSnackBar('Unable to open the deployed web app.');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _register() async {
    // Client-side validation
    final fullName = _fullName.text.trim();
    final email = _email.text.trim().toLowerCase();
    final phone = _phone.text.trim();

    if (fullName.isEmpty || email.isEmpty || phone.isEmpty) {
      _showSnackBar('Please complete your full name, email, and phone.');
      return;
    }

    if (_pass.text.length < 8) {
      _showSnackBar('Password must be at least 8 characters.');
      return;
    }

    if (!_emailRegex.hasMatch(email)) {
      _showSnackBar('Please enter a valid email address.');
      return;
    }

    if (!_phoneRegex.hasMatch(phone)) {
      _showSnackBar('Please enter a valid phone number (7-15 digits).');
      return;
    }

    final contactRows = [
      {'label': _c1Label.text.trim(), 'phone': _c1Phone.text.trim()},
      {'label': _c2Label.text.trim(), 'phone': _c2Phone.text.trim()},
      {'label': _c3Label.text.trim(), 'phone': _c3Phone.text.trim()},
    ];

    final validContacts = contactRows
        .where((c) =>
            (c['label'] as String).isNotEmpty &&
            (c['phone'] as String).isNotEmpty)
        .toList();

    if (validContacts.isEmpty) {
      _showSnackBar('Please fill in at least one emergency contact.');
      return;
    }

    for (final contact in validContacts) {
      if (!_phoneRegex.hasMatch(contact['phone'] as String)) {
        _showSnackBar('Emergency contact "${contact['label']}" has an invalid phone number.');
        return;
      }
    }

    // API call
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: _pass.text,
        data: {
          'full_name': fullName,
          'phone': phone,
          'emergency_contacts': validContacts,
        },
      );

      _showSnackBar(
        'Account created! Check your email to confirm if required, then sign in.',
        isError: false,
      );
      // Wait a moment before switching to login
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        widget.onLoginTap();
      }
    } on AuthException catch (e) {
      if (e.message.contains('Database error saving new user')) {
        _showSnackBar('This phone number might already be in use, or there is a server configuration issue.');
      } else {
        _showSnackBar(e.message);
      }
    } on PostgrestException catch (e) {
      if (e.message.contains('duplicate key value') && e.message.contains('phone')) {
        _showSnackBar('This phone number is already linked to another account.');
      } else {
        _showSnackBar('Database error: ${e.message}');
      }
    } catch (e) {
      _showSnackBar('An unexpected error occurred: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: SafeHerColors.foreground,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: SafeHerColors.accent),
        hintText: hint,
        fillColor: const Color(0xFFFCFAFF),
      ),
    );
  }

  Widget _buildContactPair({
    required TextEditingController labelController,
    required TextEditingController phoneController,
    required String hintPrefix,
  }) {
    return Column(
      children: [
        TextField(
          controller: labelController,
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.badge_outlined,
              color: SafeHerColors.accent.withValues(alpha: 0.7),
              size: 20,
            ),
            hintText: 'Relation (e.g. $hintPrefix)',
            hintStyle: const TextStyle(fontSize: 14),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.phone_android_rounded,
              color: SafeHerColors.accent.withValues(alpha: 0.7),
              size: 20,
            ),
            hintText: 'Phone number',
            hintStyle: const TextStyle(fontSize: 14),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: SafeHerGradients.pageBackground,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: safeHerGlassDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/icon/app_icon.jpeg',
                              width: 34,
                              height: 34,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SAFEHER',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: const Color(0xFF64418F),
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              Text(
                                'Your community-backed shield',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFFA05D8F),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Join the circle of protection.',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: const Color(0xFF4F336F),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 10),
                      _buildLabel('Your Details'),
                      _buildTextField(
                        _fullName,
                        'Full Name',
                        Icons.person_outline,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        _email,
                        'Email Address',
                        Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        _phone,
                        'Phone Number',
                        Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        _pass,
                        'Password (min 8 chars)',
                        Icons.lock_outline_rounded,
                        isPassword: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: safeHerGlassDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Emergency Safety Circle (at least 1 required)'),
                      const SizedBox(height: 4),
                      Text(
                        'Add up to 3 trusted contacts who will be notified instantly when you need help.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF7A5A94),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildContactPair(
                        labelController: _c1Label,
                        phoneController: _c1Phone,
                        hintPrefix: 'Mom',
                      ),
                      const Divider(height: 16, color: SafeHerColors.stroke),
                      _buildContactPair(
                        labelController: _c2Label,
                        phoneController: _c2Phone,
                        hintPrefix: 'Friend',
                      ),
                      const Divider(height: 16, color: SafeHerColors.stroke),
                      _buildContactPair(
                        labelController: _c3Label,
                        phoneController: _c3Phone,
                        hintPrefix: 'Dad',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: SafeHerGradients.brand,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton(
                      onPressed: _loading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Protect My Future',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ),
                if (AppConfig.webAppUri != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openWebApp,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open Deployed Web App'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: const Color(0xFF5F3F81),
                        side: const BorderSide(color: SafeHerColors.stroke),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: widget.onLoginTap,
                    child: Text.rich(
                      TextSpan(
                        text: 'Already have a SafeHer account? ',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF7F5B96),
                          fontWeight: FontWeight.w600,
                        ),
                        children: const [
                          TextSpan(
                            text: 'Sign in here',
                            style: TextStyle(
                              color: SafeHerColors.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
