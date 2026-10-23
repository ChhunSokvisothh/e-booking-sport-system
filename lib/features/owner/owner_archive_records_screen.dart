import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/data/auth_session.dart';
import '../../shared/models/models.dart';
import '../facility/facility_providers.dart';

class OwnerArchiveRecordsScreen extends ConsumerStatefulWidget {
  const OwnerArchiveRecordsScreen({super.key});

  @override
  ConsumerState<OwnerArchiveRecordsScreen> createState() => _OwnerArchiveRecordsScreenState();
}

class _OwnerArchiveRecordsScreenState extends ConsumerState<OwnerArchiveRecordsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;
  String _searchText = '';
  List<Facility> _rows = const [];

  @override
  void initState() {
    super.initState();
    _loadArchivedFacilities();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom ? (_fromDate ?? now.subtract(const Duration(days: 90))) : (_toDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 3650)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked == null) {
      return;
    }

    setState(() {
      if (isFrom) {
        _fromDate = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
      } else {
        _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });

    await _loadArchivedFacilities();
  }

  Future<void> _loadArchivedFacilities() async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }

    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final query = <String, String>{'archived_only': 'true'};
      if (_searchText.trim().isNotEmpty) {
        query['q'] = _searchText.trim();
      }
      if (_fromDate != null) {
        query['archived_from'] = _fromDate!.toIso8601String();
      }
      if (_toDate != null) {
        query['archived_to'] = _toDate!.toIso8601String();
      }

      final list = await api.getList('/api/facilities/owner/', query, session.token);
      final rows = list.map((e) => Facility.fromJson(e as Map<String, dynamic>)).toList();
      rows.sort((a, b) {
        final aTs = a.archivedAt;
        final bTs = b.archivedAt;
        if (aTs == null && bTs == null) {
          return 0;
        }
        if (aTs == null) {
          return 1;
        }
        if (bTs == null) {
          return -1;
        }
        return bTs.compareTo(aTs);
      });

      if (!mounted) {
        return;
      }
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load archived records right now.')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    final dateTimeFmt = DateFormat('dd MMM yyyy, HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Archive Records')),
      body: RefreshIndicator(
        onRefresh: _loadArchivedFacilities,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (value) {
                      setState(() => _searchText = value);
                    },
                    onSubmitted: (_) => _loadArchivedFacilities(),
                    decoration: InputDecoration(
                      hintText: 'Search archived venue by name, location, or sport',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check_circle_outline),
                        onPressed: _loadArchivedFacilities,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: true),
                          icon: const Icon(Icons.date_range),
                          label: Text(
                            _fromDate == null ? 'From Date' : dateFmt.format(_fromDate!),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: false),
                          icon: const Icon(Icons.event_available),
                          label: Text(
                            _toDate == null ? 'To Date' : dateFmt.format(_toDate!),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _fromDate = null;
                          _toDate = null;
                          _searchText = '';
                          _searchCtrl.clear();
                        });
                        _loadArchivedFacilities();
                      },
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Clear Filters'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (_rows.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Text(
                  'No archived records found for the selected filters.',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                ),
              )
            else
              ..._rows.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                          '${item.locationName} • ${item.sportType.toUpperCase()}',
                          style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.archivedAt == null
                              ? 'Archive date: Not recorded'
                              : 'Archived on: ${dateTimeFmt.format(item.archivedAt!)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
