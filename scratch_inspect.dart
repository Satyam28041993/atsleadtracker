// Deprecated scratch file removed for cleanup.


void main() {
  final file = File('d:/Users/user/Desktop/atsleadtracker/lib/services/pdf_service.dart');
  final content = file.readAsStringSync();
  final matches = RegExp(r'Introduction', caseSensitive: false).allMatches(content);
  print('Total matches for "Introduction": ${matches.length}');
  for (var m in matches) {
    print('Match at offset ${m.start}: "${content.substring((m.start - 20).clamp(0, content.length), (m.end + 20).clamp(0, content.length))}"');
  }
}
