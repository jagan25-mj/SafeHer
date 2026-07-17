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

  Future<void> _openWebApp() async {
    final uri = AppConfig.webAppUri;
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SAFEHER_WEB_URL is not configured.')),
      );
      return;
    }

    if (!await canLaunchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open the deployed web app.')),
        );
      }
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _friendlyRegistrationError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('already registered') ||
        message.contains('email already in use') ||
        message.contains('user already exists')) {
      return 'This email is already registered. Please sign in instead.';
    }

    if (message.contains('duplicate key value') && message.contains('phone')) {
      return 'This phone number is already linked to another account.';
    }

    return 'Unable to create your account. Please check your details and try again.';
  }

  Future<void> _register() async {
    setState(() => _loading = true);
    try {
      final fullName = _fullName.text.trim();
      final email = _email.text.trim().toLowerCase();
      final phone = _phone.text.trim();

      if (fullName.isEmpty || email.isEmpty || phone.isEmpty) {
        throw Exception('Please complete your full name, email, and phone.');
      }

      if (_pass.text.length < 8) {
        throw Exception('Password must be at least 8 characters.');
      }

      if (!_emailRegex.hasMatch(email)) {
        throw Exception('Please enter a valid email address.');
      }

      if (!_phoneRegex.hasMatch(phone)) {
        throw Exception(
          'Please enter a valid phone number (7-15 digits).',
        );
      }

      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: _pass.text,
      );

      if (res.user != null) {
        final userId = res.user!.id;

        await Supabase.instance.client.from('profiles').upsert({
          'id': userId,
          'full_name': fullName,
          'phone': phone,
          'email': email,
          'role': 'USER',
        }, onConflict: 'id');

        final contactRows = [
          {
            'user_id': userId,
            'label': _c1Label.text.trim(),
            'phone': _c1Phone.text.trim(),
          },
          {
            'user_id': userId,
            'label': _c2Label.text.trim(),
            'phone': _c2Phone.text.trim(),
          },
          {
            'user_id': userId,
            'label': _c3Label.text.trim(),
            'phone': _c3Phone.text.trim(),
          },
        ];

        // Filter out empty contacts — at least one must be valid
        final validContacts = contactRows
            .where((c) =>
                (c['label'] as String).isNotEmpty &&
                (c['phone'] as String).isNotEmpty)
            .toList();

        if (validContacts.isEmpty) {
          throw Exception(
            'Please fill in at least one emergency contact.',
          );
        }

        // Validate phone format for each contact
        for (final contact in validContacts) {
          if (!_phoneRegex.hasMatch(contact['phone'] as String)) {
            throw Exception(
              'Emergency contact "${contact['label']}" has an invalid phone number.',
            );
          }
        }

        await Supabase.instance.client
            .from('emergency_contacts')
            .delete()
            .eq('user_id', userId);

        await Supabase.instance.client
            .from('emergency_contacts')
            .insert(validContacts);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyRegistrationError(e)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
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
                        'Password',
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
                      _buildLabel('Emergency Safety Circle (3 required)'),
                      _buildContactPair(
                        labelController: _c1Label,
                        phoneController: _c1Phone,
                      ),
                      const Divider(height: 24, color: SafeHerColors.stroke),
                      _buildContactPair(
                        labelController: _c2Label,
                        phoneController: _c2Phone,
                      ),
                      const Divider(height: 24, color: SafeHerColors.stroke),
                      _buildContactPair(
                        labelController: _c3Label,
                        phoneController: _c3Phone,
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
            hintText: 'Relation (e.g. Mom)',
            hintStyle: const TextStyle(fontSize: 14),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        const SizedBox(height: 8),
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
}
