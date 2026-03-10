import 'package:finance_manager_app/core/sync/finance_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoginResult.fromJson', () {
    test('đọc access_token chuẩn từ API', () {
      final result = LoginResult.fromJson({
        'access_token': 'abc123',
        'token_type': 'bearer',
        'expires_in_days': 14,
      });

      expect(result.token, 'abc123');
      expect(result.tokenType, 'bearer');
      expect(result.expiresInDays, 14);
    });

    test('fallback sang key token cũ nếu cần tương thích ngược', () {
      final result = LoginResult.fromJson({
        'token': 'legacy-token',
        'token_type': 'bearer',
        'expires_in_days': '7',
      });

      expect(result.token, 'legacy-token');
      expect(result.tokenType, 'bearer');
      expect(result.expiresInDays, 7);
    });

    test('ném lỗi nếu thiếu cả access_token lẫn token', () {
      expect(
        () => LoginResult.fromJson({
          'token_type': 'bearer',
        }),
        throwsA(isA<FinanceSyncException>()),
      );
    });
  });
}
