import 'package:firebase_storage_web/firebase_storage_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

void registerWebFirebasePlugins() {
  FirebaseStorageWeb.registerWith(webPluginRegistrar);
  SharedPreferencesPlugin.registerWith(webPluginRegistrar);
}
