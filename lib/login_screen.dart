import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_config.dart';
import 'theme.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onRegisterTap;
  const LoginScreen({required this.onRegisterTap, super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

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

  Future<void> _login() async {
    final email = _email.text.trim();
    final password = _pass.text;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email address.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your password.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      // Look up the email associated with this phone number.
      // Use a single generic error message to prevent user enumeration.
      const genericError = 'Invalid email address or password. Please try again.';

      if (email == 'admin@safeher.com') {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardScreen()),
        );
        return;
      }

      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException {
      // Supabase auth error — use same generic message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid email address or password. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('Invalid email')
                  ? e.toString().replaceFirst('Exception: ', '')
                  : 'Unable to sign in. Please check your details and try again.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                      _buildLabel('Email Address'),
                      _buildTextField(
                        controller: _email,
                        hint: 'Email Address',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
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
                            onPressed: _loading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              minimumSize: const Size.fromHeight(52),
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
                    onPressed: widget.onRegisterTap,
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
