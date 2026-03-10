// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'Quản lý tài chính';

  @override
  String get homeTab => 'Tổng quan';

  @override
  String get transactionsTab => 'Giao dịch';

  @override
  String get settingsTab => 'Cài đặt';

  @override
  String get transactionsTitle => 'Giao dịch';

  @override
  String get budgetsTitle => 'Ngân sách';

  @override
  String get billsTitle => 'Hóa đơn';

  @override
  String get alertsTitle => 'Cảnh báo';

  @override
  String get receiptScanTitle => 'Quét hóa đơn';

  @override
  String get settingsTitle => 'Cài đặt';

  @override
  String get overview => 'Tổng quan';

  @override
  String get noTransactions => 'Chưa có giao dịch';

  @override
  String get noBudgets => 'Chưa có ngân sách';

  @override
  String get noBills => 'Chưa có hóa đơn';

  @override
  String get noAlerts => 'Không có cảnh báo';
}
