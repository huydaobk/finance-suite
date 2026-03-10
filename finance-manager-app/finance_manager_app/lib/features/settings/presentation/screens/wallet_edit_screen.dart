import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/utils/vnd_format.dart';

class WalletEditScreen extends StatefulWidget {
  const WalletEditScreen({
    super.key,
    required this.walletId,
  });

  final String walletId;

  @override
  State<WalletEditScreen> createState() => _WalletEditScreenState();
}

class _WalletEditScreenState extends State<WalletEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _openingBalanceController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  Wallet? _wallet;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final wallet = await AppDatabase.instance.getWalletById(widget.walletId);
    if (!mounted) return;
    setState(() {
      _wallet = wallet;
      _nameController.text = wallet.name;
      _openingBalanceController.text = formatVnd(wallet.openingBalance);
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_wallet == null || !_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final updatedName = _nameController.text.trim();
    final openingBalance = parseVnd(_openingBalanceController.text);

    await AppDatabase.instance.updateWallet(
      WalletsCompanion(
        id: Value(_wallet!.id),
        name: Value(updatedName),
        currency: Value(_wallet!.currency),
        openingBalance: Value(openingBalance),
        createdAt: Value(_wallet!.createdAt),
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chỉnh sửa ví'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Tên ví',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui lòng nhập tên ví';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _openingBalanceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Số dư đầu kỳ (VND)',
                        hintText: 'Ví dụ: 1.500.000',
                        border: OutlineInputBorder(),
                      ),
                      inputFormatters: const [VndTextInputFormatter()],
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        if (parseVnd(value) < 0) {
                          return 'Số dư đầu kỳ không hợp lệ';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Số dư hiện tại sẽ tự tính từ số dư đầu kỳ + thu/chi + chuyển ví theo dữ liệu hiện có.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Đang lưu...' : 'Lưu'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
