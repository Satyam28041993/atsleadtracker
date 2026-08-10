import 'dart:io';

void main() {
  final file = File('test_quote.pdf');
  if (!file.existsSync()) {
    print('Error: test_quote.pdf does not exist!');
    return;
  }
  
  final bytes = file.readAsBytesSync();
  final content = String.fromCharCodes(bytes);
  
  print('Searching generated PDF for non-ASCII characters and checkbox codes...');
  
  // Let's check common unicode bullet and checkbox characters:
  // 0x2610: ☐ (ballot box)
  // 0x2611: ☑ (ballot box with check)
  // 0x2612: ☒ (ballot box with X)
  // 0x2022: • (bullet)
  
  final checkChars = {
    0x2610: '☐ (ballot box)',
    0x2611: '☑ (ballot box with check)',
    0x2612: '☒ (ballot box with X)',
    0x2022: '• (bullet)',
    0x2013: '– (en dash)',
    0x2713: '✓ (checkmark)',
    0x2714: '✔ (heavy checkmark)',
  };
  
  var foundAny = false;
  // In PDF, strings are often written in parentheses (string) or as hex <hex>
  // Let's scan the file for these bytes or character codes
  for (var code in checkChars.keys) {
    final charName = checkChars[code]!;
    // Search as UTF-8 bytes:
    // For example, U+2612 in UTF-8 is 0xE2 0x98 0x92
    // U+2022 is 0xE2 0x80 0xA2
    List<int> utf8Bytes;
    if (code == 0x2022) {
      utf8Bytes = [0xE2, 0x80, 0xA2];
    } else if (code == 0x2610) {
      utf8Bytes = [0xE2, 0x98, 0x90];
    } else if (code == 0x2611) {
      utf8Bytes = [0xE2, 0x98, 0x91];
    } else if (code == 0x2612) {
      utf8Bytes = [0xE2, 0x98, 0x92];
    } else if (code == 0x2013) {
      utf8Bytes = [0xE2, 0x80, 0x93];
    } else if (code == 0x2713) {
      utf8Bytes = [0xE2, 0x9C, 0x93];
    } else if (code == 0x2714) {
      utf8Bytes = [0xE2, 0x9C, 0x94];
    } else {
      continue;
    }
    
    // Simple substring search in bytes
    var matchCount = 0;
    for (var i = 0; i <= bytes.length - utf8Bytes.length; i++) {
      var match = true;
      for (var j = 0; j < utf8Bytes.length; j++) {
        if (bytes[i + j] != utf8Bytes[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        matchCount++;
      }
    }
    
    if (matchCount > 0) {
      print('FOUND UTF-8 bytes for $charName: $matchCount times');
      foundAny = true;
    }
  }
  
  if (!foundAny) {
    print('No standard UTF-8 checkbox or bullet characters found in the PDF bytes.');
  }
  
  // Let's also print any text definitions we find in the PDF
  print('\nScanning for text objects in PDF...');
  final lines = content.split('\n');
  for (var line in lines) {
    if (line.contains('Introduction') || line.contains('Techno-Commercial') || line.contains('Accuracy')) {
      print('PDF Line: ${line.trim()}');
    }
  }
}
