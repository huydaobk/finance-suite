import 'package:finance_manager_app/core/db/app_database.dart';
import 'package:drift/drift.dart';

class DefaultSeed {
  DefaultSeed(this.db);

  final AppDatabase db;

  Future<void> run() async {
    await _seedWallets();
    await _seedCategories();
    await _seedTransferCategory();
  }

  Future<void> _seedWallets() async {
    final wallets = [
      (id: 'wallet_cash', name: 'Tiền mặt'),
      (id: 'wallet_momo', name: 'Ví MoMo'),
      (id: 'wallet_bank', name: 'Ngân hàng'),
    ];

    for (final w in wallets) {
      await db.into(db.wallets).insertOnConflictUpdate(
            WalletsCompanion.insert(
              id: w.id,
              name: w.name,
              currency: const Value('VND'),
              openingBalance: const Value(0),
            ),
          );
    }
  }

  Future<void> _seedCategories() async {
    final expense = [
      'Ăn uống',
      'Di chuyển',
      'Mua sắm',
      'Nhà cửa',
      'Hóa đơn',
      'Y tế',
      'Giáo dục',
      'Giải trí',
      'Du lịch',
      'Quà tặng',
      'Thú cưng',
      'Khác',
    ];

    final income = [
      'Lương',
      'Thưởng',
      'Hoàn tiền',
      'Bán hàng',
      'Khác',
    ];

    int i = 0;
    for (final name in expense) {
      await db.into(db.categories).insertOnConflictUpdate(
            CategoriesCompanion.insert(
              id: 'cat_exp_${i++}',
              name: name,
              type: 'expense',
            ),
          );
    }

    i = 0;
    for (final name in income) {
      await db.into(db.categories).insertOnConflictUpdate(
            CategoriesCompanion.insert(
              id: 'cat_inc_${i++}',
              name: name,
              type: 'income',
            ),
          );
    }
  }

  Future<void> _seedTransferCategory() async {
    await db.into(db.categories).insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: 'cat_transfer_internal',
            name: 'Chuyển ví',
            type: 'transfer',
          ),
        );
  }
}
