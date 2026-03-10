import 'package:drift/drift.dart';

class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get currency => text().withDefault(const Constant('VND'))();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // income | expense
  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get parentId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get type => text()(); // income | expense
  IntColumn get amount => integer()(); // VND
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get createdBy => text().nullable()(); // future multi-user
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get month => text()(); // YYYY-MM
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)(); // null = total
  IntColumn get limitAmount => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Bills extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get walletId => text().references(Wallets, #id)();
  IntColumn get dueDay => integer()(); // 1..31
  IntColumn get remindBeforeDays => integer().withDefault(const Constant(3))();
  IntColumn get amountExpected => integer().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class AlertEvents extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get titleVi => text()();
  TextColumn get bodyVi => text()();
  TextColumn get status =>
      text().withDefault(const Constant('new'))(); // new|seen|dismissed
  TextColumn get metaJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
