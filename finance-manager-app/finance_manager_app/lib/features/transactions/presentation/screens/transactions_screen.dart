import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/transactions/transfer_metadata.dart';
import '../../../budgets/presentation/screens/budgets_screen.dart';
import 'add_transaction_screen.dart';
import 'history_screen.dart';
import 'telegram_sync_screen.dart';
import 'wallet_transfer_screen.dart';

class TransactionsScreen extends StatefulWidget {
  TransactionsScreen({
    super.key,
    AppDatabase? database,
    this.initialMonth,
    this.enableSideEffects = true,
  }) : database = database ?? AppDatabase.instance;

  final AppDatabase database;
  final DateTime? initialMonth;

  /// When false, skip post-frame side effects (useful for widget tests).
  final bool enableSideEffects;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late DateTime _month;

  AppDatabase get _db => widget.database;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth ?? DateTime.now();
    _month = DateTime(initial.year, initial.month);
  }

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  DateTime get _monthFrom => DateTime(_month.year, _month.month, 1);
  DateTime get _monthTo => DateTime(_month.year, _month.month + 1, 1);

  String get _monthLabel => '${_month.month.toString().padLeft(2, '0')}/${_month.year}';

  Future<void> _openAddTransaction() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
    );

    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã thêm giao dịch')),
      );
    }
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  Future<void> _openWalletTransfer() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WalletTransferScreen()),
    );

    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu chuyển tiền giữa ví')),
      );
    }
  }

  void _prevMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month + 1);
    });
  }

  void _goToCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'history',
            onPressed: _openHistory,
            tooltip: 'Lịch sử giao dịch',
            child: const Icon(Icons.history),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'transfer',
            onPressed: _openWalletTransfer,
            tooltip: 'Chuyển ví',
            child: const Icon(Icons.swap_horiz),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'sync',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final imported = await navigator.push<bool>(
                MaterialPageRoute(
                  builder: (_) => const TelegramSyncScreen(),
                ),
              );
              if (!mounted) return;
              if (imported == true) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Đã đồng bộ từ Telegram ✅')),
                );
              }
            },
            tooltip: 'Đồng bộ từ Telegram',
            child: const Icon(Icons.telegram),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: _openAddTransaction,
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: _prevMonth,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Tháng trước',
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
                  tooltip: 'Tháng sau',
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: _goToCurrentMonth,
                  child: const Text('Tháng này'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          StreamBuilder(
            stream: _db.watchMonthSummary(
              from: _monthFrom,
              to: _monthTo,
            ),
            builder: (context, snap) {
              final money = NumberFormat.decimalPattern('vi_VN');
              final s = snap.data;
              final income = s?.income ?? 0;
              final expense = s?.expense ?? 0;
              final net = (s?.net ?? 0);

              // Side-effect: overspend alert (one-per-month)
              // Skip this in widget tests to avoid pending timers/futures after dispose.
              if (widget.enableSideEffects) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final db = _db;
                  db.watchTotalBudgetForMonth(_monthKey).first.then((b) {
                    if (b == null) return;
                    db.maybeCreateOverspendAlert(
                      month: _monthKey,
                      expense: expense,
                      limitAmount: b.limitAmount,
                    );
                  });
                });
              }

              Color? netColor;
              if (net > 0) netColor = Colors.green;
              if (net < 0) netColor = Colors.red;

              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryTile(
                            label: 'Thu',
                            value: '+${money.format(income)}₫',
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SummaryTile(
                            label: 'Chi',
                            value: '-${money.format(expense)}₫',
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SummaryTile(
                            label: 'Số dư',
                            value: '${net >= 0 ? '+' : ''}${money.format(net)}₫',
                            color: netColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder(
                      stream: _db.watchTotalBudgetForMonth(_monthKey),
                      builder: (context, budgetSnap) {
                        final totalBudget = budgetSnap.data?.limitAmount;
                        return _MonthlyBudgetTile(
                          expense: expense,
                          totalBudget: totalBudget,
                          onSetupBudget: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const BudgetsScreen()),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder(
              stream: _db.watchTransactionItems(
                from: _monthFrom,
                to: _monthTo,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Lỗi: ${snapshot.error}'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const _TransactionsEmptyState();
                }

                final money = NumberFormat.decimalPattern('vi_VN');
                final dateFmt = DateFormat('dd/MM');

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final it = items[index];
                    final t = it.tx;
                    final isTransfer = t.type == 'transfer';
                    final sign = t.type == 'expense' ? '-' : '+';
                    final amountText = isTransfer
                        ? '↔ ${money.format(t.amount)}₫'
                        : '$sign${money.format(t.amount)}₫';
                    final dateText = dateFmt.format(t.occurredAt);
                    final meta =
                        '${it.category.name} • ${it.wallet.name} • $dateText';
                    final transferMeta = TransferMetadata.tryParse(
                      id: t.id,
                      note: t.note,
                    );
                    final note = TransferMetadata.stripMarker(t.note);

                    return Dismissible(
                      key: ValueKey(t.id),
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 16),
                        color: Colors.blue,
                        child: const Icon(Icons.edit, color: Colors.white),
                      ),
                      secondaryBackground: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        if (direction == DismissDirection.startToEnd) {
                          // Edit
                          await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AddTransactionScreen(existing: it),
                            ),
                          );
                          return false;
                        } else {
                          // Delete confirm
                          final isTransferPair = transferMeta != null;
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(
                                  isTransferPair ? 'Xóa chuyển ví?' : 'Xóa giao dịch?'),
                              content: Text(
                                isTransferPair
                                    ? 'Xóa giao dịch chuyển ví này? Nếu đủ cặp, hệ thống sẽ xóa cả 2 giao dịch liên quan.\n\n${note.isEmpty ? '$amountText ($meta)' : '$amountText ($note)'}'
                                    : 'Xóa khoản $amountText (${note.isEmpty ? meta : note})?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Hủy'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red),
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Xóa'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await _db.deleteTransaction(t.id);
                          }
                          return false;
                        }
                      },
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isTransfer
                                ? Colors.blueGrey.shade50
                                : t.type == 'expense'
                                    ? Colors.red.shade50
                                    : Colors.green.shade50,
                            child: Icon(
                              isTransfer
                                  ? Icons.swap_horiz
                                  : t.type == 'expense'
                                      ? Icons.arrow_downward
                                      : Icons.arrow_upward,
                              color: isTransfer
                                  ? Colors.blueGrey
                                  : t.type == 'expense'
                                      ? Colors.red
                                      : Colors.green,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            amountText,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isTransfer
                                  ? Colors.blueGrey
                                  : t.type == 'expense'
                                      ? Colors.red
                                      : Colors.green,
                            ),
                          ),
                          subtitle: Text(
                            note.isEmpty ? meta : '$note\n$meta',
                          ),
                          isThreeLine: note.isNotEmpty,
                          trailing: Text(
                            dateText,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionsEmptyState extends StatelessWidget {
  const _TransactionsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 12),
            Text(
              'Chưa có giao dịch nào',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Thêm giao dịch mới hoặc đồng bộ từ Telegram để bắt đầu.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withValues(alpha: 0.75),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _MonthlyBudgetTile extends StatelessWidget {
  const _MonthlyBudgetTile({
    required this.expense,
    required this.totalBudget,
    required this.onSetupBudget,
  });

  final int expense;
  final int? totalBudget;
  final VoidCallback onSetupBudget;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.decimalPattern('vi_VN');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ngân sách tháng', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          if (totalBudget == null || totalBudget! <= 0) ...[
            Row(
              children: [
                const Expanded(child: Text('Chưa có budget tổng cho tháng này')),
                TextButton(
                  onPressed: onSetupBudget,
                  child: const Text('Thiết lập budget'),
                ),
              ],
            ),
          ] else ...[
            Builder(
              builder: (context) {
                final usedPercentRaw = expense / totalBudget!;
                final usedPercent = usedPercentRaw.clamp(0, 1).toDouble();
                final usedPercentText = (usedPercentRaw * 100).toStringAsFixed(1);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đã dùng ${money.format(expense)}/${money.format(totalBudget)}₫ ($usedPercentText%)',
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: usedPercent),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
