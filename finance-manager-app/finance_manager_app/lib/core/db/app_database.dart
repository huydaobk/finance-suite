import 'package:drift/drift.dart';
import 'package:rxdart/rxdart.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../transactions/transfer_metadata.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Wallets,
    Categories,
    Transactions,
    Budgets,
    Bills,
    AlertEvents,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(_openConnection());
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  static AppDatabase? _instance;

  static AppDatabase get instance {
    _instance ??= AppDatabase._();
    return _instance!;
  }

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'finance_manager_db');
  }

  Stream<List<TransactionItem>> watchTransactionItems({
    DateTime? from,
    DateTime? to,
  }) {
    final q = select(transactions).join([
      leftOuterJoin(wallets, wallets.id.equalsExp(transactions.walletId)),
      leftOuterJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ])
      ..orderBy([
        OrderingTerm.desc(transactions.occurredAt),
        OrderingTerm.desc(transactions.createdAt),
      ]);

    if (from != null) {
      q.where(transactions.occurredAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      q.where(transactions.occurredAt.isSmallerThanValue(to));
    }

    return q.watch().map((rows) {
      return rows.map((row) {
        return TransactionItem(
          tx: row.readTable(transactions),
          wallet: row.readTable(wallets),
          category: row.readTable(categories),
        );
      }).toList();
    });
  }

  Stream<MonthSummary> watchMonthSummary({
    required DateTime from,
    required DateTime to,
  }) {
    final q = selectOnly(transactions)
      ..addColumns([transactions.type, transactions.amount])
      ..where(transactions.occurredAt.isBiggerOrEqualValue(from))
      ..where(transactions.occurredAt.isSmallerThanValue(to))
      ..where(transactions.type.isIn(const ['income', 'expense']));

    return q.watch().map(_computeMonthSummary);
  }

  Stream<List<CategoryExpenseTotal>> watchExpenseByCategory({
    required DateTime from,
    required DateTime to,
  }) {
    final q = select(transactions).join([
      leftOuterJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ])
      ..where(transactions.occurredAt.isBiggerOrEqualValue(from))
      ..where(transactions.occurredAt.isSmallerThanValue(to))
      ..where(transactions.type.equals('expense'));

    return q.watch().map((rows) {
      final Map<String, int> totals = {};
      final Map<String, String> names = {};
      int totalExpense = 0;

      for (final row in rows) {
        final tx = row.readTable(transactions);
        final category = row.readTableOrNull(categories);
        final categoryId = tx.categoryId;
        final amount = tx.amount;

        totals[categoryId] = (totals[categoryId] ?? 0) + amount;
        names[categoryId] = category?.name ?? 'Khác';
        totalExpense += amount;
      }

      final list = totals.entries.map((entry) {
        final percent = totalExpense > 0 ? (entry.value * 100 / totalExpense) : 0.0;
        return CategoryExpenseTotal(
          categoryId: entry.key,
          categoryName: names[entry.key] ?? 'Khác',
          total: entry.value,
          percent: percent,
        );
      }).toList();

      list.sort((a, b) => b.total.compareTo(a.total));
      return list;
    });
  }

  Stream<List<MonthlyTrendPoint>> watchMonthlyTrend({
    required DateTime anchorMonth,
    int monthsBack = 6,
  }) {
    final normalizedAnchor = DateTime(anchorMonth.year, anchorMonth.month);
    final startMonth = DateTime(normalizedAnchor.year, normalizedAnchor.month - (monthsBack - 1));
    final endExclusive = DateTime(normalizedAnchor.year, normalizedAnchor.month + 1);

    final q = selectOnly(transactions)
      ..addColumns([
        transactions.occurredAt,
        transactions.type,
        transactions.amount,
      ])
      ..where(transactions.occurredAt.isBiggerOrEqualValue(startMonth))
      ..where(transactions.occurredAt.isSmallerThanValue(endExclusive))
      ..where(transactions.type.isIn(const ['income', 'expense']));

    return q.watch().map((rows) {
      final Map<String, _IncomeExpense> grouped = {};

      for (final row in rows) {
        final occurredAt = row.read(transactions.occurredAt);
        final type = row.read(transactions.type);
        final amount = row.read(transactions.amount) ?? 0;

        if (occurredAt == null || type == null) continue;

        final monthKey = '${occurredAt.year.toString().padLeft(4, '0')}-${occurredAt.month.toString().padLeft(2, '0')}';
        final bucket = grouped.putIfAbsent(monthKey, () => const _IncomeExpense());

        if (type == 'income') {
          grouped[monthKey] = bucket.copyWith(income: bucket.income + amount);
        } else if (type == 'expense') {
          grouped[monthKey] = bucket.copyWith(expense: bucket.expense + amount);
        }
      }

      final List<MonthlyTrendPoint> points = [];
      for (int i = 0; i < monthsBack; i++) {
        final month = DateTime(startMonth.year, startMonth.month + i);
        final monthKey =
            '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
        final data = grouped[monthKey] ?? const _IncomeExpense();
        points.add(
          MonthlyTrendPoint(
            month: month,
            income: data.income,
            expense: data.expense,
          ),
        );
      }

      return points;
    });
  }

  Stream<OverviewAnalytics> watchOverviewAnalytics({
    required DateTime from,
    required DateTime to,
    int monthsBack = 6,
  }) {
    final anchorMonth = DateTime(from.year, from.month);

    return Rx.combineLatest3<MonthSummary, List<CategoryExpenseTotal>,
        List<MonthlyTrendPoint>, OverviewAnalytics>(
      watchMonthSummary(from: from, to: to),
      watchExpenseByCategory(from: from, to: to),
      watchMonthlyTrend(anchorMonth: anchorMonth, monthsBack: monthsBack),
      (summary, byCategory, trend) => OverviewAnalytics(
        summary: summary,
        expenseByCategory: byCategory,
        monthlyTrend: trend,
      ),
    );
  }

  MonthSummary _computeMonthSummary(List<TypedResult> rows) {
    int income = 0;
    int expense = 0;
    for (final row in rows) {
      final type = row.read(transactions.type);
      final amount = row.read(transactions.amount) ?? 0;
      if (type == 'income') {
        income += amount;
      } else if (type == 'expense') {
        expense += amount;
      }
    }
    return MonthSummary(income: income, expense: expense);
  }

  Stream<List<AlertEvent>> watchAlertEventsByStatus(List<String> statuses) {
    final q = select(alertEvents)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
      ]);

    if (statuses.isNotEmpty) {
      q.where((t) => t.status.isIn(statuses));
    }

    return q.watch();
  }

  Future<void> updateAlertStatus(String id, String status) {
    return (update(alertEvents)..where((t) => t.id.equals(id))).write(
      AlertEventsCompanion(status: Value(status)),
    );
  }

  Future<void> markAllNewAlertsSeen() {
    return (update(alertEvents)..where((t) => t.status.equals('new'))).write(
      const AlertEventsCompanion(status: Value('seen')),
    );
  }

  Future<void> deleteAllDismissedAlerts() {
    return (delete(alertEvents)..where((t) => t.status.equals('dismissed'))).go();
  }

  Stream<List<BudgetWithCategory>> watchBudgetsForMonth(String month) {
    final q = select(budgets).join([
      leftOuterJoin(categories, categories.id.equalsExp(budgets.categoryId)),
    ])
      ..where(budgets.month.equals(month))
      ..orderBy([
        OrderingTerm.asc(budgets.categoryId),
      ]);

    return q.watch().map((rows) {
      return rows.map((row) {
        final b = row.readTable(budgets);
        // categoryId can be null
        final c = row.readTableOrNull(categories);
        return BudgetWithCategory(budget: b, category: c);
      }).toList();
    });
  }

  Future<void> upsertBudget({
    required String month,
    String? categoryId,
    required int limitAmount,
  }) async {
    final id = 'budget_${month}_${categoryId ?? 'total'}';

    await into(budgets).insertOnConflictUpdate(
      BudgetsCompanion.insert(
        id: id,
        month: month,
        categoryId: Value(categoryId),
        limitAmount: limitAmount,
      ),
    );
  }

  Future<void> deleteBudget(String id) =>
      (delete(budgets)..where((b) => b.id.equals(id))).go();

  Stream<TotalBudget?> watchTotalBudgetForMonth(String month) {
    final q = select(budgets)
      ..where((b) => b.month.equals(month) & b.categoryId.isNull());

    return q.watchSingleOrNull().map((b) {
      if (b == null) return null;
      return TotalBudget(month: b.month, limitAmount: b.limitAmount);
    });
  }

  // ── Bills DAO ──────────────────────────────────────────────────────────────

  Stream<List<BillWithDetails>> watchBills() {
    final q = select(bills).join([
      innerJoin(categories, categories.id.equalsExp(bills.categoryId)),
      innerJoin(wallets, wallets.id.equalsExp(bills.walletId)),
    ])
      ..orderBy([OrderingTerm.asc(bills.dueDay)]);

    return q.watch().map((rows) => rows
        .map((row) => BillWithDetails(
              bill: row.readTable(bills),
              category: row.readTable(categories),
              wallet: row.readTable(wallets),
            ))
        .toList());
  }

  Future<void> insertBill(BillsCompanion companion) =>
      into(bills).insert(companion);

  Future<void> toggleBillActive(String id, bool active) =>
      (update(bills)..where((b) => b.id.equals(id)))
          .write(BillsCompanion(active: Value(active)));

  Future<void> deleteBill(String id) =>
      (delete(bills)..where((b) => b.id.equals(id))).go();

  Future<void> maybeCreateBillDueAlerts() async {
    final today = DateTime.now();
    final monthKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}';
    final allBills = await select(bills).get();
    for (final bill in allBills) {
      if (!bill.active) continue;
      final daysLeft = bill.dueDay - today.day;
      if (daysLeft < 0 || daysLeft > bill.remindBeforeDays) continue;
      final alertId = 'alert_bill_due_${bill.id}_$monthKey';
      final existing = await (select(alertEvents)
            ..where((a) => a.id.equals(alertId)))
          .getSingleOrNull();
      if (existing != null) continue;
      await into(alertEvents).insert(AlertEventsCompanion.insert(
        id: alertId,
        type: 'bill_due',
        titleVi: 'Sắp đến hạn: ${bill.name}',
        bodyVi:
            'Hóa đơn "${bill.name}" đến hạn ngày ${bill.dueDay}/$monthKey.',
        metaJson: Value('{"billId":"${bill.id}","month":"$monthKey"}'),
      ));
    }
  }

  Future<void> deleteAllTransactions() => delete(transactions).go();

  Future<Category> ensureTransferCategory() async {
    final existing = await (select(categories)
          ..where((c) => c.id.equals('cat_transfer_internal')))
        .getSingleOrNull();
    if (existing != null) return existing;

    await into(categories).insertOnConflictUpdate(
      CategoriesCompanion.insert(
        id: 'cat_transfer_internal',
        name: 'Chuyển ví',
        type: 'transfer',
      ),
    );

    return (select(categories)..where((c) => c.id.equals('cat_transfer_internal')))
        .getSingle();
  }

  Future<void> createWalletTransfer({
    required String pairId,
    required String fromWalletId,
    required String toWalletId,
    required int amount,
    required DateTime occurredAt,
    required String categoryId,
    String? note,
  }) async {
    final fromWallet = await (select(wallets)..where((w) => w.id.equals(fromWalletId))).getSingle();
    final toWallet = await (select(wallets)..where((w) => w.id.equals(toWalletId))).getSingle();
    final cleanNote = (note ?? '').trim();

    await transaction(() async {
      await into(transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx_transfer_out_$pairId',
          walletId: fromWalletId,
          categoryId: categoryId,
          type: 'transfer',
          amount: amount,
          occurredAt: occurredAt,
          note: Value(
            '[TRANSFER:$pairId][OUT:$fromWalletId][IN:$toWalletId] '
            '${cleanNote.isEmpty ? 'Chuyển sang ${toWallet.name}' : cleanNote}',
          ),
        ),
      );

      await into(transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx_transfer_in_$pairId',
          walletId: toWalletId,
          categoryId: categoryId,
          type: 'transfer',
          amount: amount,
          occurredAt: occurredAt,
          note: Value(
            '[TRANSFER:$pairId][OUT:$fromWalletId][IN:$toWalletId] '
            '${cleanNote.isEmpty ? 'Nhận từ ${fromWallet.name}' : cleanNote}',
          ),
        ),
      );
    });
  }

  Future<void> deleteTransaction(String id) async {
    final existingTx = await (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
    final transferMeta = TransferMetadata.tryParse(
      id: id,
      note: existingTx?.note,
    );
    final pairId = transferMeta?.pairId;

    if (pairId == null || pairId.isEmpty) {
      await (delete(transactions)..where((t) => t.id.equals(id))).go();
      return;
    }

    final relatedIds = [
      '${TransferMetadata.transferOutPrefix}$pairId',
      '${TransferMetadata.transferInPrefix}$pairId',
    ];

    await transaction(() async {
      final existingRows = await (select(transactions)
            ..where((t) => t.id.isIn(relatedIds)))
          .get();

      if (existingRows.length <= 1) {
        await (delete(transactions)..where((t) => t.id.equals(id))).go();
        return;
      }

      await (delete(transactions)..where((t) => t.id.isIn(relatedIds))).go();
    });
  }

  Future<void> updateTransaction({
    required String id,
    required String type,
    required int amount,
    required String walletId,
    required String categoryId,
    required DateTime occurredAt,
    String? note,
  }) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          type: Value(type),
          amount: Value(amount),
          walletId: Value(walletId),
          categoryId: Value(categoryId),
          occurredAt: Value(occurredAt),
          note: Value(note),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<List<Wallet>> getWallets() => select(wallets).get();

  // ── Overspend alert ────────────────────────────────────────────────────────

  Future<void> maybeCreateOverspendAlert({
    required String month,
    required int expense,
    required int limitAmount,
  }) async {
    if (expense <= limitAmount) return;

    final overBy = expense - limitAmount;
    final alertId = 'alert_overspend_$month';

    String fmt(int v) {
      // Format as vi_VN currency-like (no decimals) with ₫ suffix.
      final s = v.toString();
      final out = StringBuffer();
      int group = 0;
      for (int i = s.length - 1; i >= 0; i--) {
        out.write(s[i]);
        group++;
        if (group == 3 && i != 0) {
          out.write(',');
          group = 0;
        }
      }
      return out.toString().split('').reversed.join();
    }

    // If already exists, do nothing (avoid spamming).
    final existing = await (select(alertEvents)
          ..where((a) => a.id.equals(alertId)))
        .getSingleOrNull();
    if (existing != null) return;

    await into(alertEvents).insert(
      AlertEventsCompanion.insert(
        id: alertId,
        type: 'overspend',
        titleVi: 'Vượt ngân sách tháng',
        bodyVi:
            'Tháng $month: chi ${fmt(expense)}₫, ngân sách ${fmt(limitAmount)}₫ (vượt ${fmt(overBy)}₫).',
        metaJson: Value(
          '{"month":"$month","expense":$expense,"limit":$limitAmount,"overBy":$overBy}',
        ),
      ),
    );
  }
}

