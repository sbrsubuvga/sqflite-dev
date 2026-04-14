import 'package:flutter/material.dart';

import 'workbench_notch.dart';

export 'workbench_notch.dart' show SqfliteDevOverlayAlignment;

/// An in-app overlay that displays the running sqflite_dev workbench server
/// URLs as a swipeable notch at the edge of the screen.
///
/// This is an **alternative** to `enableWorkbench(showOverlay: true)`.
/// Use this widget only when you need explicit control over placement or
/// want to gate visibility on a custom condition.
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => SqfliteDevOverlay(
///     enabled: kDebugMode,
///     child: child ?? const SizedBox.shrink(),
///   ),
///   home: MyHomePage(),
/// )
/// ```
class SqfliteDevOverlay extends StatelessWidget {
  const SqfliteDevOverlay({
    super.key,
    required this.child,
    this.enabled = true,
    this.alignment = SqfliteDevOverlayAlignment.right,
    this.verticalOffset = 120,
  });

  /// The app content to wrap.
  final Widget child;

  /// Whether the overlay is active. When false, [child] is rendered as-is.
  final bool enabled;

  /// Which screen edge the notch attaches to.
  final SqfliteDevOverlayAlignment alignment;

  /// Distance from the top safe-area inset to place the notch.
  final double verticalOffset;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        WorkbenchNotch(
          alignment: alignment,
          verticalOffset: verticalOffset,
        ),
      ],
    );
  }
}
