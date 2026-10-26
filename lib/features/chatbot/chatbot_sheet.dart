import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/data/auth_session.dart';
import '../../shared/models/models.dart';
import '../booking/booking_providers.dart';
import '../booking/mock_payment_screen.dart';
import '../facility/facility_providers.dart';

class ChatbotSheet extends ConsumerStatefulWidget {
  const ChatbotSheet({super.key});

  @override
  ConsumerState<ChatbotSheet> createState() => _ChatbotSheetState();
}

class _ChatbotSheetState extends ConsumerState<ChatbotSheet> {
  final _ctrl = TextEditingController();
  final _messagesScrollCtrl = ScrollController();
  final String _chatbotSessionId = 'chat-${DateTime.now().millisecondsSinceEpoch}';
  bool _loading = false;
  List<ChatSuggestion> _suggestions = [];
  ChatSuggestion? _exactSuggestionForAction;
  final List<_ChatEntry> _messages = [
    const _ChatEntry(
      role: _ChatRole.assistant,
      text: 'Tell me your sport, date, time, and duration. Example: book outdoor football tomorrow 5pm for 2 hours.',
    ),
  ];

  static const List<String> _quickPrompts = [
    'book outdoor football tomorrow 5pm for 2 hours',
    'find indoor badminton today 8pm for 1 hour',
    'show available slots at blue chalk billiard lounge tomorrow',
    'book blue chlak billiard lounge tomorrow 8pm for 1 hour',
    'available slots at tiger futsal arena tonight',
    'what time is available at precision cue arena tomorrow',
    'blue chalk price and location',
    'contact for tiger futsal arena',
    'football rules',
    'football field size',
    'billiard beginner tips',
    'booking faq',
    'payment faq',
    'cancellation faq',
    'I paid, check payment status',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _messagesScrollCtrl.dispose();
    super.dispose();
  }