class BudgetWithCategory {
  const BudgetWithCategory({
    required this.budget,
    required this.category,
  });

  final Budget budget;
  final Category? category;
}

class TransactionItem {
  const TransactionItem({
    required this.tx,
    required this.wallet,
    required this.category,
  });

  final Transaction tx;
  final Wallet wallet;
  final Category category;
}

class TotalBudget {
  const TotalBudget({
    required this.month,
    required this.limitAmount,
  });

  final String month;
  final int limitAmount;
}

class MonthSummary {
  const MonthSummary({
    required this.income,
    required this.expense,
  });

  final int income;
  final int expense;

  int get net => income - expense;
}

class CategoryExpenseTotal {
  const CategoryExpenseTotal({
    required this.categoryId,
    required this.categoryName,
    required this.total,
    required this.percent,
  });

  final String categoryId;
  final String categoryName;
  final int total;
  final double percent;
}

class MonthlyTrendPoint {
  const MonthlyTrendPoint({
    required this.month,
    required this.income,
    required this.expense,
  });

  final DateTime month;
  final int income;
  final int expense;
}

class OverviewAnalytics {
  const OverviewAnalytics({
    required this.summary,
    required this.expenseByCategory,
    required this.monthlyTrend,
  });

  final MonthSummary summary;
  final List<CategoryExpenseTotal> expenseByCategory;
  final List<MonthlyTrendPoint> monthlyTrend;
}

// ─── Bills ───────────────────────────────────────────────────────────────────

class BillWithDetails {
  const BillWithDetails({
    required this.bill,
    required this.category,
    required this.wallet,
  });

  final Bill bill;
  final Category category;
  final Wallet wallet;
}

// ─── Internal helpers ─────────────────────────────────────────────────────────

class _IncomeExpense {
  const _IncomeExpense({
    this.income = 0,
    this.expense = 0,
  });

  final int income;
  final int expense;

  _IncomeExpense copyWith({
    int? income,
    int? expense,
  }) {
    return _IncomeExpense(
      income: income ?? this.income,
      expense: expense ?? this.expense,
    );
  }
}


