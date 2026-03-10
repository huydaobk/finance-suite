import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/db/app_database.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String _selectedStatus = 'new';

  List<String> get _statuses {
    if (_selectedStatus == 'all') return ['new', 'seen', 'dismissed'];
    return [_selectedStatus];
  }

  Future<void> _markSeen(String id) async {
    await AppDatabase.instance.updateAlertStatus(id, 'seen');
  }

  Future<void> _dismiss(String id) async {
    await AppDatabase.instance.updateAlertStatus(id, 'dismissed');
  }

  Future<void> _markAllSeen() async {
    await AppDatabase.instance.markAllNewAlertsSeen();
  }

  Future<void> _deleteAllDismissed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá tất cả cảnh báo đã ẩn?'),
        content: const Text('Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AppDatabase.instance.deleteAllDismissedAlerts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'new', label: Text('Mới')),
              ButtonSegment(value: 'seen', label: Text('Đã xem')),
              ButtonSegment(value: 'dismissed', label: Text('Đã ẩn')),
              ButtonSegment(value: 'all', label: Text('Tất cả')),
            ],
            selected: {_selectedStatus},
            onSelectionChanged: (v) {
              setState(() => _selectedStatus = v.first);
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _markAllSeen,
                icon: const Icon(Icons.done_all),
                label: const Text('Đánh dấu tất cả đã xem'),
              ),
              TextButton.icon(
                onPressed: _deleteAllDismissed,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Xoá tất cả dismissed'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<List<AlertEvent>>(
            stream: AppDatabase.instance.watchAlertEventsByStatus(_statuses),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Lỗi: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final alerts = snapshot.data!;
              if (alerts.isEmpty) {
                return _AlertsEmptyState(status: _selectedStatus);
              }

              final dateFmt = DateFormat('dd/MM HH:mm');

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: alerts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final a = alerts[index];
                  final created = dateFmt.format(a.createdAt);
                  final amount = _extractAmount(a.metaJson);

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  a.titleVi,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              _StatusChip(status: a.status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(a.bodyVi),
                          if (amount != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Số tiền: ${NumberFormat.decimalPattern('vi_VN').format(amount)}₫',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            created,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (a.status == 'new')
                                OutlinedButton(
                                  onPressed: () => _markSeen(a.id),
                                  child: const Text('Đánh dấu đã xem'),
                                ),
                              if (a.status != 'dismissed')
                                TextButton(
                                  onPressed: () => _dismiss(a.id),
                                  child: const Text('Ẩn'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  int? _extractAmount(String? metaJson) {
    if (metaJson == null || metaJson.isEmpty) return null;

    try {
      final decoded = jsonDecode(metaJson);
      if (decoded is! Map<String, dynamic>) return null;

      final value = decoded['amount'];
      if (value is int) return value;
      if (value is double) return value.round();
      if (value is String) return int.tryParse(value);
    } catch (_) {
      return null;
    }

    return null;
  }
}

class _AlertsEmptyState extends StatelessWidget {
  const _AlertsEmptyState({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final message = switch (status) {
      'new' => 'Không có cảnh báo mới',
      'seen' => 'Chưa có cảnh báo đã xem',
      'dismissed' => 'Chưa có cảnh báo đã ẩn',
      _ => 'Không có cảnh báo',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Các cảnh báo sẽ xuất hiện tại đây.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'new' => ('Mới', Colors.orange),
      'seen' => ('Đã xem', Colors.blue),
      'dismissed' => ('Đã ẩn', Colors.grey),
      _ => (status, Colors.grey),
    };

    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}
