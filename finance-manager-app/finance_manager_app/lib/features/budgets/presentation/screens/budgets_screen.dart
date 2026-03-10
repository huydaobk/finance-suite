import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/db/app_database.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  String get _monthLabel =>
      '${_month.month.toString().padLeft(2, '0')}/${_month.year}';

  void _prevMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1));
  void _nextMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month + 1));

  Future<void> _showUpsertDialog({
    Budget? editing,
    required List<Category> expenseCategories,
  }) async {
    final amountController = TextEditingController(
      text: editing != null ? editing.limitAmount.toString() : '',
    );
    String? selectedCategoryId = editing?.categoryId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(
                editing == null ? 'Thiết lập ngân sách' : 'Sửa ngân sách',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: selectedCategoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Danh mục',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tổng chi tháng'),
                      ),
                      ...expenseCategories.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name),
                        ),
                      ),
                    ],
                    onChanged: (v) =>
                        setLocalState(() => selectedCategoryId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Mức chi tối đa (VND)',
                      hintText: 'Ví dụ: 5000000',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () async {
                    final raw = amountController.text.trim();
                    final limit = int.tryParse(raw);
                    if (limit == null || limit <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mức chi phải là số lớn hơn 0'),
                        ),
                      );
                      return;
                    }

                    await AppDatabase.instance.upsertBudget(
                      month: _monthKey,
                      categoryId: selectedCategoryId,
                      limitAmount: limit,
                    );

                    if (!context.mounted) return;
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu ngân sách ✅')),
      );
    }
  }

  Future<void> _deleteBudget(Budget budget) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa ngân sách?'),
        content: const Text('Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await AppDatabase.instance.deleteBudget(budget.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa ngân sách.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thiết lập ngân sách'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Category>>(
        stream: (AppDatabase.instance.select(AppDatabase.instance.categories)
              ..where((c) => c.type.equals('expense'))
              ..orderBy([(c) => OrderingTerm.asc(c.name)]))
            .watch(),
        builder: (context, catSnap) {
          final expenseCategories = catSnap.data ?? const <Category>[];

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _prevMonth,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _monthLabel,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _nextMonth,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: () =>
                          _showUpsertDialog(expenseCategories: expenseCategories),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<BudgetWithCategory>>(
                  stream: AppDatabase.instance.watchBudgetsForMonth(_monthKey),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Lỗi: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final items = snapshot.data!;
                    if (items.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.savings_outlined,
                                size: 56,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Chưa có ngân sách cho tháng này',
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Nhấn nút Thêm để đặt mức chi tối đa cho toàn tháng hoặc từng danh mục.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final money = NumberFormat.decimalPattern('vi_VN');

                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final b = items[index];
                        final title = b.category?.name ?? 'Tổng chi tháng';
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Icon(
                                b.category == null
                                    ? Icons.pie_chart_outline
                                    : Icons.sell_outlined,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                              ),
                            ),
                            title: Text(title),
                            subtitle: Text(
                              'Giới hạn: ${money.format(b.budget.limitAmount)}₫',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Sửa',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showUpsertDialog(
                                    editing: b.budget,
                                    expenseCategories: expenseCategories,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Xóa',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteBudget(b.budget),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
