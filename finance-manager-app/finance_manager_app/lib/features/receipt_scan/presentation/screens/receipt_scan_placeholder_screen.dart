import 'package:flutter/material.dart';

class ReceiptScanPlaceholderScreen extends StatelessWidget {
  const ReceiptScanPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét hóa đơn'),
      ),
      body: const Center(
        child: Text('Quét hóa đơn'),
      ),
    );
  }
}
