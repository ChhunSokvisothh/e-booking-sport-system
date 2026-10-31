import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import '../booking/home_shell.dart';
import '../owner/owner_home_shell.dart';
import 'data/auth_session.dart';
import '../../utils/validators.dart';
import '../../services/telegram_auth_service.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _venueNameCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSignUp = false;
  bool _isOwnerRegistration = false;
  bool _loading = false;
  bool _telegramLoading = false;
  String? _telegramStartCode;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    if (_telegramLoading) {
      TelegramAuthService.cancel();
    }
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _venueNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _loading = true);
    final auth = ref.read(authControllerProvider);

    try {
      if (_isSignUp) {
        if (_isOwnerRegistration) {
          await auth.ownerSignUp(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text.trim(),
            venueName: _venueNameCtrl.text.trim(),
            contactPhone: _contactPhoneCtrl.text.trim(),
          );
        } else {
          await auth.signUp(email: _emailCtrl.text.trim(), password: _passwordCtrl.text.trim());
        }
      } else {
        await auth.login(email: _emailCtrl.text.trim(), password: _passwordCtrl.text.trim());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isOwnerRegistration
                  ? 'Application submitted. Owner features unlock after admin approval.'
                  : _isSignUp
                      ? 'Account created and logged in.'
                      : 'Logged in',
            ),
          ),
        );

        final session = ref.read(authSessionProvider);
        final target = (session?.role == 'owner') ? const OwnerHomeShell() : const HomeShell();

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => target),
          (route) => false,
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.isEmpty ? 'Authentication failed. Please try again.' : message),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _telegramLogin() async {
    if (_loading || _telegramLoading) {
      return;
    }
    setState(() {
      _telegramLoading = true;
      _telegramStartCode = null;
    });
    try {
      final response = await TelegramAuthService.login(
        onCodeCreated: (code) {
          if (mounted) {
            setState(() => _telegramStartCode = code);
          }
        },
      );
      if (!mounted) {
        return;
      }
      final session = response['session'] is Map<String, dynamic>
          ? response['session'] as Map<String, dynamic>
          : response;
      await ref.read(authControllerProvider).saveLoginResponse(session);
      if (mounted) {
        final currentSession = ref.read(authSessionProvider);
        final target = (currentSession?.role == 'owner') ? const OwnerHomeShell() : const HomeShell();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => target),
          (route) => false,
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst(RegExp(r'^(Exception|TimeoutException):\s*'), '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _telegramLoading = false;
          _telegramStartCode = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0F172A),
              const Color(0xFF0F766E),
              cs.primary.withValues(alpha: 0.28),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 760;

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 920 : 440),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 460),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * 20),
                            child: child,
                          ),
                        );
                      },
                      child: isWide
                          ? Row(
                              children: [
                                Expanded(
                                  child: _AuthHero(isSignUp: _isSignUp),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _AuthCard(
                                    formKey: _formKey,
                                    isSignUp: _isSignUp,
                                    isOwnerRegistration: _isOwnerRegistration,
                                    loading: _loading,
                                    telegramLoading: _telegramLoading,
                                    telegramStartCode: _telegramStartCode,
                                    emailCtrl: _emailCtrl,
                                    passwordCtrl: _passwordCtrl,
                                    confirmCtrl: _confirmCtrl,
                                    venueNameCtrl: _venueNameCtrl,
                                    contactPhoneCtrl: _contactPhoneCtrl,
                                    onTelegramLogin: _telegramLogin,
                                    onPasswordChanged: () => setState(() {}),
                                    obscurePassword: _obscurePassword,
                                    obscureConfirm: _obscureConfirm,
                                    onToggleObscurePassword: () {
                                      setState(() => _obscurePassword = !_obscurePassword);
                                    },
                                    onToggleObscureConfirm: () {
                                      setState(() => _obscureConfirm = !_obscureConfirm);
                                    },
                                    onSubmit: _submit,
                                    onToggleMode: () {
                                      setState(() {
                                        _isSignUp = !_isSignUp;
                                        if (!_isSignUp) {
                                          _isOwnerRegistration = false;
                                        }
                                      });
                                    },
                                    onToggleOwnerRegistration: () {
                                      setState(() => _isOwnerRegistration = !_isOwnerRegistration);
                                    },
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                _AuthHero(isSignUp: _isSignUp),
                                const SizedBox(height: 14),
                                _AuthCard(
                                  formKey: _formKey,
                                  isSignUp: _isSignUp,
                                  isOwnerRegistration: _isOwnerRegistration,
                                  loading: _loading,
                                  telegramLoading: _telegramLoading,
                                  telegramStartCode: _telegramStartCode,
                                  emailCtrl: _emailCtrl,
                                  passwordCtrl: _passwordCtrl,
                                  confirmCtrl: _confirmCtrl,
                                  venueNameCtrl: _venueNameCtrl,
                                  contactPhoneCtrl: _contactPhoneCtrl,
                                  onTelegramLogin: _telegramLogin,
                                  onPasswordChanged: () => setState(() {}),
                                  obscurePassword: _obscurePassword,
                                  obscureConfirm: _obscureConfirm,
                                  onToggleObscurePassword: () {
                                    setState(() => _obscurePassword = !_obscurePassword);
                                  },
                                  onToggleObscureConfirm: () {
                                    setState(() => _obscureConfirm = !_obscureConfirm);
                                  },
                                  onSubmit: _submit,
                                  onToggleMode: () {
                                    setState(() {
                                      _isSignUp = !_isSignUp;
                                      if (!_isSignUp) {
                                        _isOwnerRegistration = false;
                                      }
                                    });
                                  },
                                  onToggleOwnerRegistration: () {
                                    setState(() => _isOwnerRegistration = !_isOwnerRegistration);
                                  },
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({required this.isSignUp});

  final bool isSignUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sports_soccer_rounded, color: Colors.white, size: 44),
          const SizedBox(height: 14),
          const Text(
            'E-Booking Sport',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSignUp
                ? 'Create your account and start exploring real-time slots instantly.'
                : 'Sign in and continue booking your favorite courts in seconds.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.90),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _HeroChip(label: 'Live Slot Availability'),
              _HeroChip(label: 'AI Booking Assistant'),
              _HeroChip(label: 'Fast Payment Confirmation'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.formKey,
    required this.isSignUp,
    required this.isOwnerRegistration,
    required this.loading,
    required this.telegramLoading,
    required this.telegramStartCode,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.venueNameCtrl,
    required this.contactPhoneCtrl,
    required this.onTelegramLogin,
    required this.onPasswordChanged,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.onToggleObscurePassword,
    required this.onToggleObscureConfirm,
    required this.onSubmit,
    required this.onToggleMode,
    required this.onToggleOwnerRegistration,
  });

  final GlobalKey<FormState> formKey;
  final bool isSignUp;
  final bool isOwnerRegistration;
  final bool loading;
  final bool telegramLoading;
  final String? telegramStartCode;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final TextEditingController venueNameCtrl;
  final TextEditingController contactPhoneCtrl;
  final VoidCallback onTelegramLogin;
  final VoidCallback onPasswordChanged;
  final bool obscurePassword;
  final bool obscureConfirm;
  final VoidCallback onToggleObscurePassword;
  final VoidCallback onToggleObscureConfirm;
  final VoidCallback onSubmit;
  final VoidCallback onToggleMode;
  final VoidCallback onToggleOwnerRegistration;

  @override
  Widget build(BuildContext context) {
    final password = passwordCtrl.text.trim();
    final passwordHasMinLength = password.length >= 8;
    final passwordHasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSignUp) ...[
                Text(
                  'Account type',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.person_outline),
                      label: Text('Book sports'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.storefront_outlined),
                      label: Text('Register venue'),
                    ),
                  ],
                  selected: {isOwnerRegistration},
                  onSelectionChanged: loading ? null : (_) => onToggleOwnerRegistration(),
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 18),
              ],
              Text(
                isSignUp
                    ? isOwnerRegistration
                        ? 'Register Your Venue'
                        : 'Create Account'
                    : 'Welcome Back',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                isSignUp
                    ? isOwnerRegistration
                        ? 'Create an owner account to manage your sports venue.'
                        : 'Use your email to join and start booking.'
                    : 'Login to access your account homepage.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                validator: Validators.email,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordCtrl,
                obscureText: obscurePassword,
                onChanged: (_) => onPasswordChanged(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: onToggleObscurePassword,
                    icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
                validator: Validators.password,
              ),
              if (isSignUp && isOwnerRegistration) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: venueNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Venue name',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Venue name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: contactPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contact phone (optional)',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
              ],
              if (isSignUp) ...[
                const SizedBox(height: 8),
                _PasswordRequirement(
                  label: 'At least 8 characters',
                  met: passwordHasMinLength,
                ),
                _PasswordRequirement(
                  label: 'One uppercase letter',
                  met: passwordHasUppercase,
                ),
              ],
              if (isSignUp) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmCtrl,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_person_outlined),
                    suffixIcon: IconButton(
                      onPressed: onToggleObscureConfirm,
                      icon: Icon(obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                  validator: (value) => Validators.confirmPassword(value, passwordCtrl.text),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: loading ? null : onSubmit,
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isSignUp ? 'Create account' : 'Login'),
                ),
              ),
              if (!isSignUp) ...[
                const SizedBox(height: 18),
                _TelegramOption(
                  isSignUp: false,
                  loading: telegramLoading,
                  startCode: telegramStartCode,
                  onOpenTelegram: TelegramAuthService.openTelegram,
                  onPressed: onTelegramLogin,
                  onCancel: TelegramAuthService.cancel,
                ),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: loading || telegramLoading ? null : onToggleMode,
                  child: Text(isSignUp ? 'Already have account? Login' : 'No account? Sign up'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TelegramOption extends StatelessWidget {
  const _TelegramOption({
    required this.isSignUp,
    required this.loading,
    required this.startCode,
    required this.onOpenTelegram,
    required this.onPressed,
    required this.onCancel,
  });

  final bool isSignUp;
  final bool loading;
  final String? startCode;
  final VoidCallback onOpenTelegram;
  final VoidCallback onPressed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final divider = Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(isSignUp ? 'or sign up with email' : 'or'),
        ),
        const Expanded(child: Divider()),
      ],
    );
    final button = Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: loading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF229ED9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontWeight: FontWeight.w500),
            ),
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.send_rounded),
                      SizedBox(width: 10),
                      Text('Continue with Telegram'),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Get booking updates from our bot',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        if (loading && startCode != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onOpenTelegram,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Telegram'),
          ),
          Text(
            'If Telegram only sends /start, copy and send this command in the bot chat:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 4),
          SelectableText(
            '/start $startCode',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
          ),
        ],
        if (loading)
          TextButton(onPressed: onCancel, child: const Text('Cancel Telegram sign-in')),
      ],
    );
    return Column(
      children: isSignUp
          ? [button, const SizedBox(height: 18), divider]
          : [divider, const SizedBox(height: 18), button],
    );
  }
}

class _PasswordRequirement extends StatelessWidget {
  const _PasswordRequirement({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.circle,
            size: 16,
            color: met ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}
