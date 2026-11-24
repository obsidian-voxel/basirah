import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haram_blur/main.dart';
import 'package:haram_blur/services/blur_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await blurEngine.init();
  });

  testWidgets('app launches on the dashboard with protection controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BasirahApp());
    await tester.pumpAndSettle();

    // The hero shows the protection mode and the streak card is present.
    expect(find.text('Off'), findsWidgets);
    // With no history the card invites the user to start a streak.
    expect(find.text('Start your streak'), findsOneWidget);
    expect(find.text('Advanced Settings'), findsOneWidget);
    expect(find.text('Block Newly Installed Apps'), findsOneWidget);
  });

  testWidgets('bottom navigation switches between the five tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BasirahApp());
    await tester.pumpAndSettle();

    for (final label in ['Dashboard', 'Block list', 'Premium', 'Calm',
      'Support']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('Premium'));
    await tester.pumpAndSettle();
    expect(find.text('Why pay for 12+ apps when one is enough?'), findsOneWidget);

    await tester.tap(find.text('Calm'));
    await tester.pumpAndSettle();
    expect(find.text('Enter Calm Mode'), findsOneWidget);

    await tester.tap(find.text('Block list'));
    await tester.pumpAndSettle();
    expect(find.text('Blocklist'), findsOneWidget);
    expect(find.text('Add Items'), findsOneWidget);
  });
}
