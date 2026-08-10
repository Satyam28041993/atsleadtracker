import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:atsleadtracker/firebase_options.dart';

Future<void> main() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final db = FirebaseFirestore.instance;
  final snapshot = await db.collection('quotations').get();
  
  int updated = 0;
  for (final doc in snapshot.docs) {
    final data = doc.data();
    final currentRefNo = data['currentRefNo'] as String? ?? '';
    
    final badFormatRegex = RegExp(r'^(.+)/(\d{4}-\d{4})-R(\d+)$');
    final match = badFormatRegex.firstMatch(currentRefNo);
    
    if (match != null) {
      final headParts = match.group(1);
      final yearPart = match.group(2);
      final rev = match.group(3);
      
      final newRefNo = '$headParts-R$rev/$yearPart';
      
      final quoteReq = Map<String, dynamic>.from(data['quoteRequest'] as Map? ?? {});
      quoteReq['refNo'] = newRefNo;
      
      print('Updating $currentRefNo -> $newRefNo');
      await doc.reference.update({
        'currentRefNo': newRefNo,
        'quoteRequest': quoteReq,
      });
      updated++;
    }
  }
  print('Done. Updated $updated quotations.');
}
