import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'core/db/app_database.dart';
import 'core/utils/vnd_format.dart';
import 'core/seed/default_seed.dart';
import 'features/alerts/presentation/screens/alerts_screen.dart';
import 'features/transactions/presentation/screens/transactions_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';

void main() {
  runApp(const FinanceManagerApp());
}

class FinanceManagerApp extends StatelessWidget {
  const FinanceManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quản lý tài chính',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi', 'VN'),
      supportedLocales: const [
        Locale('vi', 'VN'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await DefaultSeed(AppDatabase.instance).run();
  }

  final List<String> _titles = [
    'Tổng quan',
    'Giao dịch',
    'Cảnh báo',
    'Cài đặt',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          const OverviewScreen(),
          TransactionsScreen(),
          const AlertsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Tổng quan',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Giao dịch',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Cảnh báo',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }
}

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  final AppDatabase _db = AppDatabase.instance;
  late DateTime _selectedMonth;
  late DateFormat _monthLabelFormat;
  late NumberFormat _moneyFormat;

  static const List<Color> _chartColors = [
    Color(0xFF4E79A7),
    Color(0xFFF28E2B),
    Color(0xFF59A14F),
    Color(0xFFE15759),
    Color(0xFF76B7B2),
    Color(0xFFEDC948),
    Color(0xFFB07AA1),
    Color(0xFFFF9DA7),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _monthLabelFormat = DateFormat('MM/yyyy', 'vi_VN');
    _moneyFormat = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );
  }

  DateTime get _monthStart =>
      DateTime(_selectedMonth.year, _selectedMonth.month);

  DateTime get _nextMonthStart =>
      DateTime(_selectedMonth.year, _selectedMonth.month + 1);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OverviewAnalytics>(
      stream: _db.watchOverviewAnalytics(
        from: _monthStart,
        to: _nextMonthStart,
        monthsBack: 6,
      ),
      builder: (context, snapshot) {
        final analytics = snapshot.data;

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedMonth = DateTime(
                          _selectedMonth.year,
                          _selectedMonth.month - 1,
                        );
                      });
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Tháng ${_monthLabelFormat.format(_selectedMonth)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      final now = DateTime.now();
                      final currentMonth = DateTime(now.year, now.month);
                      if (_selectedMonth.isBefore(currentMonth)) {
                        setState(() {
                          _selectedMonth = DateTime(
                            _selectedMonth.year,
                            _selectedMonth.month + 1,
                          );
                        });
                      }
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SummaryCards(
                summary: analytics!.summary,
                moneyFormat: _moneyFormat,
              ),
              const SizedBox(height: 16),
              _ExpenseBreakdownCard(
                data: analytics.expenseByCategory,
                moneyFormat: _moneyFormat,
                chartColors: _chartColors,
              ),
              const SizedBox(height: 16),
              _SixMonthTrendCard(
                points: analytics.monthlyTrend,
                monthFormat: _monthLabelFormat,
                moneyFormat: _moneyFormat,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.summary,
    required this.moneyFormat,
  });

  final MonthSummary summary;
  final NumberFormat moneyFormat;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SummaryCardTile(
          title: 'Tổng thu',
          value: '${formatVnd(summary.income)}₫',
          color: Colors.green,
          icon: Icons.trending_up,
        ),
        const SizedBox(height: 8),
        _SummaryCardTile(
          title: 'Tổng chi',
          value: '${formatVnd(summary.expense)}₫',
          color: Colors.red,
          icon: Icons.trending_down,
        ),
        const SizedBox(height: 8),
        _SummaryCardTile(
          title: 'Ròng',
          value: '${formatVnd(summary.net)}₫',
          color: summary.net >= 0 ? Colors.blue : Colors.orange,
          icon: Icons.account_balance_wallet_outlined,
        ),
      ],
    );
  }
}

class _SummaryCardTile extends StatelessWidget {
  const _SummaryCardTile({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _ExpenseBreakdownCard extends StatelessWidget {
  const _ExpenseBreakdownCard({
    required this.data,
    required this.moneyFormat,
    required this.chartColors,
  });

  final List<CategoryExpenseTotal> data;
  final NumberFormat moneyFormat;
  final List<Color> chartColors;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chi tiêu theo danh mục',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (data.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.pie_chart_outline,
                          size: 48, color: Colors.grey),
                      SizedBox(height: 10),
                      Text('Không có dữ liệu chi tiêu tháng này'),
                    ],
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 220,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 36,
                    sectionsSpace: 2,
                    sections: List.generate(data.length, (index) {
                      final item = data[index];
                      final color = chartColors[index % chartColors.length];
                      return PieChartSectionData(
                        value: item.total.toDouble(),
                        color: color,
                        radius: 72,
                        title: '${item.percent.toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...List.generate(data.length, (index) {
                final item = data[index];
                final color = chartColors[index % chartColors.length];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.categoryName)),
                      Text(
                        '${formatVnd(item.total)}₫',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _SixMonthTrendCard extends StatelessWidget {
  const _SixMonthTrendCard({
    required this.points,
    required this.monthFormat,
    required this.moneyFormat,
  });

  final List<MonthlyTrendPoint> points;
  final DateFormat monthFormat;
  final NumberFormat moneyFormat;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Xu hướng 6 tháng gần nhất',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (points.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.show_chart, size: 48, color: Colors.grey),
                      SizedBox(height: 10),
                      Text('Chưa có dữ liệu giao dịch'),
                    ],
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 230,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: true),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= points.length) {
                              return const SizedBox.shrink();
                            }
                            final label = monthFormat
                                .format(points[index].month)
                                .substring(0, 5);
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(label,
                                  style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 54,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              _compactMoney(value),
                              style: const TextStyle(fontSize: 10),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        color: Colors.red,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        spots: List.generate(points.length, (index) {
                          return FlSpot(index.toDouble(),
                              points[index].expense.toDouble());
                        }),
                      ),
                      LineChartBarData(
                        isCurved: true,
                        color: Colors.green,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        spots: List.generate(points.length, (index) {
                          return FlSpot(index.toDouble(),
                              points[index].income.toDouble());
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendItem(color: Colors.red, label: 'Chi'),
                  SizedBox(width: 16),
                  _LegendItem(color: Colors.green, label: 'Thu'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Tháng mới nhất: Thu ${formatVnd(points.last.income)}₫ | '
                'Chi ${formatVnd(points.last.expense)}₫',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _compactMoney(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(0)}tr';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}k';
    }
    return value.toStringAsFixed(0);
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

// Settings screen is implemented in features/settings (SettingsPlaceholderScreen).
