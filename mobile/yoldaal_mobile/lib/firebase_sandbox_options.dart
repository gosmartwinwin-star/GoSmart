import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class FirebaseSandboxOptions {
  static const String projectId = 'gosmart-sandbox-fd8f6';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase sandbox options are not configured for '
          '$defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAiMkMoAdNwTrtvqlWqNlD-Qi_F5Jysyls',
    appId: '1:428312240805:web:ca44fe447e3622554ea34c',
    messagingSenderId: '428312240805',
    projectId: projectId,
    authDomain: 'gosmart-sandbox-fd8f6.firebaseapp.com',
    storageBucket: 'gosmart-sandbox-fd8f6.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCrxjbbbTsVc_eMiBlvexxHeyySJ-Og8GM',
    appId: '1:428312240805:android:14c826254f9185b74ea34c',
    messagingSenderId: '428312240805',
    projectId: projectId,
    storageBucket: 'gosmart-sandbox-fd8f6.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCj6c0qlf98YYXKTVIRewZeuD8WqOTFYhY',
    appId: '1:428312240805:ios:49720560db2e8a584ea34c',
    messagingSenderId: '428312240805',
    projectId: projectId,
    storageBucket: 'gosmart-sandbox-fd8f6.firebasestorage.app',
    iosBundleId: 'com.example.gosmartMobile',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAiMkMoAdNwTrtvqlWqNlD-Qi_F5Jysyls',
    appId: '1:428312240805:web:0170f522af9604554ea34c',
    messagingSenderId: '428312240805',
    projectId: projectId,
    authDomain: 'gosmart-sandbox-fd8f6.firebaseapp.com',
    storageBucket: 'gosmart-sandbox-fd8f6.firebasestorage.app',
  );
}
