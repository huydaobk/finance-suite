import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Kết nối tới finance-api để pull giao dịch từ Telegram.
class FinanceSyncService {
  FinanceSyncService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const _prefKeyToken = 'finance_api_token';
  static const _prefKeyLastSync = 'finance_api_last_sync';
  static const _prefKeyBaseUrl = 'finance_api_url';
  static const _prefKeyUsername = 'finance_api_username';
  static const _prefKeyPassword = 'finance_api_password';

  final http.Client _httpClient;

  Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKeyBaseUrl);
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();

    const defined = String.fromEnvironment('FINANCE_API_URL', defaultValue: '');
    if (defined.trim().isNotEmpty) return _normalizeBaseUrl(defined);

    return 'http://10.0.2.2:8089';
  }

  Future<String> _getNormalizedBaseUrl() async =>
      _normalizeBaseUrl(await _getBaseUrl());

  Future<Uri> get _syncUri async =>
      Uri.parse('${await _getNormalizedBaseUrl()}/sync');
  Future<Uri> get _ackUri async =>
      Uri.parse('${await _getNormalizedBaseUrl()}/sync/ack');
  Future<Uri> get _loginUri async =>
      Uri.parse('${await _getNormalizedBaseUrl()}/auth/login');

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefKeyToken);
    if (cached != null && cached.isNotEmpty) return cached;
    throw const FinanceSyncException(
      'Chưa đăng nhập đồng bộ. Hãy nhập FINANCE_API_URL, tài khoản và mật khẩu rồi thử lại.',
    );
  }

  String _normalizeBaseUrl(String baseUrl) {
    var s = baseUrl.trim();
    if (s.isEmpty) return s;
    // Remove trailing slashes to avoid //auth/login causing 404 on nginx
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<void> saveBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) {
      await prefs.remove(_prefKeyBaseUrl);
      return;
    }
    await prefs.setString(_prefKeyBaseUrl, normalized);
  }

  Future<void> clearAuth({bool clearCredentials = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyToken);
    if (clearCredentials) {
      await prefs.remove(_prefKeyUsername);
      await prefs.remove(_prefKeyPassword);
    }
  }

  Future<bool> hasSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_prefKeyToken);
    return token != null && token.trim().isNotEmpty;
  }

  Future<bool> hasSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_prefKeyUsername)?.trim() ?? '';
    final password = prefs.getString(_prefKeyPassword)?.trim() ?? '';
    return username.isNotEmpty && password.isNotEmpty;
  }

  Future<FinanceSyncAuthState> getSavedAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    return FinanceSyncAuthState(
      baseUrl: prefs.getString(_prefKeyBaseUrl)?.trim() ?? '',
      username: prefs.getString(_prefKeyUsername)?.trim() ?? '',
      hasToken: (prefs.getString(_prefKeyToken)?.trim() ?? '').isNotEmpty,
      hasPassword: (prefs.getString(_prefKeyPassword)?.trim() ?? '').isNotEmpty,
    );
  }

  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    required String password,
    bool persistCredentials = true,
  }) async {
    final normalizedBaseUrl = baseUrl.trim();
    final normalizedUsername = username.trim();
    final normalizedPassword = password.trim();

    if (normalizedBaseUrl.isEmpty) {
      throw const FinanceSyncException('FINANCE_API_URL không được để trống.');
    }
    if (normalizedUsername.isEmpty) {
      throw const FinanceSyncException('Username không được để trống.');
    }
    if (normalizedPassword.isEmpty) {
      throw const FinanceSyncException('Password không được để trống.');
    }

    await saveBaseUrl(normalizedBaseUrl);

    final resp = await _httpClient
        .post(
          await _loginUri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': normalizedUsername,
            'password': normalizedPassword,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw FinanceSyncException(
        _buildApiError(
          fallback:
              'Đăng nhập thất bại (${resp.statusCode}). Kiểm tra lại URL hoặc tài khoản.',
          responseBody: resp.body,
        ),
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FinanceSyncException(
        'Response /auth/login không đúng format.',
      );
    }

    final result = LoginResult.fromJson(decoded);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyToken, result.token);
    await prefs.setString(_prefKeyBaseUrl, normalizedBaseUrl);
    if (persistCredentials) {
      await prefs.setString(_prefKeyUsername, normalizedUsername);
      await prefs.setString(_prefKeyPassword, normalizedPassword);
    }
    return result;
  }

  Future<LoginResult> reloginFromSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_prefKeyBaseUrl)?.trim() ?? '';
    final username = prefs.getString(_prefKeyUsername)?.trim() ?? '';
    final password = prefs.getString(_prefKeyPassword)?.trim() ?? '';

    if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) {
      await clearAuth();
      throw const FinanceSyncException(
        'Token sync đã hết hạn và app chưa có đủ thông tin để tự đăng nhập lại. Vui lòng nhập lại URL, username và password.',
      );
    }

    return login(
      baseUrl: baseUrl,
      username: username,
      password: password,
      persistCredentials: true,
    );
  }

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
      final resp = await _httpClient.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 401) {
        throw const FinanceSyncUnauthorizedException();
      }

      if (resp.statusCode != 200) {
        throw FinanceSyncException(
          _buildApiError(
            fallback: 'Lấy dữ liệu sync thất bại (${resp.statusCode}).',
            responseBody: resp.body,
          ),
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

    try {
      final token = await _getToken();
      return await runWithToken(token);
    } on FinanceSyncUnauthorizedException {
      await clearAuth();
      try {
        final loginResult = await reloginFromSavedCredentials();
        return await runWithToken(loginResult.token);
      } on FinanceSyncException catch (e) {
        throw FinanceSyncException(
          'Phiên đăng nhập sync đã hết hạn và app tự đăng nhập lại không thành công. ${e.message}',
        );
      }
    }
  }

  Future<void> ack(List<int> ids) async {
    if (ids.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    Future<void> runWithToken(String token) async {
      final ackUri = await _ackUri;
      final resp = await _httpClient
          .post(
            ackUri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'ids': ids}),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 401) {
        throw const FinanceSyncUnauthorizedException();
      }

      if (resp.statusCode != 200) {
        throw FinanceSyncException(
          _buildApiError(
            fallback: 'Ack sync thất bại (${resp.statusCode}).',
            responseBody: resp.body,
          ),
        );
      }

      await prefs.setString(
        _prefKeyLastSync,
        DateTime.now().toUtc().toIso8601String(),
      );
    }

    try {
      final token = await _getToken();
      await runWithToken(token);
    } on FinanceSyncUnauthorizedException {
      await clearAuth();
      try {
        final loginResult = await reloginFromSavedCredentials();
        await runWithToken(loginResult.token);
      } on FinanceSyncException catch (e) {
        throw FinanceSyncException(
          'Phiên đăng nhập sync đã hết hạn và app tự đăng nhập lại không thành công. ${e.message}',
        );
      }
    }
  }

  String _buildApiError({
    required String fallback,
    required String responseBody,
  }) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return '$fallback ${detail.trim()}';
        }
      }
    } catch (_) {}
    return '$fallback $responseBody';
  }
}

