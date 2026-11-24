import 'dart:io';

import '../services/native_bridge.dart';
import 'blur_engine.dart';

/// Writes the blur-event history as pretty JSON into the app documents
/// directory and returns the file. No platform share sheet is used, so the app
/// needs no extra permissions.
Future<File> exportHistoryToFile() async {
  final directory = await nativeBridge.appDocumentsDirectory();
  final file = File(
    '$directory${Platform.pathSeparator}'
    'haram_blur_events_${DateTime.now().millisecondsSinceEpoch}.json',
  );
  await file.writeAsString(blurEngine.exportJson(), flush: true);
  return file;
}
