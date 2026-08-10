// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// Fires [onVisible] when the browser tab becomes visible again.
void listenTabVisibility(void Function() onVisible) {
  html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      onVisible();
    }
  });
}
