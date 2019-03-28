import 'package:flutter_test/flutter_test.dart';
import 'package:flight_tracker/main.dart';

void main() {
  testWidgets('Test', (WidgetTester tester) async {
    await tester.pumpWidget(App());
  });
}
