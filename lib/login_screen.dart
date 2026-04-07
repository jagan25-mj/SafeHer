import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_config.dart';
import 'theme.dart';

class LoginScreen extends StatelessWidget {
  final VoidCallback onRegisterTap;
  LoginScreen({required this.onRegisterTap, super.key});

  final _phone = TextEditingController();
  final _pass = TextEditingController();

  Future<void> _openWebApp(BuildContext context) async {
    final uri = AppConfig.webAppUri;
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SAFEHER_WEB_URL is not configured.')),
      );
      return;
    }

    if (!await canLaunchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open the deployed web app.')),
        );
      }
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _friendlyLoginError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('invalid login credentials')) {
      return 'Incorrect password. Please try again.';
    }

    if (message.contains('email not confirmed')) {
      return 'Please confirm your email before logging in.';
    }

    if (message.contains('no account found')) {
      return 'No account found for that phone number.';
    }

    return 'Unable to sign in. Please check your details and try again.';
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(18),
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
                                'Safety starts with connection',
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
                        'Welcome back',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: const Color(0xFF4F336F),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Access your safety dashboard, trusted contacts, and live risk updates in one place.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF7A5A94),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4FA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFF2D8E8)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Why women choose SafeHer',
                              style: TextStyle(
                                color: Color(0xFF5F3F81),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text('• Trusted-circle alerts in one tap'),
                            Text('• Live helplines and safety resources'),
                            Text('• Organized emergency evidence logs'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildLabel('Phone Number'),
                      _buildTextField(
                        controller: _phone,
                        hint: 'Phone Number',
                        icon: Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 14),
                      _buildLabel('Password'),
                      _buildTextField(
                        controller: _pass,
                        hint: 'Password',
                        icon: Icons.lock_outline_rounded,
                        isPassword: true,
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
                            onPressed: () async {
                              try {
                                final phone = _phone.text.trim();
                                if (phone.isEmpty) {
                                  throw Exception(
                                    'Please enter your phone number.',
                                  );
                                }

                                final profileResponse = await Supabase
                                    .instance
                                    .client
                                    .from('profiles')
                                    .select('email')
                                    .eq('phone', phone)
                                    .maybeSingle();

                                final email =
                                    profileResponse?['email'] as String?;
                                if (email == null || email.isEmpty) {
                                  throw Exception(
                                    'No account found for that phone number.',
                                  );
                                }

                                await Supabase.instance.client.auth
                                    .signInWithPassword(
                                      email: email,
                                      password: _pass.text,
                                    );
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(_friendlyLoginError(e)),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Login to Dashboard',
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
                            onPressed: () => _openWebApp(context),
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 18,
                            ),
                            label: const Text('Open Deployed Web App'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: const Color(0xFF5F3F81),
                              side: const BorderSide(
                                color: SafeHerColors.stroke,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: onRegisterTap,
                    child: Text.rich(
                      TextSpan(
                        text: 'New here? ',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF7F5B96),
                          fontWeight: FontWeight.w600,
                        ),
                        children: const [
                          TextSpan(
                            text: 'Create an account',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper widget for Labels
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

  // Modern Input Builder
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
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
}
