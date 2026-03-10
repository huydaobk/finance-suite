import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/utils/vnd_format.dart';
import 'add_transaction_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _dateFmt = DateFormat('dd/MM/yyyy');

  DateTimeRange? _customRange;
  String _filterType = 'all';
  String? _filterWalletId;
  String? _filterCategoryId;
  String _search = '';

  DateTimeRange get _effectiveRange {
    if (_customRange != null) return _customRange!;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    return DateTimeRange(start: start, end: end);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _effectiveRange,
      locale: const Locale('vi', 'VN'),
    );

    if (picked != null) {
      setState(() => _customRange = picked);
    }
  }

  void _clearFilters() {
    setState(() {
      _customRange = null;
      _filterType = 'all';
      _filterWalletId = null;
      _filterCategoryId = null;
      _search = '';
    });
  }

  bool _matches(TransactionItem item) {
    final tx = item.tx;
    final lowerSearch = _search.trim().toLowerCase();

    if (_filterType != 'all' && tx.type != _filterType) return false;
    if (_filterWalletId != null && tx.walletId != _filterWalletId) return false;
    if (_filterCategoryId != null && tx.categoryId != _filterCategoryId) {
      return false;
    }

    if (lowerSearch.isNotEmpty) {
      final haystack = [
        tx.note ?? '',
        item.wallet.name,
        item.category.name,
        tx.id,
      ].join(' ').toLowerCase();
      if (!haystack.contains(lowerSearch)) return false;
    }

    return true;
  }

  String _groupLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    return _dateFmt.format(date);
  }

  @override
  Widget build(BuildContext context) {
    final range = _effectiveRange;
    final from = DateTime(range.start.year, range.start.month, range.start.day);
    final toExclusive =
        DateTime(range.end.year, range.end.month, range.end.day + 1);
    final db = AppDatabase.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử giao dịch'),
        actions: [
          IconButton(
            onPressed: _clearFilters,
            tooltip: 'Xóa bộ lọc',
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    hintText: 'Tìm theo ghi chú, ví, danh mục...',
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickRange,
                        icon: const Icon(Icons.date_range_outlined),
                        label: Text(
                          '${_dateFmt.format(range.start)} - ${_dateFmt.format(range.end)}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('Tất cả')),
                          ButtonSegment(value: 'expense', label: Text('Chi')),
                          ButtonSegment(value: 'income', label: Text('Thu')),
                          ButtonSegment(
                              value: 'transfer', label: Text('Chuyển')),
                        ],
                        selected: {_filterType},
                        onSelectionChanged: (values) {
                          setState(() => _filterType = values.first);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<Wallet>>(
                  stream: db.select(db.wallets).watch(),
                  builder: (context, walletSnap) {
                    final wallets = walletSnap.data ?? const <Wallet>[];
                    return DropdownButtonFormField<String?>(
                      initialValue: _filterWalletId,
                      decoration: const InputDecoration(
                        labelText: 'Lọc theo ví',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tất cả ví'),
                        ),
                        ...wallets.map(
                          (wallet) => DropdownMenuItem<String?>(
                            value: wallet.id,
                            child: Text(wallet.name),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _filterWalletId = value),
                    );
                  },
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<Category>>(
                  stream: db.select(db.categories).watch(),
                  builder: (context, catSnap) {
                    final categories = catSnap.data ?? const <Category>[];
                    return DropdownButtonFormField<String?>(
                      initialValue: _filterCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Lọc theo danh mục',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tất cả danh mục'),
                        ),
                        ...categories.map(
                          (category) => DropdownMenuItem<String?>(
                            value: category.id,
                            child: Text(category.name),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _filterCategoryId = value),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<TransactionItem>>(
              stream: db.watchTransactionItems(from: from, to: toExclusive),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Lỗi tải lịch sử: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final filtered = snapshot.data!.where(_matches).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off,
                              size: 56, color: Colors.grey.shade500),
                          const SizedBox(height: 12),
                          Text('Không có giao dịch phù hợp',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          const Text(
                            'Thử đổi khoảng thời gian hoặc bộ lọc để xem thêm dữ liệu.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final Map<String, List<TransactionItem>> grouped = {};
                for (final item in filtered) {
                  final key = _groupLabel(item.tx.occurredAt);
                  grouped.putIfAbsent(key, () => []).add(item);
                }

                final sections = grouped.entries.toList();
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sections.length,
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    final items = section.value;
                    final income = items
                        .where((e) => e.tx.type == 'income')
                        .fold<int>(0, (sum, e) => sum + e.tx.amount);
                    final expense = items
                        .where((e) => e.tx.type == 'expense')
                        .fold<int>(0, (sum, e) => sum + e.tx.amount);
                    final transfer = items
                        .where((e) => e.tx.type == 'transfer')
                        .fold<int>(0, (sum, e) => sum + e.tx.amount);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  section.key,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                'Thu ${formatVnd(income)}₫ · Chi ${formatVnd(expense)}₫${transfer > 0 ? ' · Chuyển ${formatVnd(transfer)}₫' : ''}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        ...items.map((item) => _HistoryTile(
                            item: item,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        AddTransactionScreen(existing: item)),
                              );
                              if (mounted) setState(() {});
                            })),
                        if (index != sections.length - 1)
                          const SizedBox(height: 16),
                      ],
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

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.onTap,
  });

  final TransactionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tx = item.tx;
    final isExpense = tx.type == 'expense';
    final isTransfer = tx.type == 'transfer';
    final color =
        isTransfer ? Colors.blue : (isExpense ? Colors.red : Colors.green);
    final sign = isTransfer ? '' : (isExpense ? '-' : '+');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            isTransfer
                ? Icons.swap_horiz_rounded
                : (isExpense ? Icons.arrow_downward : Icons.arrow_upward),
            color: color,
          ),
        ),
        title: Text(
          '$sign${formatVnd(tx.amount)}₫',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: Text(
          [
            item.category.name,
            item.wallet.name,
            if ((tx.note ?? '').trim().isNotEmpty) tx.note!.trim(),
          ].join(' • '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(DateFormat('HH:mm').format(tx.occurredAt)),
            const SizedBox(height: 4),
            Text(
              isTransfer ? 'Chuyển ví' : (isExpense ? 'Chi' : 'Thu'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
