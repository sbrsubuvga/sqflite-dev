import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_dev/sqflite_dev.dart';

/// Screen edge the workbench notch attaches to.
enum SqfliteDevOverlayAlignment { left, right }

/// Programmatically insert the workbench notch into the running app's
/// [Overlay]. Pass this to [registerOverlayHandler] or
/// [WorkbenchServer.instance.overlayHandler].
void insertWorkbenchOverlay() {
  if (_entry != null) return;
  _retryCount = 0;
  WidgetsBinding.instance.addPostFrameCallback((_) => _tryInsert());
}

/// Remove the notch overlay.
void removeWorkbenchOverlay() {
  _entry?.remove();
  _entry?.dispose();
  _entry = null;
}

OverlayEntry? _entry;
int _retryCount = 0;

void _tryInsert() {
  final rootElement = WidgetsBinding.instance.rootElement;
  if (rootElement == null) {
    _scheduleRetry();
    return;
  }

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

  _entry = OverlayEntry(builder: (_) => const WorkbenchNotch());
  overlayState!.insert(_entry!);
}

void _scheduleRetry() {
  if (++_retryCount > 30) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => _tryInsert());
}

// ─────────────────────────────────────────────────────────────────────────────
// Notch + Panel widget
// ─────────────────────────────────────────────────────────────────────────────

class WorkbenchNotch extends StatefulWidget {
  const WorkbenchNotch({
    super.key,
    this.alignment = SqfliteDevOverlayAlignment.right,
    this.verticalOffset = 120,
  });

  final SqfliteDevOverlayAlignment alignment;
  final double verticalOffset;

  @override
  State<WorkbenchNotch> createState() => _WorkbenchNotchState();
}

class _WorkbenchNotchState extends State<WorkbenchNotch>
    with SingleTickerProviderStateMixin {
  static const double _panelWidth = 260;

  late final AnimationController _ctrl;
  Timer? _refreshTimer;
  String? _copiedUrl;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _copiedTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_ctrl.value > 0.5) {
      _ctrl.reverse();
    } else {
      _ctrl.forward();
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copiedUrl = url);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copiedUrl = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = WorkbenchServer.instance;
    if (!server.isRunning) return const SizedBox.shrink();

    final port = server.port;
    final localIp = server.localIp;
    final dbCount = server.databases.length;
    final isRight = widget.alignment == SqfliteDevOverlayAlignment.right;
    final topPadding = MediaQuery.maybeOf(context)?.padding.top ?? 0;

    return Positioned(
      right: isRight ? 0 : null,
      left: isRight ? null : 0,
      top: topPadding + widget.verticalOffset,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final hidden = (1 - _ctrl.value) * _panelWidth;
          final offset = isRight ? hidden : -hidden;
          return Transform.translate(
            offset: Offset(offset, 0),
            child: Material(
              color: Colors.transparent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: isRight
                    ? [
                        _buildHandle(isRight: true),
                        _buildPanel(port, localIp, dbCount, isRight: true),
                      ]
                    : [
                        _buildPanel(port, localIp, dbCount, isRight: false),
                        _buildHandle(isRight: false),
                      ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHandle({required bool isRight}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      onHorizontalDragUpdate: (d) {
        final delta = isRight ? -d.delta.dx : d.delta.dx;
        _ctrl.value = (_ctrl.value + delta / _panelWidth).clamp(0.0, 1.0);
      },
      onHorizontalDragEnd: (_) {
        if (_ctrl.value > 0.5) {
          _ctrl.forward();
        } else {
          _ctrl.reverse();
        }
      },
      child: Container(
        width: 16,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1),
          borderRadius: isRight
              ? const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                )
              : const BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: Offset(isRight ? -2 : 2, 2),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 3,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(int port, String? localIp, int dbCount,
      {required bool isRight}) {
    return Container(
      width: _panelWidth,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: isRight
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(6),
                topLeft: Radius.circular(6),
              )
            : const BorderRadius.only(
                bottomRight: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: Offset(isRight ? -4 : 4, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'sqflite_dev',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Text(
                'workbench',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _urlRow('LOCAL', 'http://localhost:$port'),
          const SizedBox(height: 10),
          if (localIp != null)
            _urlRow('NETWORK', 'http://$localIp:$port')
          else
            Text(
              'Network: not detected',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.storage_outlined,
                color: Colors.white.withValues(alpha: 0.4),
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                '$dbCount database${dbCount == 1 ? '' : 's'} registered',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _urlRow(String label, String url) {
    final isCopied = _copiedUrl == url;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            if (isCopied)
              const Text(
                'copied',
                style: TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        InkWell(
          onTap: () => _copy(url),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    url,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                      height: 1.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  isCopied ? Icons.check : Icons.copy,
                  size: 13,
                  color: Colors.white.withValues(alpha: isCopied ? 0.8 : 0.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
