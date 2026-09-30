// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:typed_data';
import 'dart:html' as html;

Future<void> downloadAndOpenPdf(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
