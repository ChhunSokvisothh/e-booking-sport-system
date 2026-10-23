import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/auth_session.dart';
import '../booking/booking_providers.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _pushEnabled = true;
  bool _offersEnabled = false;
  bool _loadingPrefs = true;

  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _cityController = TextEditingController(text: 'Phnom Penh');
  String _favoriteSport = 'Football';
  String? _profileImageBase64;

  static const _favoriteSports = ['Football', 'Billiard', 'Pickleball', 'Volleyball', 'Basketball', 'Futsal', 'Tennis', 'Badminton'];

  double _profileCompletion() {
    var score = 0.4;
    if (_displayNameController.text.trim().isNotEmpty) {
      score += 0.3;
    }
    if (_cityController.text.trim().isNotEmpty) {
      score += 0.2;
    }
    if (_favoriteSport.trim().isNotEmpty) {
      score += 0.1;
    }
    return score.clamp(0, 1).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _pushEnabled = prefs.getBool('profile_push_enabled') ?? true;
      _offersEnabled = prefs.getBool('profile_offers_enabled') ?? false;
      _displayNameController.text = prefs.getString('profile_display_name') ?? '';
      _cityController.text = prefs.getString('profile_city') ?? 'Phnom Penh';
      _favoriteSport = prefs.getString('profile_favorite_sport') ?? 'Football';
      _profileImageBase64 = prefs.getString('profile_image_base64');
      _loadingPrefs = false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('profile_push_enabled', _pushEnabled);
    await prefs.setBool('profile_offers_enabled', _offersEnabled);
    await prefs.setString('profile_display_name', _displayNameController.text.trim());
    await prefs.setString('profile_city', _cityController.text.trim());
    await prefs.setString('profile_favorite_sport', _favoriteSport);
    if (_profileImageBase64 != null && _profileImageBase64!.isNotEmpty) {
      await prefs.setString('profile_image_base64', _profileImageBase64!);
    } else {
      await prefs.remove('profile_image_base64');
    }
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 900, imageQuality: 80);
      if (picked == null) {
        return;
      }

      final bytes = await picked.readAsBytes();
      setState(() {
        _profileImageBase64 = base64Encode(bytes);
      });
      await _savePrefs();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to pick profile photo right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final tiny = width < 360;
    final session = ref.watch(authSessionProvider);
    final bookings = ref.watch(bookingHistoryProvider).value ?? const [];
    final isGuest = session == null;
    final email = session?.email ?? 'guest@player.local';
    final effectiveName = _displayNameController.text.trim().isEmpty ? email.split('@').first : _displayNameController.text.trim();
    final initials = effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'U';
    final confirmed = bookings.where((b) => b.status.toLowerCase() == 'confirmed').length;
    final pending = bookings.where((b) => b.status.toLowerCase() == 'pending').length;
    final spent = bookings.fold<double>(0, (sum, b) => sum + b.finalPrice);
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    final monthlySavings = bookings
      .where((b) => !b.startAt.isBefore(monthStart) && b.startAt.isBefore(nextMonthStart))
      .fold<double>(0, (sum, b) => sum + b.couponDiscount);
    final completion = _profileCompletion();

    if (_loadingPrefs) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0EA5E9).withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _AssetOrNetworkImage(
                  assetPath: 'assets/images/sports/profile_banner.jpg',
                  fallbackImageUrl:
                      'https://images.unsplash.com/photo-1517649763962-0c623066013b?auto=format&fit=crop&w=1200&q=80',
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F766E),
                    backgroundImage: (_profileImageBase64 != null && _profileImageBase64!.isNotEmpty)
                        ? MemoryImage(base64Decode(_profileImageBase64!))
                        : null,
                    child: (_profileImageBase64 == null || _profileImageBase64!.isEmpty)
                        ? Text(
                            initials,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          effectiveName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _GradientActionButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Upload Photo',
                  colors: const [Color(0xFF14B8A6), Color(0xFF0EA5E9)],
                  onTap: _pickProfilePhoto,
                ),
              ),
              const SizedBox(height: 10),
              if (tiny)
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: _GradientActionButton(
                        icon: isGuest ? Icons.login : Icons.sync,
                        label: isGuest ? 'Login' : 'Refresh Session',
                        colors: const [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                        onTap: () async {
                          if (isGuest) {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AuthScreen()),
                            );
                            return;
                          }

                          try {
                            await ref.read(authControllerProvider).refreshSession();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Session refreshed')),
                            );
                          } catch (_) {
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Unable to refresh session right now. Please try again.')),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: _GradientActionButton(
                        icon: isGuest ? Icons.lock_outline : Icons.logout,
                        label: isGuest ? 'Guest Mode' : 'Logout',
                        colors: const [Color(0xFFEF4444), Color(0xFFB91C1C)],
                        onTap: () async {
                          if (isGuest) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Login required to book and manage account.')),
                            );
                            return;
                          }
                          await ref.read(authControllerProvider).logout();
                        },
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _GradientActionButton(
                        icon: isGuest ? Icons.login : Icons.sync,
                        label: isGuest ? 'Login' : 'Refresh Session',
                        colors: const [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                        onTap: () async {
                          if (isGuest) {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AuthScreen()),
                            );
                            return;
                          }

                          try {
                            await ref.read(authControllerProvider).refreshSession();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Session refreshed')),
                            );
                          } catch (_) {
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Unable to refresh session right now. Please try again.')),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GradientActionButton(
                        icon: isGuest ? Icons.lock_outline : Icons.logout,
                        label: isGuest ? 'Guest Mode' : 'Logout',
                        colors: const [Color(0xFFEF4444), Color(0xFFB91C1C)],
                        onTap: () async {
                          if (isGuest) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Login required to book and manage account.')),
                            );
                            return;
                          }
                          await ref.read(authControllerProvider).logout();
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 380;
                return GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: compact ? 1.9 : 2.5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  children: [
                    _StatCard(label: 'Confirmed', value: '$confirmed', color: Colors.green),
                    _StatCard(label: 'Pending', value: '$pending', color: Colors.orange),
                    _StatCard(label: 'Spent', value: '\$${spent.toStringAsFixed(0)}', color: cs.primary),
                    _StatCard(label: 'Saved (Month)', value: '\$${monthlySavings.toStringAsFixed(0)}', color: const Color(0xFF0F766E)),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.savings_outlined, color: Color(0xFF047857)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  monthlySavings > 0
                      ? 'You saved \$${monthlySavings.toStringAsFixed(2)} this month with coupons.'
                      : 'No coupon savings yet this month. Apply promo codes at checkout to save more.',
                  style: const TextStyle(
                    color: Color(0xFF065F46),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account Health', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: completion,
                          minHeight: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${(completion * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  completion >= 0.95
                      ? 'Profile is complete and ready for fast checkout.'
                      : 'Complete your details to improve booking recommendations and assistant responses.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PillInfo(label: 'City', value: _cityController.text.trim().isEmpty ? 'Not set' : _cityController.text.trim()),
                    _PillInfo(label: 'Favorite', value: _favoriteSport),
                    _PillInfo(label: 'Notifications', value: _pushEnabled ? 'Enabled' : 'Disabled'),
                    _PillInfo(label: 'Offers', value: _offersEnabled ? 'Enabled' : 'Disabled'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                TextField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(labelText: 'Display Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _cityController,
                  decoration: const InputDecoration(labelText: 'Preferred City'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _favoriteSport,
                  decoration: const InputDecoration(labelText: 'Favorite Sport'),
                  items: _favoriteSports
                      .map((sport) => DropdownMenuItem<String>(value: sport, child: Text(sport)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _favoriteSport = value);
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await _savePrefs();
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile preferences saved')),
                      );
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                  'Preferences',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              SwitchListTile(
                value: _pushEnabled,
                onChanged: (v) async {
                  setState(() => _pushEnabled = v);
                  await _savePrefs();
                },
                title: const Text('Push Notifications'),
                subtitle: const Text('Booking reminders and updates'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _offersEnabled,
                onChanged: (v) async {
                  setState(() => _offersEnabled = v);
                  await _savePrefs();
                },
                title: const Text('Special Offers'),
                subtitle: const Text('Receive promo notifications'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Account Security'),
                subtitle: const Text('Your API keys stay private in local .env files'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Default City'),
                subtitle: Text(_cityController.text.trim().isEmpty ? 'Phnom Penh' : _cityController.text.trim(), style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.stars_rounded, color: cs.primary),
            ),
            title: const Text('Enterprise Booking Experience'),
            subtitle: const Text(
              'Live slot availability, dynamic pricing, booking history, and AI assistant are active.',
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillInfo extends StatelessWidget {
  const _PillInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _AssetOrNetworkImage extends StatelessWidget {
  const _AssetOrNetworkImage({
    required this.assetPath,
    required this.fallbackImageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String assetPath;
  final String fallbackImageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Image.network(
          fallbackImageUrl,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, networkError, networkStack) {
            return Container(
              width: width,
              height: height,
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: const Icon(Icons.image_not_supported_outlined),
            );
          },
        );
      },
    );
  }
}
