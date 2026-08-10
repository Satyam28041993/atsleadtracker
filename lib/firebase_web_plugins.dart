import 'firebase_web_plugins_stub.dart'
    if (dart.library.html) 'firebase_web_plugins_web.dart' as impl;

void registerWebFirebasePlugins() => impl.registerWebFirebasePlugins();
