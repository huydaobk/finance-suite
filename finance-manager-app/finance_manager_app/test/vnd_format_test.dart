import 'package:finance_manager_app/core/utils/vnd_format.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatVnd', () {
    test('format plain int with dot separators', () {
      expect(formatVnd(2000000), '2.000.000');
    });
  });

  group('parseVnd', () {
    test('parse plain digits', () {
      expect(parseVnd('2000000'), 2000000);
    });

    test('parse string with dots', () {
      expect(parseVnd('2.000.000'), 2000000);
    });

    test('parse string with commas', () {
      expect(parseVnd('2,000,000'), 2000000);
    });

    test('parse string with spaces', () {
      expect(parseVnd('2 000 000'), 2000000);
    });
  });

  group('VndTextInputFormatter', () {
    const formatter = VndTextInputFormatter();

    test('auto inserts separators while typing', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        ),
        const TextEditingValue(
          text: '2000000',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );

      expect(result.text, '2.000.000');
      expect(result.selection.baseOffset, result.text.length);
    });

    test('keeps cursor near edited position in middle', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '1.000',
          selection: TextSelection.collapsed(offset: 1),
        ),
        const TextEditingValue(
          text: '12000',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      expect(result.text, '12.000');
      expect(result.selection.baseOffset, 2);
    });
  });
}
