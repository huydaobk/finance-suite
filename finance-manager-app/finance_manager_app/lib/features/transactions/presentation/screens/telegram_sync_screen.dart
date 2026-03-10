import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _obscurePassword = true;
  bool _hasToken = false;
  String? _error;

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
    final prefs = await SharedPreferences.getInstance();
    _urlCtrl.text = prefs.getString('finance_api_url') ?? '';
    _hasToken = await _svc.hasSavedToken();
    if (mounted) setState(() {});
  }

  Future<void> _handleUnauthorized() async {
    await _svc.clearAuth();
    _pending = [];
    _selected.clear();
    _hasToken = false;
    if (mounted) setState(() {});
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loggingIn = true;
      _error = null;
    });

    try {
      await _svc.login(
        baseUrl: _urlCtrl.text,
        username: _usernameCtrl.text,
        password: _passwordCtrl.text,
      );
      _passwordCtrl.clear();
      _hasToken = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đăng nhập thành công ✅')),
        );
      }
      await _fetch();
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
        setState(() => _loggingIn = false);
      }
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _svc.fetchPending();
      setState(() {
        _hasToken = true;
        _pending = items;
        _selected = items.map((e) => e.id).toSet();
      });
    } on FinanceSyncException catch (e) {
      if (e.message.contains('(401)')) {
        await _handleUnauthorized();
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
      if (e.message.contains('(401)')) {
        await _handleUnauthorized();
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
                'Nhập địa chỉ finance-api và tài khoản của anh. App sẽ tự lấy token, không cần dán JWT thủ công nữa.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
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
                onSubmitted: (_) => _loggingIn ? null : _login(),
                decoration: InputDecoration(
                  labelText: 'Password',
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
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loggingIn ? null : _login,
                icon: _loggingIn
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(_loggingIn ? 'Đang đăng nhập...' : 'Đăng nhập'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
          SizedBox(height: 12),
          Text('Không có giao dịch mới từ Telegram'),
        ],
      ),
    );
  }

  Widget _buildPendingList() {
    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
                onPressed: () =>
                    setState(() => _selected = _pending.map((e) => e.id).toSet()),
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
              onPressed: (_loading || _loggingIn)
                  ? null
                  : () async {
                      await _handleUnauthorized();
                      setState(() {
                        _error = 'Đã đăng xuất sync. Vui lòng đăng nhập lại.';
                      });
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
