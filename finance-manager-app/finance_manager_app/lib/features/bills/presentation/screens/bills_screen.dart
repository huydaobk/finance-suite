import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/db/app_database.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  final _db = AppDatabase.instance;
  final _moneyFmt = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  Future<void> _confirmDelete(BillWithDetails item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa hóa đơn?'),
        content: Text('Xóa "${item.bill.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok == true) await _db.deleteBill(item.bill.id);
  }

  Future<void> _openAddSheet() async {
    final categories = await _db.select(_db.categories).get();
    final wallets = await _db.select(_db.wallets).get();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddBillSheet(
        categories: categories,
        wallets: wallets,
        onSave: (companion) async {
          await _db.insertBill(companion);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hóa đơn định kỳ'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<BillWithDetails>>(
        stream: _db.watchBills(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(
              child: Text('Chưa có hóa đơn nào.\nNhấn + để thêm.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              final bill = item.bill;
              return Dismissible(
                key: ValueKey(bill.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) async {
                  await _confirmDelete(item);
                  return false; // we handle delete ourselves
                },
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: bill.active
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.grey.shade200,
                    child: Text(
                      '${bill.dueDay}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: bill.active
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Colors.grey,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(bill.name)),
                      if (!bill.active)
                        const Chip(
                          label: Text('Tắt', style: TextStyle(fontSize: 11)),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.category.name} · ${item.wallet.name}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (bill.amountExpected != null)
                        Text(
                          _moneyFmt.format(bill.amountExpected),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onLongPress: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await _db.toggleBillActive(bill.id, !bill.active);
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(
                      content: Text(bill.active
                          ? '"${bill.name}" đã tắt'
                          : '"${bill.name}" đã bật'),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AddBillSheet extends StatefulWidget {
  const _AddBillSheet({
    required this.categories,
    required this.wallets,
    required this.onSave,
  });

  final List<Category> categories;
  final List<Wallet> wallets;
  final Future<void> Function(BillsCompanion) onSave;

  @override
  State<_AddBillSheet> createState() => _AddBillSheetState();
}

class _AddBillSheetState extends State<_AddBillSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String? _categoryId;
  String? _walletId;
  int _dueDay = 1;
  int _remindBefore = 3;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.categories.isNotEmpty) _categoryId = widget.categories.first.id;
    if (widget.wallets.isNotEmpty) _walletId = widget.wallets.first.id;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null || _walletId == null) return;
    setState(() => _saving = true);

    final amountRaw = _amountCtrl.text.trim();
    final amount = amountRaw.isEmpty ? null : int.tryParse(amountRaw);

    await widget.onSave(BillsCompanion.insert(
      id: const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      categoryId: _categoryId!,
      walletId: _walletId!,
      dueDay: _dueDay,
      remindBeforeDays: Value(_remindBefore),
      amountExpected: Value(amount),
      active: Value(_active),
    ));

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Thêm hóa đơn',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên hóa đơn *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nhập tên hóa đơn' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Danh mục *',
                border: OutlineInputBorder(),
              ),
              items: widget.categories
                  .map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _walletId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Ví *',
                border: OutlineInputBorder(),
              ),
              items: widget.wallets
                  .map((w) =>
                      DropdownMenuItem(value: w.id, child: Text(w.name)))
                  .toList(),
              onChanged: (v) => setState(() => _walletId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _dueDay,
                    decoration: const InputDecoration(
                      labelText: 'Ngày HĐ',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(28, (i) => i + 1)
                        .map((d) =>
                            DropdownMenuItem(value: d, child: Text('Ngày $d')))
                        .toList(),
                    onChanged: (v) => setState(() => _dueDay = v ?? 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _remindBefore,
                    decoration: const InputDecoration(
                      labelText: 'Nhắc trước',
                      border: OutlineInputBorder(),
                    ),
                    items: [1, 2, 3, 5, 7]
                        .map((d) =>
                            DropdownMenuItem(value: d, child: Text('$d ngày')))
                        .toList(),
                    onChanged: (v) => setState(() => _remindBefore = v ?? 3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền dự kiến (không bắt buộc)',
                border: OutlineInputBorder(),
                hintText: 'VD: 200000',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Đang hoạt động'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}
