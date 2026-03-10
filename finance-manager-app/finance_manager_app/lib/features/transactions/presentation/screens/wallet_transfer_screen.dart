import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/utils/vnd_format.dart';

class WalletTransferScreen extends StatefulWidget {
  const WalletTransferScreen({super.key});

  @override
  State<WalletTransferScreen> createState() => _WalletTransferScreenState();
}

class _WalletTransferScreenState extends State<WalletTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _uuid = const Uuid();

  DateTime _occurredAt = DateTime.now();
  String? _fromWalletId;
  String? _toWalletId;
  String? _transferCategoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bootstrapDefaults();
  }

  Future<void> _bootstrapDefaults() async {
    final db = AppDatabase.instance;
    final wallets = await db.getWallets();
    final transferCategory = await db.ensureTransferCategory();
    if (!mounted) return;

    setState(() {
      _transferCategoryId = transferCategory.id;
      if (wallets.isNotEmpty) {
        _fromWalletId = wallets.first.id;
      }
      if (wallets.length > 1) {
        _toWalletId = wallets[1].id;
      }
    });
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
      locale: const Locale('vi', 'VN'),
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

    final amount = parseVnd(_amountCtrl.text);
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số tiền phải lớn hơn 0')),
      );
      return;
    }

    if (_fromWalletId == null ||
        _toWalletId == null ||
        _transferCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Chọn đủ ví nguồn, ví đích và danh mục chuyển tiền')),
      );
      return;
    }

    if (_fromWalletId == _toWalletId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ví nguồn và ví đích phải khác nhau')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = AppDatabase.instance;
      final pairId = _uuid.v4();
      final noteText = _noteCtrl.text.trim();
      final baseNote = noteText.isEmpty ? 'Chuyển tiền giữa ví' : noteText;

      await db.createWalletTransfer(
        pairId: pairId,
        fromWalletId: _fromWalletId!,
        toWalletId: _toWalletId!,
        amount: amount,
        occurredAt: _occurredAt,
        categoryId: _transferCategoryId!,
        note: baseNote,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không lưu được chuyển ví: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('dd/MM/yyyy', 'vi_VN').format(_occurredAt);
    final db = AppDatabase.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chuyển tiền giữa ví'),
      ),
      body: StreamBuilder<List<Wallet>>(
        stream: db.select(db.wallets).watch(),
        builder: (context, walletSnap) {
          final wallets = walletSnap.data ?? const <Wallet>[];

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Luồng xử lý',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          const Text(
                            'App sẽ tạo 2 bản ghi liên kết: 1 giao dịch chuyển ra ở ví nguồn và 1 giao dịch chuyển vào ở ví đích.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _fromWalletId,
                    decoration: const InputDecoration(
                      labelText: 'Ví nguồn',
                      border: OutlineInputBorder(),
                    ),
                    items: wallets
                        .map(
                          (wallet) => DropdownMenuItem(
                            value: wallet.id,
                            child: Text(wallet.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _fromWalletId = value),
                    validator: (value) =>
                        value == null ? 'Chọn ví nguồn' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _toWalletId,
                    decoration: const InputDecoration(
                      labelText: 'Ví đích',
                      border: OutlineInputBorder(),
                    ),
                    items: wallets
                        .map(
                          (wallet) => DropdownMenuItem(
                            value: wallet.id,
                            child: Text(wallet.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _toWalletId = value),
                    validator: (value) => value == null ? 'Chọn ví đích' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [VndTextInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Số tiền (VND)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Nhập số tiền';
                      }
                      final amount = parseVnd(value);
                      if (amount <= 0) return 'Số tiền không hợp lệ';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú',
                      hintText: 'VD: Chuyển từ MoMo về tiền mặt',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Ngày thực hiện: $dateLabel'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.swap_horiz),
                    label: Text(_saving ? 'Đang lưu...' : 'Lưu chuyển ví'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
