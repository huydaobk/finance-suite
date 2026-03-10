import 'package:flutter/material.dart';

class BillsPlaceholderScreen extends StatelessWidget {
  const BillsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hóa đơn'),
      ),
      body: const Center(
        child: Text('Chưa có hóa đơn'),
      ),
    );
  }
}
