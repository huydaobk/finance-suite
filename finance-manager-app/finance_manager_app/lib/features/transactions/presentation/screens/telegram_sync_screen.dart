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

  final _tokenCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  List<InboxTx> _pending = [];
  Set<int> _selected = {};
  bool _loading = false;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _fetch();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _tokenCtrl.text = prefs.getString('finance_api_token') ?? '';
    _urlCtrl.text = prefs.getString('finance_api_url') ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _tokenCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (token.isNotEmpty) await prefs.setString('finance_api_token', token);
    if (url.isNotEmpty) await prefs.setString('finance_api_url', url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu cấu hình đồng bộ ✅')),
      );
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
        _pending = items;
        _selected = items.map((e) => e.id).toSet(); // chọn tất cả mặc định
      });
    } on FinanceSyncException catch (e) {
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
    setState(() => _importing = true);

    try {
      final db = AppDatabase.instance;
      final toImport = _pending.where((t) => _selected.contains(t.id)).toList();

      // Resolve category/wallet IDs from DB
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

      // Ack server
      await _svc.ack(importedIds);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Đã import ${importedIds.length} giao dịch ✅'),
        ));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi import: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đồng bộ từ Telegram'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loading ? null : _fetch,
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            TextField(
                              controller: _urlCtrl,
                              decoration: const InputDecoration(
                                labelText: 'FINANCE_API_URL',
                                hintText:
                                    'vd: http://14.225.222.53:8089 hoặc https://your-domain',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _tokenCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Token đồng bộ (JWT)',
                                hintText: 'Dán token vào đây',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          await _savePrefs();
                          await _fetch();
                        },
                        child: const Text('Lưu & Thử lại'),
                      ),
                    ],
                  ),
                )
              : _pending.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 48, color: Colors.green),
                          SizedBox(height: 12),
                          Text('Không có giao dịch mới từ Telegram'),
                        ],
                      ),
                    )
                  : Column(
                      children: [
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
                                onPressed: () => setState(() => _selected =
                                    _pending.map((e) => e.id).toSet()),
                                child: const Text('Chọn tất cả'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _selected.clear()),
                                child: const Text('Bỏ chọn'),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _pending.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
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
                                  backgroundColor: isExpense
                                      ? Colors.red.shade50
                                      : Colors.green.shade50,
                                  child: Icon(
                                    isExpense
                                        ? Icons.arrow_downward
                                        : Icons.arrow_upward,
                                    color:
                                        isExpense ? Colors.red : Colors.green,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  '$sign${formatVnd(tx.amountVnd)}₫',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color:
                                        isExpense ? Colors.red : Colors.green,
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
                    ),
      bottomNavigationBar: _pending.isNotEmpty
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
