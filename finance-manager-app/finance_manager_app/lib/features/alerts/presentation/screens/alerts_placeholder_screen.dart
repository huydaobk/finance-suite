import 'package:flutter/material.dart';

class AlertsPlaceholderScreen extends StatelessWidget {
  const AlertsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cảnh báo'),
      ),
      body: const Center(
        child: Text('Không có cảnh báo'),
      ),
    );
  }
}
