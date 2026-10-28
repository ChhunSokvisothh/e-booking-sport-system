import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/network/api_client.dart';
import '../auth/data/auth_session.dart';
import '../facility/facility_providers.dart';

class OwnerProgramScreen extends ConsumerStatefulWidget {
  const OwnerProgramScreen({super.key});

  @override
  ConsumerState<OwnerProgramScreen> createState() => _OwnerProgramScreenState();
}

class _OwnerProgramScreenState extends ConsumerState<OwnerProgramScreen> {
  final _formKey = GlobalKey<FormState>();
  final _campus = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _price = TextEditingController(text: '20');
  final _phone = TextEditingController();
  final _imageUrl = TextEditingController();
  String _sport = 'football';
  bool _indoor = false;
  bool _busy = false;
  List<Map<String, dynamic>> _applications = [];
  Map<String, dynamic>? _subscription;
  Map<String, dynamic>? _analytics;
  String? _error;
  static const _sports = <String, String>{
    'football': 'Football', 'futsal': 'Futsal', 'basketball': 'Basketball',
    'badminton': 'Badminton', 'tennis': 'Tennis', 'volleyball': 'Volleyball',
    'pickleball': 'Pickleball', 'billiard': 'Billiard',
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
  }

  @override
  void dispose() {
    _campus.dispose();
    _description.dispose();
    _location.dispose();
    _price.dispose();
    _phone.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final session = ref.read(authSessionProvider);
    if (session == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.getList('/api/owner/applications/', null, session.token),
        api.getMap('/api/owner/subscription/', token: session.token),
      ]);
      if (!mounted) return;
      setState(() {
        _applications = (results[0] as List).cast<Map<String, dynamic>>();
        _subscription = results[1] as Map<String, dynamic>;
      });
      if (_subscription?['active'] == true) {
        final data = await api.getMap('/api/owner/analytics/', token: session.token);
        if (mounted) setState(() => _analytics = data);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) return;
    final session = ref.read(authSessionProvider);
    if (session == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(apiClientProvider).postJson('/api/owner/applications/', {
        'campus_name': _campus.text.trim(),
        'description': _description.text.trim(),
        'location_name': _location.text.trim(),
        'sport_type': _sport,
        'is_indoor': _indoor,
        'base_price_per_hour': _price.text.trim(),
        'contact_phone': _phone.text.trim(),
        'image_url': _imageUrl.text.trim(),
      }, token: session.token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application submitted for review.')));
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkout(int applicationId) async {
    final session = ref.read(authSessionProvider);
    if (session == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await ref.read(apiClientProvider).postJson('/api/owner/checkout/', {
        'application_id': applicationId,
      }, token: session.token);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Checkout prepared'),
          content: Text('Amount: ${result['currency']} ${result['amount']}\n\n${result['message']}\n\nA real payment provider must be connected before money can be collected.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
        ),
      );
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    if (session == null) {
      return Scaffold(appBar: AppBar(title: const Text('Sports Campus Owner')), body: const Center(child: Text('Please sign in to apply.')));
    }
    final hasOpenApplication = _applications.any((a) => ['pending', 'under_review', 'approved'].contains(a['status']));
    return Scaffold(
      appBar: AppBar(title: const Text('Sports Campus Owner')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Run your sports campus', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text('Apply to list your venue, manage facilities, and view booking performance. Owner access costs $20/month after approval.'),
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
            if (_subscription?['active'] == true) ...[
              const SizedBox(height: 16),
              _sectionTitle('Owner analytics'),
              _metricGrid(_analytics ?? const {}),
            ],
            const SizedBox(height: 18),
            _sectionTitle('Your applications'),
            if (_applications.isEmpty) const Text('No application submitted yet.'),
            ..._applications.map((a) => Card(
              child: ListTile(
                title: Text((a['campus_name'] ?? 'Campus').toString()),
                subtitle: Text('Status: ${(a['status'] ?? 'unknown').toString().replaceAll('_', ' ')}${(a['admin_note'] ?? '').toString().isEmpty ? '' : '\nNote: ${a['admin_note']}'}'),
                isThreeLine: (a['admin_note'] ?? '').toString().isNotEmpty,
                trailing: a['status'] == 'approved' && _subscription?['active'] != true && _subscription?['status'] != 'pending_payment'
                    ? TextButton(onPressed: _busy ? null : () => _checkout(a['id'] as int), child: const Text('Pay $20/mo'))
                    : null,
              ),
            )),
            if (_subscription?['active'] == true)
              Card(child: ListTile(leading: const Icon(Icons.verified), title: const Text('Owner subscription active'), subtitle: Text('Expires: ${_subscription?['expires_at'] ?? 'not available'}')))
            else if (_subscription?['status'] == 'pending_payment')
              const Card(child: ListTile(leading: Icon(Icons.hourglass_top), title: Text('Payment pending'), subtitle: Text('Checkout is recorded, but no payment provider is connected yet. Owner tools remain locked until payment is verified.')))
            else if (!hasOpenApplication) ...[
              const SizedBox(height: 18),
              _sectionTitle('Apply to become an owner'),
              Form(
                key: _formKey,
                child: Column(children: [
                  _field(_campus, 'Campus / venue name'),
                  _field(_description, 'Campus description', maxLines: 3),
                  _field(_location, 'Full location / address'),
                  _field(_phone, 'Contact phone (optional)', required: false, keyboardType: TextInputType.phone),
                  _field(_imageUrl, 'Venue image URL (optional)', required: false, keyboardType: TextInputType.url),
                  _field(_price, 'Hourly price (USD)', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _sport,
                    decoration: const InputDecoration(labelText: 'Main sport', border: OutlineInputBorder()),
                    items: _sports.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setState(() => _sport = v ?? 'football'),
                  ),
                  SwitchListTile(title: const Text('Indoor campus'), value: _indoor, onChanged: (v) => setState(() => _indoor = v)),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: _busy ? null : _submitApplication,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Submit application'),
                  )),
                ]),
              ),
            ],
            const SizedBox(height: 24),
            const Text('Payment is not collected in this build. A verified payment provider callback must be configured before subscriptions can activate.', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
  );

  Widget _field(TextEditingController controller, String label, {int maxLines = 1, bool required = true, TextInputType? keyboardType}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: (value) {
        if (!required) return null;
        if ((value ?? '').trim().isEmpty) return 'This field is required';
        if (label == 'Hourly price (USD)' && (double.tryParse(value!.trim()) == null || double.parse(value.trim()) <= 0)) return 'Enter a valid positive price';
        return null;
      },
    ),
  );

  Widget _metricGrid(Map<String, dynamic> data) {
    final metrics = <(String, String)>[
      ('Campuses', '${data['campus_count'] ?? 0}'),
      ('Facilities', '${data['facility_count'] ?? 0}'),
      ('Bookings', '${data['booking_count'] ?? 0}'),
      ('Paid revenue', '$${data['revenue'] ?? '0.00'}'),
    ];
    return GridView.count(
      crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.9, mainAxisSpacing: 8, crossAxisSpacing: 8,
      children: metrics.map((m) => Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(m.$1, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Text(m.$2, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
      ))).toList(),
    );
  }
}
