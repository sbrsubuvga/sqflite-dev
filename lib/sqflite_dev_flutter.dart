/// Flutter overlay support for sqflite_dev.
///
/// Provides [registerOverlayHandler] to connect your in-app overlay widget
/// to `enableWorkbench(webDebugInfoOverlay: true)`.
///
/// See `example/lib/widgets/workbench_notch.dart` for a ready-to-use
/// Flutter overlay implementation.
library sqflite_dev_flutter;

export 'src/workbench_overlay.dart' show registerOverlayHandler;
