/// Flutter-specific widgets for [sqflite_dev].
///
/// Import this library from your Flutter app to access [SqfliteDevOverlay],
/// an in-app draggable notch that displays the running workbench server URLs
/// (Local and Network) without needing to check the console.
///
/// ```dart
/// import 'package:sqflite_dev/sqflite_dev.dart';
/// import 'package:sqflite_dev/sqflite_dev_flutter.dart';
///
/// void main() {
///   runApp(
///     SqfliteDevOverlay(
///       enabled: kDebugMode,
///       child: MyApp(),
///     ),
///   );
/// }
/// ```
///
/// This library imports `package:flutter/material.dart`, so it must only be
/// used from Flutter projects. Pure Dart consumers should continue to import
/// `package:sqflite_dev/sqflite_dev.dart` and skip this entry-point.
library sqflite_dev_flutter;

export 'src/workbench_overlay.dart';