class FinanceSyncException implements Exception {
  const FinanceSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FinanceSyncUnauthorizedException extends FinanceSyncException {
  const FinanceSyncUnauthorizedException()
      : super('Phiên đăng nhập sync đã hết hạn hoặc không hợp lệ (401).');
}

class FinanceSyncAuthState {
  const FinanceSyncAuthState({
    required this.baseUrl,
    required this.username,
    required this.hasToken,
    required this.hasPassword,
  });

  final String baseUrl;
  final String username;
  final bool hasToken;
  final bool hasPassword;
}

class LoginResult {
  const LoginResult({
    required this.token,
    required this.tokenType,
    required this.expiresInDays,
  });

  final String token;
  final String tokenType;
  final int? expiresInDays;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    final dynamic tokenValue = json['access_token'];
    if (tokenValue is! String || tokenValue.trim().isEmpty) {
      throw const FinanceSyncException(
        'Response /auth/login thiếu access_token hợp lệ.',
      );
    }

    final dynamic tokenTypeValue = json['token_type'];
    final dynamic expiresValue = json['expires_in_days'];

    return LoginResult(
      token: tokenValue.trim(),
      tokenType: tokenTypeValue is String && tokenTypeValue.trim().isNotEmpty
          ? tokenTypeValue.trim()
          : 'bearer',
      expiresInDays: expiresValue is int
          ? expiresValue
          : int.tryParse(expiresValue?.toString() ?? ''),
    );
  }
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
