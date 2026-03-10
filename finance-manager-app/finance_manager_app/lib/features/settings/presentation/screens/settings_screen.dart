import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../budgets/presentation/screens/budgets_screen.dart';
import '../../../bills/presentation/screens/bills_screen.dart';
import '../../../../core/db/app_database.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmDeleteTransactions(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa toàn bộ giao dịch?'),
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
      await AppDatabase.instance.deleteAllTransactions();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa toàn bộ giao dịch.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const _SectionHeader('Quản lý'),
        ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: const Text('Ngân sách'),
          subtitle: const Text('Thiết lập mức chi theo tháng / danh mục'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BudgetsScreen()),
          ),
        ),
        const Divider(height: 1, indent: 16),
        ListTile(
          leading: const Icon(Icons.receipt_outlined),
          title: const Text('Hóa đơn định kỳ'),
          subtitle: const Text('Quản lý hóa đơn hàng tháng'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BillsScreen()),
          ),
        ),
        const Divider(height: 1),
        const _SectionHeader('Ví của tôi'),
        FutureBuilder<List<Wallet>>(
          future: AppDatabase.instance.getWallets(),
          builder: (context, snapshot) {
            final wallets = snapshot.data ?? [];
            if (wallets.isEmpty) {
              return const ListTile(
                leading: Icon(Icons.account_balance_wallet_outlined),
                title: Text('Chưa có ví nào'),
              );
            }
            return Column(
              children: wallets
                  .map((w) => ListTile(
                        leading: const Icon(
                            Icons.account_balance_wallet_outlined),
                        title: Text(w.name),
                        subtitle: Text(w.currency),
                      ))
                  .toList(),
            );
          },
        ),
        const Divider(height: 1),
        const _SectionHeader('Ứng dụng'),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final versionText = snapshot.hasData
                ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                : 'Đang tải...';
            return ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Phiên bản'),
              subtitle: Text(versionText),
            );
          },
        ),
        const Divider(height: 1),
        const _SectionHeader('Dữ liệu'),
        ListTile(
          leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
          title: const Text(
            'Xóa toàn bộ giao dịch',
            style: TextStyle(color: Colors.red),
          ),
          subtitle: const Text('Không thể hoàn tác'),
          onTap: () => _confirmDeleteTransactions(context),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
      ),
    );
  }
}
