import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'local_dev_config.dart' as local_dev;

class AppConfig {
  static const bool _isReleaseBuild = bool.fromEnvironment('dart.vm.product');
  static const String _definedAuthKey = String.fromEnvironment(
    'DATA4LIBRARY_AUTH_KEY',
  );
  static const String data4LibraryBaseUrl = 'https://data4library.kr/api';

  static String get data4LibraryAuthKey {
    final fromDefine = _definedAuthKey.trim();
    if (_isReleaseBuild && fromDefine.isNotEmpty) {
      throw StateError(
        'Release builds must not include DATA4LIBRARY_AUTH_KEY in the Flutter app. Remove the direct key before producing APK/AAB.',
      );
    }
    if (fromDefine.isNotEmpty) return fromDefine;

    final fromDotEnv = _dotenvValue('DATA4LIBRARY_AUTH_KEY');
    if (_isReleaseBuild && fromDotEnv.isNotEmpty) {
      throw StateError(
        'Release builds must not load DATA4LIBRARY_AUTH_KEY from .env. Remove the key before producing APK/AAB.',
      );
    }
    if (fromDotEnv.isNotEmpty) return fromDotEnv;

    return _localDevData4LibraryAuthKey;
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

    final fromDotEnv = _dotenvValue('PURCHASE_API_BASE_URL');
    if (fromDotEnv.isNotEmpty) return _trimSlash(fromDotEnv);

    return _trimSlash(_localDevPurchaseApiBaseUrl);
  }

  static bool get purchaseEnabled {
    final raw = _definedPurchaseEnabled.trim().isNotEmpty
        ? _definedPurchaseEnabled
        : _firstNonEmpty([
            _dotenvValue('ENABLE_PURCHASE_TAB'),
            _localDevEnablePurchaseTab,
            'true',
          ]);
    return !['false', '0', 'no'].contains(raw.toLowerCase());
  }

  static String get _localDevData4LibraryAuthKey {
    var value = '';
    assert(() {
      value = local_dev.localDevData4LibraryAuthKey.trim();
      return true;
    }());
    return value;
  }

  static String get _localDevPurchaseApiBaseUrl {
    var value = '';
    assert(() {
      value = local_dev.localDevPurchaseApiBaseUrl.trim();
      return true;
    }());
    return value;
  }

  static String get _localDevEnablePurchaseTab {
    var value = '';
    assert(() {
      value = local_dev.localDevEnablePurchaseTab.trim();
      return true;
    }());
    return value;
  }

  static String _dotenvValue(String key) {
    try {
      return (dotenv.maybeGet(key, fallback: '') ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static String _trimSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