  void _scrollMessagesToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesScrollCtrl.hasClients) {
        return;
      }
      _messagesScrollCtrl.animateTo(
        _messagesScrollCtrl.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  List<Map<String, dynamic>> _serializedSuggestions() {
    return _suggestions
        .map(
          (e) => {
            'option_id': e.optionId,
            'facility_name': e.facilityName,
            'start_at': e.startAt,
            'end_at': e.endAt,
            'duration_hours': e.durationHours,
            'base_price': e.basePrice,
            'weather_discount': e.weatherDiscount,
            'empty_slot_discount': e.emptySlotDiscount,
            'final_price': e.finalPrice,
            'currency': e.currency,
            'rain_mm': e.rainMm,
            'current_bookings': e.currentBookings,
            'max_bookings': e.maxBookings,
            'available_spots': e.availableSpots,
            'is_available': e.isAvailable,
          },
        )
        .toList();
  }

  void _appendMessage(_ChatRole role, String text) {
    setState(() {
      _messages.add(_ChatEntry(role: role, text: text));
    });
    _scrollMessagesToBottom();
  }

  int? _parseBookingId(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  String _friendlyError(Object error) {
    final text = error.toString().trim();
    if (text.startsWith('Exception:')) {
      return text.replaceFirst('Exception:', '').trim();
    }
    return text;
  }

  Future<void> _refreshBookingViews() async {
    ref.invalidate(bookingHistoryProvider);
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(liveSlotAvailabilityProvider);
    await Future.wait([
      ref.read(bookingHistoryProvider.future),
      ref.read(dashboardSummaryProvider.future),
    ]);
  }

  String _displayVenueName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final minusSuffix = RegExp(r'\s*-\s*(pitch|court|table)\s*(#?\d+|[a-z])\s*$', caseSensitive: false);
    final spaceSuffix = RegExp(r'\s+(pitch|court|table)\s*(#?\d+|[a-z])\s*$', caseSensitive: false);
    return trimmed.replaceAll(minusSuffix, '').replaceAll(spaceSuffix, '').trim();
  }

  String _buildSuggestionSummary(List<ChatSuggestion> suggestions, {String? preface}) {
    if (suggestions.isEmpty) {
      return 'No matching slots were found. Try another time or venue.';
    }

    final lines = <String>[];
    for (var i = 0; i < suggestions.length; i++) {
      final s = suggestions[i];
      final parsedStart = DateTime.tryParse(s.startAt);
      final startLabel = parsedStart == null
          ? s.startAt
          : DateFormat('EEE dd MMM, HH:mm').format(parsedStart);
      final parsedEnd = DateTime.tryParse(s.endAt) ?? parsedStart?.add(Duration(minutes: (s.durationHours * 60).round()));
      final endLabel = parsedEnd == null ? '' : DateFormat('HH:mm').format(parsedEnd);
      final displayVenue = _displayVenueName(s.facilityName);
      lines.add(
        '${i + 1}) $startLabel${endLabel.isEmpty ? '' : ' - $endLabel'} | $displayVenue | ${s.finalPrice} ${s.currency} | ${s.availableSpots} spot(s)',
      );
    }

    final lead = (preface == null || preface.trim().isEmpty)
        ? 'Here are the available slots:'
        : preface.trim();
    return '$lead\n${lines.join('\n')}';
  }

  Future<void> _openPayment({
    int? bookingId,
    String? feedbackMessage,
    ChatSuggestion? suggestion,
    Map<String, dynamic>? chatOption,
    Map<String, dynamic>? paymentQuote,
  }) async {
    if (!mounted) {
      return;
    }

    ChatSuggestion? effectiveSuggestion = suggestion;
    if (effectiveSuggestion == null && chatOption != null) {
      try {
        effectiveSuggestion = ChatSuggestion.fromJson(chatOption);
      } catch (_) {
        effectiveSuggestion = null;
      }
    }
    if (effectiveSuggestion == null && bookingId != null) {
      try {
        final bookings = await ref.read(bookingHistoryProvider.future);
        BookingItem? row;
        for (final item in bookings) {
          if (item.id == bookingId) {
            row = item;
            break;
          }
        }
        if (row != null) {
          final durationHours = row.endAt.difference(row.startAt).inMinutes / 60;
          effectiveSuggestion = ChatSuggestion(
            optionId: '$bookingId',
            facilityName: row.facilityName,
            startAt: row.startAt.toIso8601String(),
            endAt: row.endAt.toIso8601String(),
            durationHours: durationHours,
            finalPrice: row.finalPrice.toStringAsFixed(2),
            currency: 'USD',
            currentBookings: 0,
            maxBookings: 0,
            availableSpots: 0,
            isAvailable: true,
            basePrice: row.finalPrice.toStringAsFixed(2),
            weatherDiscount: '0.00',
            emptySlotDiscount: '0.00',
            rainMm: 0,
            isExactMatch: false,
          );
        }
      } catch (_) {
        // Fallback keeps payment flow alive even if prefetch fails.
      }
    }

    if (!mounted) {
      return;
    }

    final parsedStart = DateTime.tryParse(effectiveSuggestion?.startAt ?? '');
    final startAt = parsedStart;
    final parsedEnd = DateTime.tryParse(effectiveSuggestion?.endAt ?? '');
    final endAt = parsedEnd ?? startAt?.add(Duration(minutes: ((effectiveSuggestion?.durationHours ?? 0) * 60).round()));

    final paymentResult = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => MockPaymentScreen(
          bookingId: bookingId,
          chatOption: chatOption,
          paymentQuote: paymentQuote,
          bookingSource: 'chatbot',
          chatbotSessionId: _chatbotSessionId,
          facilityName: effectiveSuggestion?.facilityName,
          startAt: startAt,
          endAt: endAt,
          totalPrice: double.tryParse(effectiveSuggestion?.finalPrice ?? ''),
          currency: effectiveSuggestion?.currency ?? 'USD',
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    if (paymentResult == true) {
      await _refreshBookingViews();
      _appendMessage(_ChatRole.assistant, 'Payment completed. Verifying booking status in database...');
      await _sendSystemMessage('I paid, check payment status');
      return;
    }

    if (paymentResult == 'refresh_slots') {
      await _refreshBookingViews();
      _appendMessage(_ChatRole.assistant, 'Payment window expired. I refreshed live slots. Please choose a new time and I can help you book again.');
      return;
    }

    if (feedbackMessage != null && feedbackMessage.isNotEmpty) {
      _appendMessage(_ChatRole.assistant, feedbackMessage);
    }
  }

  Future<void> _sendSystemMessage(String message) async {
    _ctrl.text = message;
    await _send();
  }

  Future<void> _send() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) {
      return;
    }

    _ctrl.clear();
    _appendMessage(_ChatRole.user, input);

    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    final session = ref.read(authSessionProvider);
    if (session == null) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _appendMessage(_ChatRole.assistant, 'Please login first.');
      }
      return;
    }

    try {
      final result = await api.postJson('/api/chat/', {
        'message': input,
        'booking_source': 'chatbot',
        'chatbot_session_id': _chatbotSessionId,
        'suggestions': _serializedSuggestions(),
      }, token: session.token);

      final type = (result['type'] as String?) ?? 'unknown';
      final text = (result['text'] as String?) ?? 'No response';

      if (type == 'suggestions') {
        final raw = result['suggestions'] as List<dynamic>? ?? [];
        final parsedSuggestions = raw.map((e) => ChatSuggestion.fromJson(e as Map<String, dynamic>)).toList();
        final exactRaw = result['exact_slot'] as Map<String, dynamic>?;
        ChatSuggestion? exact;
        if (exactRaw != null) {
          exact = ChatSuggestion.fromJson(exactRaw);
        } else {
          for (final s in parsedSuggestions) {
            if (s.isExactMatch) {
              exact = s;
              break;
            }
          }
        }
        setState(() {
          _suggestions = parsedSuggestions;
          _exactSuggestionForAction = exact;
        });
        _appendMessage(_ChatRole.assistant, _buildSuggestionSummary(parsedSuggestions, preface: text));
      } else if (type == 'no_slots') {
        setState(() {
          _suggestions = [];
          _exactSuggestionForAction = null;
        });
        _appendMessage(_ChatRole.assistant, text);
      } else if (type == 'payment_quote') {
        final selected = result['selected_option'] as Map<String, dynamic>?;
        final quote = result['payment_quote'] as Map<String, dynamic>?;
        setState(() {
          _suggestions = [];
          _exactSuggestionForAction = null;
        });
        _appendMessage(_ChatRole.assistant, text);
        if (selected != null) {
          ChatSuggestion? parsed;
          try {
            parsed = ChatSuggestion.fromJson(selected);
          } catch (_) {
            parsed = null;
          }
          await _openPayment(
            feedbackMessage: text,
            suggestion: parsed,
            chatOption: selected,
            paymentQuote: quote,
          );
        }
      } else if (type == 'auto_booking_created' || type == 'pending_booking_created') {
        final bookingId = _parseBookingId(result['booking_id']);
        setState(() {
          _suggestions = [];
          _exactSuggestionForAction = null;
        });
        _appendMessage(_ChatRole.assistant, text);
        if (bookingId != null) {
            await _refreshBookingViews();
            await _openPayment(bookingId: bookingId, feedbackMessage: text);
        }
      } else {
        _appendMessage(_ChatRole.assistant, text);
        if (type == 'payment_confirmed') {
          await _refreshBookingViews();
          setState(() {
            _suggestions = [];
            _exactSuggestionForAction = null;
          });
        }
      }
    } catch (e) {
      _appendMessage(
        _ChatRole.assistant,
        _friendlyError(e).isEmpty
            ? 'We are unable to process your request at the moment. Please try again in a few moments.'
            : _friendlyError(e),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _book(ChatSuggestion s) async {
    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    final session = ref.read(authSessionProvider);
    if (session == null) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _appendMessage(_ChatRole.assistant, 'Please login first.');
      }
      return;
    }

    try {
      final result = await api.postJson('/api/chat/', {
        'message': 'confirm',
        'booking_source': 'chatbot',
        'chatbot_session_id': _chatbotSessionId,
        'selected_option_id': s.optionId,
        'suggestions': _serializedSuggestions(),
      }, token: session.token);

      final text = (result['text'] as String?) ?? 'Please simulate payment to confirm this slot.';
      final selected = result['selected_option'] as Map<String, dynamic>?;
      final quote = result['payment_quote'] as Map<String, dynamic>?;
      final bookingId = _parseBookingId(result['booking_id']);
      _appendMessage(_ChatRole.assistant, text);
      if (selected != null) {
        await _openPayment(
          feedbackMessage: text,
          suggestion: s,
          chatOption: selected,
          paymentQuote: quote,
        );
      } else if (bookingId != null) {
        await _refreshBookingViews();
        await _openPayment(bookingId: bookingId, feedbackMessage: text, suggestion: s);
      }
      if (mounted) {
        setState(() {
          _exactSuggestionForAction = null;
        });
      }
    } catch (e) {
      _appendMessage(
        _ChatRole.assistant,
        _friendlyError(e).isEmpty
            ? 'We could not complete your booking request right now. Please try again shortly.'
            : _friendlyError(e),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final tiny = width < 360;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withValues(alpha: 0.18),
                    cs.tertiary.withValues(alpha: 0.14),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI Booking Assistant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: _messagesScrollCtrl,
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final entry = _messages[index];
                  final isUser = entry.role == _ChatRole.user;
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: EdgeInsets.symmetric(horizontal: tiny ? 10 : 12, vertical: tiny ? 8 : 10),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (tiny ? 0.82 : 0.72)),
                      decoration: BoxDecoration(
                        color: isUser ? cs.primary : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
                      ),
                      child: Text(
                        entry.text,
                        style: TextStyle(color: isUser ? cs.onPrimary : cs.onSurface),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                labelText: 'Type your request',
                hintText: 'book outdoor football tomorrow 5pm for 2 hours',
              ),
              onSubmitted: (_) => _loading ? null : _send(),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loading ? null : _send,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('Ask AI'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: tiny ? 34 : 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickPrompts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final prompt = _quickPrompts[index];
                  return ActionChip(
                    label: Text(
                      prompt,
                      style: TextStyle(fontSize: tiny ? 11.5 : 12.5),
                    ),
                    labelPadding: EdgeInsets.symmetric(horizontal: tiny ? 4 : 6),
                    onPressed: _loading
                        ? null
                        : () {
                            _ctrl.text = prompt;
                            _send();
                          },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            if (_exactSuggestionForAction != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Exact Slot Found',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _loading ? null : () => _book(_exactSuggestionForAction!),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Auto-book Exact'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => _appendMessage(
                                    _ChatRole.assistant,
                                    'Manual mode selected. Review the slots below and tap Book this on your preferred one.',
                                  ),
                          icon: const Icon(Icons.view_list),
                          label: const Text('Browse Manually'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _suggestions.isEmpty
                  ? const SizedBox.shrink()
                  : ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: tiny ? 300 : 240),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          final s = _suggestions[index];
                          final parsedStart = DateTime.tryParse(s.startAt);
                          final startLabel = parsedStart == null
                              ? s.startAt
                              : DateFormat('EEE, dd MMM • HH:mm').format(parsedStart);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final stackButton = constraints.maxWidth < 380;
                                  final info = Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: s.isExactMatch ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          s.isExactMatch ? 'Exact Match' : 'Alternative',
                                          style: TextStyle(
                                            color: s.isExactMatch ? const Color(0xFF047857) : const Color(0xFFB45309),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${s.facilityName} • ${s.finalPrice} ${s.currency}',
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$startLabel • ${s.durationHours.toStringAsFixed(0)} hour(s)',
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Slots: ${s.availableSpots} free (${s.currentBookings}/${s.maxBookings} booked)',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  );

                                  final action = FilledButton.tonal(
                                    onPressed: _loading || !s.isAvailable ? null : () => _book(s),
                                    child: Text(s.isAvailable ? 'Book this' : 'Full'),
                                  );

                                  if (stackButton) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        info,
                                        const SizedBox(height: 8),
                                        SizedBox(width: double.infinity, child: action),
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      Expanded(child: info),
                                      const SizedBox(width: 10),
                                      action,
                                    ],
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ChatRole { user, assistant }

class _ChatEntry {
  const _ChatEntry({required this.role, required this.text});

  final _ChatRole role;
  final String text;
}
