import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

Future<TaskSnapshot> uploadBytes(
  Reference ref,
  Uint8List bytes,
  SettableMetadata metadata,
) async {
  final task = ref.putData(bytes, metadata);
  StreamSubscription<TaskSnapshot>? subscription;
  subscription = task.snapshotEvents.listen(
    (_) {},
    onError: (_) {},
    cancelOnError: true,
  );
  try {
    await task;
    return task.snapshot;
  } finally {
    await subscription.cancel();
  }
}
