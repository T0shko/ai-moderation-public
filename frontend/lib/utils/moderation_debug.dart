import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Full scan payloads for developers — not shown in the UI.
void logVisionScan(String tag, Map<String, dynamic> payload) {
  if (!kDebugMode) return;
  const encoder = JsonEncoder.withIndent('  ');
  debugPrint('[$tag] ${encoder.convert(payload)}');
}
