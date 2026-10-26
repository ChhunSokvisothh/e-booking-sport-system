import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/data/auth_session.dart';
import '../../shared/models/models.dart';
import '../auth/profile_screen.dart';
import '../auth/auth_screen.dart';
import '../chatbot/chatbot_sheet.dart';
import '../facility/explore_screen.dart';
import '../facility/facility_providers.dart';
import 'booking_providers.dart';
import 'booking_screen.dart';
import 'dashboard_screen.dart';
import 'quick_book_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({
    super.key,
    this.isGuest = false,
  });

  final bool isGuest;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _openingQuickBook = false;

  void _prefetchBookings() {
    ref.invalidate(bookingHistoryProvider);
    ref.invalidate(dashboardSummaryProvider);
    Future.wait([
      ref.read(bookingHistoryProvider.future),
      ref.read(dashboardSummaryProvider.future),
    ]);
  }

  void _prefetchExplore() {
    final queryKey = serializeQuery(const {
      'featured': 'true',
      'page': '1',
      'page_size': '12',
    });
    ref.read(facilityListByQueryWithDiagnosticsProvider(queryKey).future);
    ref.read(liveSlotAvailabilityProvider('').future);
  }

  void _onDestinationSelected(int value) {
    if (!mounted) {
      return;
    }

    setState(() => _index = value);
    if (value == 1) {
      _prefetchExplore();
    }
    if (value == 2) {
      _prefetchBookings();
    }
  }

  void _goToTab(int index) {
    if (!mounted) {
      return;
    }
    setState(() => _index = index);
    if (index == 1) {
      _prefetchExplore();
    }
    if (index == 2) {
      _prefetchBookings();
    }
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  Future<void> _openQuickBook({
    LiveSlotAvailability? initialSlot,
    List<LiveSlotAvailability>? initialSlots,
    String? initialSportType,
    String? initialFacilityId,
  }) async {
    if (_openingQuickBook || !mounted) {
      return;
    }

    _openingQuickBook = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!mounted) {
        return;
      }
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => QuickBookScreen(
            initialSlot: initialSlot,
            initialSlots: initialSlots,
            initialSportType: initialSportType,
            initialFacilityId: initialFacilityId,
            onOpenDashboard: () => _goToTab(0),
          ),
        ),
      );
      if (mounted) {
        _goToTab(0);
      }
    } finally {
      _openingQuickBook = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final session = ref.watch(authSessionProvider);
    final isGuest = session == null || widget.isGuest;

    final pages = [
      DashboardScreen(
        onOpenQuickBook: (slots) => _openQuickBook(
          initialSlot: (slots == null || slots.isEmpty) ? null : slots.first,
          initialSlots: slots,
        ),
        onOpenExplore: () => _goToTab(1),
        onOpenHistory: () => _goToTab(2),
      ),
      ExploreScreen(onOpenDashboard: () => _goToTab(0)),
      const BookingScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Open AI booking assistant',
        child: FloatingActionButton.extended(
          onPressed: () {
            if (isGuest) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please login to use AI Assistant.')),
              );
              _openLogin();
              return;
            }

            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              sheetAnimationStyle: disableAnimations
                  ? AnimationStyle.noAnimation
                  : null,
              builder: (_) => const FractionallySizedBox(
                heightFactor: 0.92,
                child: ChatbotSheet(),
              ),
            );
          },
          label: const Text('AI Assistant'),
          icon: const Icon(Icons.auto_awesome),
          backgroundColor: const Color(0xFF13151B),
          foregroundColor: Colors.white,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.bookmark_outline), label: 'Bookings'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
