import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../budgets/presentation/screens/budgets_screen.dart';

class SettingsPlaceholderScreen extends StatelessWidget {
  const SettingsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Budgets (Ngân sách)'),
            subtitle:
                const Text('Thiết lập mức chi theo tháng / theo danh mục'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BudgetsScreen()),
              );
            },
          ),
          const Divider(height: 1),
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
        ],
      ),
    );
  }
}
