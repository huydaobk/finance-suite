import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Kết nối tới finance-api để pull giao dịch từ Telegram.
class FinanceSyncService {
  static const _prefKeyToken = 'finance_api_token';
  static const _prefKeyLastSync = 'finance_api_last_sync';
  static const _prefKeyBaseUrl = 'finance_api_url';

  Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKeyBaseUrl);
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();

    // fallback build-time define (optional)
    const defined = String.fromEnvironment('FINANCE_API_URL', defaultValue: '');
    if (defined.trim().isNotEmpty) return defined.trim();

    // dev fallback
    return 'http://10.0.2.2:8089';
  }

  Future<Uri> get _syncUri async => Uri.parse('${await _getBaseUrl()}/sync');
  Future<Uri> get _ackUri async => Uri.parse('${await _getBaseUrl()}/sync/ack');

  /// Lấy JWT token (cache vào SharedPreferences).
  ///
  /// Hiện tại app chỉ dùng token đã lưu sẵn ở local. Không commit credential vào mã nguồn.
  /// Nếu sau này cần login tương tác, nên chuyển sang flow nhập token / refresh token
  /// hoặc secure storage thay vì hardcode username/password.
  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefKeyToken);
    if (cached != null && cached.isNotEmpty) return cached;
    throw const FinanceSyncException(
      'Chưa có token đồng bộ. Hãy cấu hình FINANCE_API_URL và lưu token trước khi sync.',
    );
  }

  /// Pull danh sách giao dịch chưa sync từ server.
  Future<List<InboxTx>> fetchPending() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_prefKeyLastSync);

    Future<List<InboxTx>> runWithToken(String token) async {
      final base = await _syncUri;
      final uri = base.replace(
        queryParameters: lastSync != null && lastSync.isNotEmpty
            ? {'since': lastSync}
            : null,
      );
      final resp = await http
          .get(
            uri,
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        throw FinanceSyncException(
          'Lấy dữ liệu sync thất bại (${resp.statusCode}): ${resp.body}',
        );
      }

      final data = jsonDecode(resp.body);
      final rawItems = data['items'];
      if (rawItems is! List) {
        throw const FinanceSyncException(
          'Response /sync không đúng format: thiếu mảng items.',
        );
      }

      return rawItems
          .map((j) => InboxTx.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
    }

    var token = await _getToken();
    try {
      return await runWithToken(token);
    } on FinanceSyncException catch (e) {
      if (!e.message.contains('(401)')) rethrow;
      await prefs.remove(_prefKeyToken);
      throw const FinanceSyncException(
        'Token sync đã hết hạn hoặc không hợp lệ (401). Hãy cấp token mới rồi thử lại.',
      );
    }
  }

  /// Ack các ID đã import vào DB local.
  Future<void> ack(List<int> ids) async {
    if (ids.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    Future<void> runWithToken(String token) async {
      final ackUri = await _ackUri;
      final resp = await http
          .post(
            ackUri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'ids': ids}),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        throw FinanceSyncException(
          'Ack sync thất bại (${resp.statusCode}): ${resp.body}',
        );
      }

      await prefs.setString(
        _prefKeyLastSync,
        DateTime.now().toUtc().toIso8601String(),
      );
    }

    var token = await _getToken();
    try {
      await runWithToken(token);
    } on FinanceSyncException catch (e) {
      if (!e.message.contains('(401)')) rethrow;
      await prefs.remove(_prefKeyToken);
      throw const FinanceSyncException(
        'Token sync đã hết hạn hoặc không hợp lệ (401). Hãy cấp token mới rồi thử lại.',
      );
    }
  }
}

class FinanceSyncException implements Exception {
  const FinanceSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class InboxTx {
  final int id;
  final String type;
  final int amountVnd;
  final String? category;
  final String? wallet;
  final String? note;
  final String txDate;
  final String rawText;

  const InboxTx({
    required this.id,
    required this.type,
    required this.amountVnd,
    this.category,
    this.wallet,
    this.note,
    required this.txDate,
    required this.rawText,
  });

  factory InboxTx.fromJson(Map<String, dynamic> j) => InboxTx(
        id: j['id'] as int,
        type: j['type'] as String,
        amountVnd: j['amount_vnd'] as int,
        category: j['category'] as String?,
        wallet: j['wallet'] as String?,
        note: j['note'] as String?,
        txDate: j['tx_date'] as String,
        rawText: j['raw_text'] as String,
      );
}
