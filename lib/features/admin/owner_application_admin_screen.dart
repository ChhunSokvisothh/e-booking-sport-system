import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/data/auth_session.dart';
import '../facility/facility_providers.dart';

class OwnerApplicationAdminScreen extends ConsumerStatefulWidget {
  const OwnerApplicationAdminScreen({super.key});

  @override
  ConsumerState<OwnerApplicationAdminScreen> createState() =>
      _OwnerApplicationAdminScreenState();
}

class _OwnerApplicationAdminScreenState
    extends ConsumerState<OwnerApplicationAdminScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _applications = [];
  final Set<int> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    final session = ref.read(authSessionProvider);
    if (session == null || !session.isSuperuser) {
      setState(() {
        _loading = false;
        _error = 'Superadmin access is required.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await ref.read(apiClientProvider).getList(
        '/api/admin/owner-applications/',
        const {'status': 'pending'},
        session.token,
      );
      if (!mounted) return;
      setState(() {
        _applications = rows.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _review(Map<String, dynamic> application, String decision) async {
    final session = ref.read(authSessionProvider);
    if (session == null) return;
    final id = application['id'] as int;

    setState(() => _processingIds.add(id));
    try {
      await ref.read(apiClientProvider).postJson(
        '/api/admin/owner-applications/$id/review/',
        {'decision': decision},
        token: session.token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(decision == 'approve'
              ? 'Owner application approved.'
              : 'Owner application rejected.'),
        ),
      );
      await _loadApplications();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh requests',
            onPressed: _loading ? null : _loadApplications,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 42),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadApplications,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadApplications,
                  child: _applications.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 140),
                            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
                            SizedBox(height: 12),
                            Center(
                              child: Text(
                                'No pending owner requests',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                            ),
                            SizedBox(height: 6),
                            Center(child: Text('New requests will appear here.')),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _applications.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final application = _applications[index];
                            final id = application['id'] as int;
                            final busy = _processingIds.contains(id);
                            final createdAt = DateTime.tryParse(
                              application['created_at']?.toString() ?? '',
                            );
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const CircleAvatar(
                                          child: Icon(Icons.stadium_outlined),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            application['venue_name']?.toString() ?? 'Unnamed venue',
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        Chip(
                                          label: Text((application['status']?.toString() ?? 'pending').toUpperCase()),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    _DetailRow(
                                      icon: Icons.email_outlined,
                                      text: application['applicant_email']?.toString() ?? 'No email provided',
                                    ),
                                    const SizedBox(height: 8),
                                    _DetailRow(
                                      icon: Icons.phone_outlined,
                                      text: application['contact_phone']?.toString().trim().isNotEmpty == true
                                          ? application['contact_phone'].toString()
                                          : 'No phone provided',
                                    ),
                                    if (createdAt != null) ...[
                                      const SizedBox(height: 8),
                                      _DetailRow(
                                        icon: Icons.schedule,
                                        text: 'Submitted ${createdAt.toLocal()}',
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: busy ? null : () => _review(application, 'reject'),
                                            icon: const Icon(Icons.close),
                                            label: const Text('Reject'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: theme.colorScheme.error,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: busy ? null : () => _review(application, 'approve'),
                                            icon: busy
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                : const Icon(Icons.check),
                                            label: const Text('Approve'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
