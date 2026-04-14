import 'package:flutter/widgets.dart';

import 'workbench_notch.dart';

OverlayEntry? _entry;
int _retryCount = 0;
const _maxRetries = 30; // ~30 frames ≈ 500 ms at 60 fps

/// Programmatically insert the workbench notch into the running app's
/// [Overlay]. Call from [enableWorkbench] when `showOverlay: true`.
void insertWorkbenchOverlay() {
  if (_entry != null) return; // already active
  _retryCount = 0;

  // Ensure a binding exists (safe to call multiple times).
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addPostFrameCallback((_) => _tryInsert());
}

/// Remove the notch overlay if it was inserted.
void removeWorkbenchOverlay() {
  _entry?.remove();
  _entry?.dispose();
  _entry = null;
}

void _tryInsert() {
  final rootElement = WidgetsBinding.instance.rootElement;
  if (rootElement == null) {
    _scheduleRetry();
    return;
  }

  // Walk the element tree to find the topmost OverlayState (Navigator's).
  OverlayState? overlayState;
  void visitor(Element el) {
    if (overlayState != null) return;
    if (el is StatefulElement && el.state is OverlayState) {
      overlayState = el.state as OverlayState;
      return;
    }
    el.visitChildren(visitor);
  }

  rootElement.visitChildren(visitor);

  if (overlayState == null) {
    _scheduleRetry();
    return;
  }

  _entry = OverlayEntry(
    builder: (_) => const WorkbenchNotch(),
  );
  overlayState!.insert(_entry!);
}

void _scheduleRetry() {
  if (++_retryCount > _maxRetries) {
    // Give up silently — the app may not have a Navigator/Overlay.
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) => _tryInsert());
}
