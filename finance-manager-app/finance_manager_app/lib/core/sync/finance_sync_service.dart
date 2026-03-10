import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Kết nối tới finance-api để pull giao dịch từ Telegram.
class FinanceSyncService {
  static const _baseUrl = 'http://14.225.222.53:8089'; // VPS via nginx
  static const _username = 'huy';
  static const _password = 'Finance@2026';
  static const _prefKeyToken = 'finance_api_token';
  static const _prefKeyLastSync = 'finance_api_last_sync';

  /// Lấy JWT token (cache vào SharedPreferences).
  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefKeyToken);
    if (cached != null && cached.isNotEmpty) return cached;
    return _login(prefs);
  }

  Future<String> _login(SharedPreferences prefs) async {
    final resp = await http
        .post(
          Uri.parse('$_baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': _username, 'password': _password}),
        )
        .timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw const FinanceSyncException(
        'Đăng nhập finance-api thất bại: kiểm tra lại finance-api hoặc tài khoản.',
      );
    }

    final data = jsonDecode(resp.body);
    final token = data['access_token'];
    if (token is! String || token.isEmpty) {
      throw const FinanceSyncException('Finance API không trả access_token hợp lệ.');
    }

    await prefs.setString(_prefKeyToken, token);
    return token;
  }

  /// Pull danh sách giao dịch chưa sync từ server.
  Future<List<InboxTx>> fetchPending() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_prefKeyLastSync);

    Future<List<InboxTx>> runWithToken(String token) async {
      final uri = Uri.parse('$_baseUrl/sync').replace(
        queryParameters:
            lastSync != null && lastSync.isNotEmpty ? {'since': lastSync} : null,
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

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
      token = await _login(prefs);
      return runWithToken(token);
    }
  }

  /// Ack các ID đã import vào DB local.
  Future<void> ack(List<int> ids) async {
    if (ids.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    Future<void> runWithToken(String token) async {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/sync/ack'),
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
      token = await _login(prefs);
      await runWithToken(token);
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
