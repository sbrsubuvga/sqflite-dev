import 'workbench_server.dart';

/// Registers a callback as the overlay handler.
///
/// Call this from your Flutter app before [enableWorkbench] to wire up the
/// in-app notch overlay. Pass a function that inserts an overlay widget
/// into the running app (see the example for a full implementation).
///
/// In pure Dart contexts, skip this call — `webDebugInfoOverlay` will be
/// silently ignored.
void registerOverlayHandler(void Function() handler) {
  WorkbenchServer.instance.overlayHandler = handler;
}
