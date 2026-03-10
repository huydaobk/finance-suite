import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final NumberFormat _vndNumberFormat = NumberFormat.decimalPattern('vi_VN');

String formatVnd(int amount) => _vndNumberFormat.format(amount);

int parseVnd(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0;
  return int.parse(digits);
}

class VndTextInputFormatter extends TextInputFormatter {
  const VndTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final formatted = formatVnd(int.parse(digits));
    final digitsBeforeCursor = _countDigitsBeforeCursor(
      newValue.text,
      newValue.selection.baseOffset,
    );
    final cursorOffset = _offsetForDigits(formatted, digitsBeforeCursor);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorOffset),
      composing: TextRange.empty,
    );
  }

  int _countDigitsBeforeCursor(String text, int cursorOffset) {
    final safeOffset = cursorOffset.clamp(0, text.length);
    return RegExp(r'\d').allMatches(text.substring(0, safeOffset)).length;
  }

  int _offsetForDigits(String formatted, int digitsCount) {
    if (digitsCount <= 0) return 0;

    var seenDigits = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (RegExp(r'\d').hasMatch(formatted[i])) {
        seenDigits++;
        if (seenDigits == digitsCount) {
          return i + 1;
        }
      }
    }

    return formatted.length;
  }
}
