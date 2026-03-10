import 'package:flutter/material.dart';

class BudgetsPlaceholderScreen extends StatelessWidget {
  const BudgetsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ngân sách'),
      ),
      body: const Center(
        child: Text('Chưa có ngân sách'),
      ),
    );
  }
}
