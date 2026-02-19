// GENERATED (manual) Firebase options for iOS.
// This file was created to ensure Firebase.initializeApp has explicit options.
// If you later run `flutterfire configure`, you can replace this file.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;

      // This project bundle did not include Android/macOS/windows/linux configs.
      default:
        throw UnsupportedError(
          'FirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDApm08LAdAVFnhjoW0ufdbPF7dRlU_0SI',
    appId: '1:618778228430:ios:8489bdc31bdad427b2429f',
    messagingSenderId: '618778228430',
    projectId: 'cold-bore',
    storageBucket: 'cold-bore.firebasestorage.app',
    iosBundleId: 'com.remington.coldbore',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBk7XTRmf8bzUOLA7wGems1PKkxmpV5aYE',
    appId: '1:618778228430:web:a39f33f769df280eb2429f',
    messagingSenderId: '618778228430',
    projectId: 'cold-bore',
    authDomain: 'cold-bore.firebaseapp.com',
    storageBucket: 'cold-bore.firebasestorage.app',
    measurementId: 'G-3GDJ4YPKZ4',
  );

}