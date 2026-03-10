import 'package:flutter/material.dart';

class TransactionsPlaceholderScreen extends StatelessWidget {
  const TransactionsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giao dịch'),
      ),
      body: const Center(
        child: Text('Chưa có giao dịch'),
      ),
    );
  }
}
