import '../app_database.dart';

mixin WalletsDao on AppDatabase {
  Stream<List<Wallet>> watchAllWallets() {
    return select(wallets).watch();
  }

  Future<Wallet> getWalletById(String id) {
    return (select(wallets)..where((tbl) => tbl.id.equals(id))).getSingle();
  }

  Future<void> insertWallet(WalletsCompanion entry) {
    return into(wallets).insert(entry);
  }

  Future<void> updateWallet(WalletsCompanion entry) {
    return update(wallets).replace(entry);
  }

  Future<void> deleteWallet(String id) {
    return (delete(wallets)..where((tbl) => tbl.id.equals(id))).go();
  }
}
