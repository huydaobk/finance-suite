import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/db/app_database.dart';
import 'wallet_transfer_screen.dart';

/// Dùng cho cả thêm mới lẫn chỉnh sửa giao dịch.
/// Truyền [existing] để vào chế độ edit.
class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key, this.existing});

  final TransactionItem? existing;

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _type = 'expense';
  DateTime _occurredAt = DateTime.now();
  String? _walletId;
  String? _categoryId;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final tx = widget.existing!.tx;
      _type = tx.type;
      _occurredAt = tx.occurredAt;
      _walletId = tx.walletId;
      _categoryId = tx.categoryId;
      _amountCtrl.text = tx.amount.toString();
      _noteCtrl.text = tx.note ?? '';
    } else {
      _bootstrapDefaults();
    }
  }

  Future<void> _bootstrapDefaults() async {
    final db = AppDatabase.instance;
    final wallets = await db.select(db.wallets).get();
    if (wallets.isNotEmpty && mounted) {
      final preferred = wallets.cast<Wallet?>().firstWhere(
            (w) => w?.id == 'wallet_cash',
            orElse: () => wallets.first,
          );
      setState(() => _walletId = preferred?.id);
    }
    final cats = await (db.select(db.categories)
          ..where((c) => c.type.equals(_type)))
        .get();
    if (cats.isNotEmpty && mounted) {
      setState(() => _categoryId = cats.first.id);
    }
  }

  Future<void> _ensureDefaultCategoryForType() async {
    if (_categoryId != null) return;
    final db = AppDatabase.instance;
    final cats = await (db.select(db.categories)
          ..where((c) => c.type.equals(_type)))
        .get();
    if (cats.isNotEmpty && mounted) {
      setState(() => _categoryId = cats.first.id);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _occurredAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _occurredAt.hour,
          _occurredAt.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số tiền phải > 0')),
      );
      return;
    }

    if (_walletId == null || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn ví và danh mục')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = AppDatabase.instance;
      final noteVal = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

      if (_isEdit) {
        // ── Update ──────────────────────────────────────────────────────────
        await db.updateTransaction(
          id: widget.existing!.tx.id,
          type: _type,
          amount: amount,
          walletId: _walletId!,
          categoryId: _categoryId!,
          occurredAt: _occurredAt,
          note: noteVal,
        );
      } else {
        // ── Insert ──────────────────────────────────────────────────────────
        final id = 'tx_${DateTime.now().millisecondsSinceEpoch}';
        await db.transaction(() async {
          await db.into(db.transactions).insert(
                TransactionsCompanion.insert(
                  id: id,
                  walletId: _walletId!,
                  categoryId: _categoryId!,
                  type: _type,
                  amount: amount,
                  occurredAt: _occurredAt,
                  note: noteVal == null
                      ? const Value.absent()
                      : Value(noteVal),
                ),
              );

          if (_type == 'expense' && amount >= 2500000) {
            final alertId = 'alert_${DateTime.now().millisecondsSinceEpoch}';
            await db.into(db.alertEvents).insert(
                  AlertEventsCompanion.insert(
                    id: alertId,
                    type: 'large_expense',
                    titleVi: 'Cảnh báo chi tiêu lớn',
                    bodyVi:
                        'Bạn vừa ghi nhận khoản chi ${NumberFormat.decimalPattern('vi_VN').format(amount)}₫.',
                    metaJson: Value(
                      '{"txId":"$id","amount":$amount,"walletId":"$_walletId","categoryId":"$_categoryId"}',
                    ),
                  ),
                );
          }
        });
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi lưu: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabase.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Sửa giao dịch' : 'Thêm giao dịch'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Chi')),
                  ButtonSegment(value: 'income', label: Text('Thu')),
                  ButtonSegment(value: 'transfer', label: Text('Chuyển')),
                ],
                selected: {_type},
                onSelectionChanged: _isEdit
                    ? null
                    : (v) async {
                        final next = v.first;
                        if (next == _type) return;
                        setState(() {
                          _type = next;
                          _categoryId = null;
                        });
                        await _ensureDefaultCategoryForType();
                      },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Số tiền (VND)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nhập số tiền' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (tuỳ chọn)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  'Ngày: ${_occurredAt.year}-${_occurredAt.month.toString().padLeft(2, '0')}-${_occurredAt.day.toString().padLeft(2, '0')}',
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder(
                stream: db.select(db.wallets).watch(),
                builder: (context, snapshot) {
                  final wallets = snapshot.data ?? const [];
                  return DropdownButtonFormField<String>(
                    initialValue: _walletId,
                    decoration: const InputDecoration(
                      labelText: 'Ví',
                      border: OutlineInputBorder(),
                    ),
                    items: wallets
                        .map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(w.name),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _walletId = v),
                  );
                },
              ),
              const SizedBox(height: 12),
              if (_type == 'transfer')
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Giao dịch chuyển ví cần tạo qua màn riêng để ghi đồng thời ví nguồn và ví đích.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _isEdit
                              ? null
                              : () async {
                                  if (!context.mounted) return;
                                  final navigator = Navigator.of(context);
                                  final created = await navigator.push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => const WalletTransferScreen(),
                                    ),
                                  );
                                  if (created == true && context.mounted) {
                                    navigator.pop(true);
                                  }
                                },
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Mở màn chuyển ví'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                StreamBuilder(
                  stream: (db.select(db.categories)
                        ..where((c) => c.type.equals(_type)))
                      .watch(),
                  builder: (context, snapshot) {
                    final cats = snapshot.data ?? const [];
                    return DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      decoration: const InputDecoration(
                        labelText: 'Danh mục',
                        border: OutlineInputBorder(),
                      ),
                      items: cats
                          .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _categoryId = v),
                    );
                  },
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? 'Đang lưu...'
                    : (_isEdit ? 'Cập nhật' : 'Lưu')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
