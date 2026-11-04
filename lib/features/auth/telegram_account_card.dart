import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/auth_session.dart';
import '../facility/facility_providers.dart';

class TelegramAccountCard extends ConsumerStatefulWidget {
  const TelegramAccountCard({super.key});

  @override
  ConsumerState<TelegramAccountCard> createState() => _TelegramAccountCardState();
}

class _TelegramAccountCardState extends ConsumerState<TelegramAccountCard> {
  bool _loadingStatus = true;
  bool _linking = false;
  bool _linked = false;
  String? _username;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      if (mounted) setState(() => _loadingStatus = false);
      return;
    }

    try {
      final result = await ref.read(apiClientProvider).getMap(
        '/api/auth/telegram/link/status/',
        token: session.token,
      );
      if (!mounted) return;
      setState(() {
        _linked = result['linked'] == true;
        _username = (result['telegram_username'] as String?)?.trim();
        _error = null;
        _loadingStatus = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        _loadingStatus = false;
      });
    }
  }

  Future<void> _startLinking() async {
    final session = ref.read(authSessionProvider);
    if (session == null || _linking) return;

    setState(() {
      _linking = true;
      _error = null;
    });

    try {
      final result = await ref.read(apiClientProvider).postJson(
        '/api/auth/telegram/link/start/',
        const <String, dynamic>{},
        token: session.token,
      );
      final telegramUrl = result['telegram_url'] as String?;
      if (telegramUrl == null || telegramUrl.isEmpty) {
        throw Exception('The server did not return a Telegram link.');
      }

      final opened = await launchUrl(
        Uri.parse(telegramUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        await _showManualLink(telegramUrl);
      }

      // Telegram confirms the binding through the bot webhook. Poll the
      // authenticated status endpoint; never trust a browser redirect.
      for (var attempt = 0; attempt < 150; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;

        final status = await ref.read(apiClientProvider).getMap(
          '/api/auth/telegram/link/status/',
          token: session.token,
        );
        if (status['linked'] == true) {
          if (!mounted) return;
          setState(() {
            _linked = true;
            _username = (status['telegram_username'] as String?)?.trim();
            _error = null;
          });
          return;
        }
      }

      if (mounted) {
        setState(() {
          _error = 'Linking timed out. If you already pressed Start in Telegram, refresh the status.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
      await _loadStatus();
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _showManualLink(String url) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open Telegram to continue'),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Open Telegram'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = _linked ? Colors.green : colors.onSurfaceVariant;
    final statusText = _loadingStatus
        ? 'Checking connection…'
        : _linked
            ? 'Connected' + (_username != null && _username!.isNotEmpty ? ' as @' + _username! : '')
            : 'Not connected';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF229ED9).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.send_rounded, color: Color(0xFF229ED9)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Telegram Account', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            _linked ? Icons.check_circle : Icons.circle_outlined,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              statusText,
                              style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh Telegram status',
                  onPressed: _loadingStatus || _linking ? null : _loadStatus,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _linked
                  ? 'Your Telegram account is connected. You can use it to sign in to E-Booking Sport.'
                  : 'Connect Telegram to your existing account. Open the bot and press Start to verify ownership.',
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loadingStatus || _linking || _linked ? null : _startLinking,
                icon: _linking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_linked ? Icons.verified_user : Icons.link),
                label: Text(
                  _linking
                      ? 'Waiting for Telegram confirmation…'
                      : _linked
                          ? 'Telegram Connected'
                          : 'Link Telegram',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF229ED9),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
