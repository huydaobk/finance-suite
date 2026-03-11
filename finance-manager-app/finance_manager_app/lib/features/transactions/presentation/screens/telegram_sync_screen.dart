import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/sync/finance_sync_service.dart';
import '../../../../core/utils/vnd_format.dart';

class TelegramSyncScreen extends StatefulWidget {
  const TelegramSyncScreen({super.key});

  @override
  State<TelegramSyncScreen> createState() => _TelegramSyncScreenState();
}

class _TelegramSyncScreenState extends State<TelegramSyncScreen> {
  final _svc = FinanceSyncService();

  final _urlCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  List<InboxTx> _pending = [];
  Set<int> _selected = {};
  bool _loading = false;
  bool _importing = false;
  bool _loggingIn = false;
  bool _testingLogin = false;
  bool _obscurePassword = true;
  bool _hasToken = false;
  String? _error;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadPrefs();
    if (_hasToken) {
      await _fetch();
    }
  }

  Future<void> _loadPrefs() async {
    final authState = await _svc.getSavedAuthState();
    _urlCtrl.text = authState.baseUrl;
    _usernameCtrl.text = authState.username;
    _hasToken = authState.hasToken;
    if (mounted) setState(() {});
  }

  Future<void> _handleLogout(
      {String? message, bool clearCredentials = false}) async {
    await _svc.clearAuth(clearCredentials: clearCredentials);
    _pending = [];
    _selected.clear();
    _hasToken = false;
    if (message != null) {
      _error = message;
      _statusMessage = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _login({bool testOnly = false}) async {
    FocusScope.of(context).unfocus();
    setState(() {
      if (testOnly) {
        _testingLogin = true;
      } else {
        _loggingIn = true;
      }
      _error = null;
      _statusMessage = null;
    });

    try {
      final result = await _svc.login(
        baseUrl: _urlCtrl.text,
        username: _usernameCtrl.text,
        password: _passwordCtrl.text,
        persistCredentials: true,
      );
      _hasToken = true;
      _statusMessage = testOnly
          ? 'Test login thành công. Token ${result.tokenType} có hạn ${result.expiresInDays ?? '?'} ngày.'
          : 'Đăng nhập thành công ✅';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_statusMessage!)),
        );
      }
      if (!testOnly) {
        await _fetch();
      }
    } on FinanceSyncException catch (e) {
      setState(() {
        _hasToken = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _hasToken = false;
        _error = 'Không thể đăng nhập: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loggingIn = false;
          _testingLogin = false;
        });
      }
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final items = await _svc.fetchPending();
      setState(() {
        _hasToken = true;
        _pending = items;
        _selected = items.map((e) => e.id).toSet();
        if (items.isEmpty) {
          _statusMessage =
              'Đồng bộ OK. Hiện chưa có giao dịch mới từ Telegram.';
        }
      });
    } on FinanceSyncException catch (e) {
      if (e.message.contains('tự đăng nhập lại không thành công') ||
          e.message.contains('Vui lòng nhập lại URL, username và password')) {
        await _handleLogout(message: e.message);
      }
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Không kết nối được server: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _importSelected() async {
    if (_selected.isEmpty) return;
    setState(() {
      _importing = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      final db = AppDatabase.instance;
      final toImport = _pending.where((t) => _selected.contains(t.id)).toList();

      final categories = await db.select(db.categories).get();
      final wallets = await db.select(db.wallets).get();

      Category matchCat(String? name, String type) {
        final normalizedName = name?.trim().toLowerCase();
        if (normalizedName != null && normalizedName.isNotEmpty) {
          for (final category in categories) {
            if (category.type == type &&
                category.name.trim().toLowerCase() == normalizedName) {
              return category;
            }
          }

          for (final category in categories) {
            if (category.type == type &&
                category.name.toLowerCase().contains(normalizedName)) {
              return category;
            }
          }
        }

        final sameType = categories.where((c) => c.type == type).toList();
        if (sameType.isNotEmpty) return sameType.first;
        throw StateError('Không tìm thấy category type=$type trong DB local.');
      }

      Wallet matchWallet(String? name) {
        final normalizedName = name?.trim().toLowerCase();
        if (normalizedName != null && normalizedName.isNotEmpty) {
          for (final wallet in wallets) {
            if (wallet.name.trim().toLowerCase() == normalizedName) {
              return wallet;
            }
          }

          for (final wallet in wallets) {
            if (wallet.name.toLowerCase().contains(normalizedName)) {
              return wallet;
            }
          }
        }

        for (final wallet in wallets) {
          if (wallet.id == 'wallet_cash') return wallet;
        }
        if (wallets.isNotEmpty) return wallets.first;
        throw StateError('Không tìm thấy ví nào trong DB local.');
      }

      if (categories.isEmpty) {
        throw StateError('DB local chưa có categories seed.');
      }
      if (wallets.isEmpty) {
        throw StateError('DB local chưa có wallets seed.');
      }

      final importedIds = <int>[];
      for (final tx in toImport) {
        final cat = matchCat(tx.category, tx.type);
        final wallet = matchWallet(tx.wallet);
        final txDate = DateTime.tryParse(tx.txDate) ?? DateTime.now();
        final id = 'tx_tg_${const Uuid().v4()}';

        await db.into(db.transactions).insert(
              TransactionsCompanion.insert(
                id: id,
                walletId: wallet.id,
                categoryId: cat.id,
                type: tx.type,
                amount: tx.amountVnd,
                occurredAt: txDate,
                note: tx.note != null ? Value(tx.note!) : const Value.absent(),
              ),
            );
        importedIds.add(tx.id);
      }

      await _svc.ack(importedIds);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Đã import ${importedIds.length} giao dịch ✅'),
        ));
        Navigator.of(context).pop(true);
      }
    } on FinanceSyncException catch (e) {
      if (e.message.contains('tự đăng nhập lại không thành công') ||
          e.message.contains('Vui lòng nhập lại URL, username và password')) {
        await _handleLogout(message: e.message);
      }
      setState(() => _error = e.message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      final message = 'Lỗi import: $e';
      setState(() => _error = message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _buildInfoBanner() {
    final message = _error ?? _statusMessage;
    if (message == null) return const SizedBox.shrink();

    final isError = _error != null;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: isError ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.info_outline,
                color: isError
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: isError
                        ? scheme.onErrorContainer
                        : scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline, size: 56, color: Colors.blueGrey),
              const SizedBox(height: 16),
              Text(
                'Đăng nhập để đồng bộ Telegram',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Phương án C: app tự lưu URL + token, đồng thời lưu credential để auto re-login khi token bị 401.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              _buildInfoBanner(),
              const SizedBox(height: 24),
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'FINANCE_API_URL',
                  hintText: 'vd: http://14.225.222.53:8089',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                onSubmitted: (_) =>
                    (_loggingIn || _testingLogin) ? null : _login(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText:
                      'Password được lưu local để app tự đăng nhập lại khi token hết hạn.',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_loggingIn || _testingLogin)
                          ? null
                          : () => _login(testOnly: true),
                      icon: _testingLogin
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.health_and_safety_outlined),
                      label: Text(
                        _testingLogin ? 'Đang test...' : 'Test Login',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_loggingIn || _testingLogin) ? null : _login,
                      icon: _loggingIn
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label:
                          Text(_loggingIn ? 'Đang đăng nhập...' : 'Đăng nhập'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
          const SizedBox(height: 12),
          const Text('Không có giao dịch mới từ Telegram'),
          if (_statusMessage != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingList() {
    return Column(
      children: [
        _buildInfoBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${_pending.length} giao dịch từ Telegram',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(
                    () => _selected = _pending.map((e) => e.id).toSet()),
                child: const Text('Chọn tất cả'),
              ),
              TextButton(
                onPressed: () => setState(() => _selected.clear()),
                child: const Text('Bỏ chọn'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _pending.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final tx = _pending[i];
              final isSelected = _selected.contains(tx.id);
              final isExpense = tx.type == 'expense';
              final sign = isExpense ? '-' : '+';
              return CheckboxListTile(
                value: isSelected,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(tx.id);
                  } else {
                    _selected.remove(tx.id);
                  }
                }),
                secondary: CircleAvatar(
                  backgroundColor:
                      isExpense ? Colors.red.shade50 : Colors.green.shade50,
                  child: Icon(
                    isExpense ? Icons.arrow_downward : Icons.arrow_upward,
                    color: isExpense ? Colors.red : Colors.green,
                    size: 18,
                  ),
                ),
                title: Text(
                  '$sign${formatVnd(tx.amountVnd)}₫',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isExpense ? Colors.red : Colors.green,
                  ),
                ),
                subtitle: Text(
                  [
                    if (tx.note != null) tx.note!,
                    if (tx.category != null) tx.category!,
                    tx.txDate,
                  ].join(' · '),
                ),
                isThreeLine: false,
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showLogin = !_hasToken;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đồng bộ từ Telegram'),
        centerTitle: true,
        actions: [
          if (!showLogin)
            IconButton(
              onPressed: _loading ? null : _fetch,
              icon: const Icon(Icons.refresh),
              tooltip: 'Tải lại',
            ),
          if (!showLogin)
            IconButton(
              onPressed: (_loading || _loggingIn || _testingLogin)
                  ? null
                  : () async {
                      await _handleLogout(
                        message: 'Đã đăng xuất sync. Vui lòng đăng nhập lại.',
                        clearCredentials: true,
                      );
                    },
              icon: const Icon(Icons.logout),
              tooltip: 'Đăng xuất sync',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : showLogin
              ? _buildLoginForm()
              : _pending.isEmpty
                  ? _buildEmptyState()
                  : _buildPendingList(),
      bottomNavigationBar: (!showLogin && _pending.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: (_importing || _selected.isEmpty)
                      ? null
                      : _importSelected,
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(_importing
                      ? 'Đang import...'
                      : 'Import ${_selected.length} giao dịch'),
                ),
              ),
            )
          : null,
    );
  }
}
