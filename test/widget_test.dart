import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_library/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('K Library opens in API mode when key is loaded', (tester) async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'DATA4LIBRARY_AUTH_KEY=test-key');
    await tester.pumpWidget(const KLibraryApp());
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('K Library'), findsOneWidget);
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('API 연결'), findsOneWidget);
  });
}
