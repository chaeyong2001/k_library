import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const String _definedAuthKey = String.fromEnvironment(
    'DATA4LIBRARY_AUTH_KEY',
  );
  static const String data4LibraryBaseUrl = 'https://data4library.kr/api';

  static String get data4LibraryAuthKey {
    final fromDefine = _definedAuthKey.trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    return (dotenv.maybeGet('DATA4LIBRARY_AUTH_KEY', fallback: '') ?? '')
        .trim();
  }

  static bool get hasApiKey => data4LibraryAuthKey.isNotEmpty;
  static bool get isDemoMode => !hasApiKey;
  static String get dataMode => isDemoMode ? 'demo' : 'api';
  static String get dataModeLabel =>
      isDemoMode ? '데모 데이터 사용 중' : '도서관 정보나루 API 연결됨';

  static const String _definedPurchaseBaseUrl = String.fromEnvironment(
    'PURCHASE_API_BASE_URL',
  );
  static const String _definedPurchaseEnabled = String.fromEnvironment(
    'ENABLE_PURCHASE_TAB',
    defaultValue: 'true',
  );

  static String get purchaseApiBaseUrl {
    final fromDefine = _definedPurchaseBaseUrl.trim();
    if (fromDefine.isNotEmpty) return _trimSlash(fromDefine);
    try {
      return _trimSlash(
        (dotenv.maybeGet('PURCHASE_API_BASE_URL', fallback: '') ?? '').trim(),
      );
    } catch (_) {
      return '';
    }
  }

  static bool get purchaseEnabled {
    final raw = _definedPurchaseEnabled.trim().isNotEmpty
        ? _definedPurchaseEnabled
        : (() {
            try {
              return dotenv.maybeGet('ENABLE_PURCHASE_TAB', fallback: 'true') ??
                  'true';
            } catch (_) {
              return 'true';
            }
          })();
    return !['false', '0', 'no'].contains(raw.toLowerCase());
  }

  static String _trimSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
