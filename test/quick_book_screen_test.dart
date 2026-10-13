import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_project/core/api_client.dart';
import 'package:my_project/features/booking/quick_book_screen.dart';
import 'package:my_project/features/facility/facility_providers.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required this.handler});

  final Future<List<dynamic>> Function(String path, Map<String, String>? query, String? token) handler;
  int getListCalls = 0;

  @override
  Future<List<dynamic>> getList(String path, [Map<String, String>? query, String? token]) {
    getListCalls += 1;
    return handler(path, query, token);
  }
}

Widget _buildSubject({required ApiClient client}) {
  return _buildSubjectWithOverrides(
    client: client,
    overrides: const [],
  );
}

Widget _buildSubjectWithOverrides({
  required ApiClient client,
  required List<Override> overrides,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      ...overrides,
    ],
    child: MaterialApp(
      home: QuickBookScreen(
        onOpenDashboard: () {},
      ),
    ),
  );
}

void main() {
  testWidgets('shows delayed retry action while loading slots', (tester) async {
    final neverCompletes = Completer<List<dynamic>>();
    final client = _FakeApiClient(
      handler: (path, query, token) {
        if (path == '/api/live-slots/') {
          return neverCompletes.future;
        }
        return Future<List<dynamic>>.value(const <dynamic>[]);
      },
    );

    await tester.pumpWidget(_buildSubject(client: client));

    expect(find.text('Loading available slots...'), findsOneWidget);
    expect(find.text('Retry Loading Slots'), findsNothing);

    await tester.pump(const Duration(seconds: 9));

    expect(find.text('Retry Loading Slots'), findsOneWidget);
    expect(find.text('This is taking longer than expected. You can retry now.'), findsOneWidget);

    await tester.tap(find.text('Retry Loading Slots'));
    await tester.pump();

    expect(client.getListCalls, greaterThanOrEqualTo(2));
  });

}
