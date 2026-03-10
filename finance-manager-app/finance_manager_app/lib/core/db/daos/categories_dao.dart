import '../app_database.dart';

mixin CategoriesDao on AppDatabase {
  Stream<List<Category>> watchAllCategories() {
    return select(categories).watch();
  }

  Future<Category> getCategoryById(String id) {
    return (select(categories)..where((tbl) => tbl.id.equals(id))).getSingle();
  }

  Future<void> insertCategory(CategoriesCompanion entry) {
    return into(categories).insert(entry);
  }

  Future<void> updateCategory(CategoriesCompanion entry) {
    return update(categories).replace(entry);
  }

  Future<void> deleteCategory(String id) {
    return (delete(categories)..where((tbl) => tbl.id.equals(id))).go();
  }
}
