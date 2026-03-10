class TransferMetadata {
  const TransferMetadata({
    required this.pairId,
    this.fromWalletId,
    this.toWalletId,
  });

  final String pairId;
  final String? fromWalletId;
  final String? toWalletId;

  static const String transferOutPrefix = 'tx_transfer_out_';
  static const String transferInPrefix = 'tx_transfer_in_';
  static final RegExp _noteMarkerPattern = RegExp(
    r'^\[TRANSFER:([^\]]+)\]\[OUT:([^\]]+)\]\[IN:([^\]]+)\]\s*',
  );

  static TransferMetadata? tryParse({String? id, String? note}) {
    final fromId = _tryParseFromId(id);
    final fromNote = _tryParseFromNote(note);

    if (fromId != null && fromNote != null) {
      return fromId.pairId == fromNote.pairId ? fromNote : fromId;
    }

    return fromNote ?? fromId;
  }

  static TransferMetadata? _tryParseFromId(String? id) {
    if (id == null || id.isEmpty) return null;

    if (id.startsWith(transferOutPrefix)) {
      final pairId = id.substring(transferOutPrefix.length);
      return pairId.isEmpty ? null : TransferMetadata(pairId: pairId);
    }

    if (id.startsWith(transferInPrefix)) {
      final pairId = id.substring(transferInPrefix.length);
      return pairId.isEmpty ? null : TransferMetadata(pairId: pairId);
    }

    return null;
  }

  static TransferMetadata? _tryParseFromNote(String? note) {
    if (note == null) return null;

    final raw = note.trimLeft();
    final match = _noteMarkerPattern.firstMatch(raw);
    if (match == null) return null;

    final pairId = match.group(1)?.trim();
    final fromWalletId = match.group(2)?.trim();
    final toWalletId = match.group(3)?.trim();

    if ([pairId, fromWalletId, toWalletId]
        .any((value) => value == null || value.isEmpty)) {
      return null;
    }

    return TransferMetadata(
      pairId: pairId!,
      fromWalletId: fromWalletId,
      toWalletId: toWalletId,
    );
  }

  static String stripMarker(String? note) {
    if (note == null) return '';

    final match = _noteMarkerPattern.firstMatch(note);
    if (match == null) return note.trim();

    return note.substring(match.end).trim();
  }
}
