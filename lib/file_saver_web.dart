import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

Future<bool> saveTextFile({required String filename, required String content}) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return true;
}

Future<String?> pickTextFile({List<String> accept = const ['.json']}) async {
  final input = html.FileUploadInputElement()..accept = accept.join(',');
  input.style.display = 'none';
  html.document.body?.append(input);

  final completer = Completer<String?>();
  input.onChange.first.then((_) async {
    try {
      final file = (input.files?.isNotEmpty == true) ? input.files!.first : null;
      if (file == null) {
        completer.complete(null);
        return;
      }
      final reader = html.FileReader();
      reader.readAsText(file);
      await reader.onLoadEnd.first;
      completer.complete(reader.result as String?);
    } catch (e) {
      completer.completeError(e);
    } finally {
      input.remove();
    }
  });

  input.click();
  return completer.future;
}
