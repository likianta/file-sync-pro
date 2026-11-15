/// Perspective-rendered 3D device illustrations for the device card.
///
/// Each device is painted face-on in its own local space and tilted slightly
/// with a perspective matrix that keeps a slow auto-tilt loop — the same
/// treatment used by the reference circuit-board render. Every model uses
/// only canvas primitives (rounded rects, gradients, paths) so no image
/// assets are required.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/sync_client_config.dart';

class DeviceModel3D extends StatefulWidget {
  const DeviceModel3D({
    super.key,
    required this.model,
    this.autoAnimate = true,
  });

  final SyncDeviceModel model;
  final bool autoAnimate;

  @override
  State<DeviceModel3D> createState() => _DeviceModel3DState();
}

class _DeviceModel3DState extends State<DeviceModel3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    // Skip auto-repeat in widget tests so pumpAndSettle can complete.
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    if (widget.autoAnimate && !isTest) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) => CustomPaint(
        painter: _DevicePainter(model: widget.model, t: _clock.value),
      ),
    );
  }
}

class _DevicePainter extends CustomPainter {
  _DevicePainter({required this.model, required this.t});

  final SyncDeviceModel model;
  final double t;

  static const _palettes = <SyncDeviceModel, _ModelPalette>{
    SyncDeviceModel.macbook: _ModelPalette.mac,
    SyncDeviceModel.windowsLaptop: _ModelPalette.windows,
    SyncDeviceModel.windowsDesktop: _ModelPalette.windowsDesktop,
    SyncDeviceModel.linuxDesktop: _ModelPalette.linux,
    SyncDeviceModel.iphone: _ModelPalette.ios,
    SyncDeviceModel.ipad: _ModelPalette.ios,
    SyncDeviceModel.androidPhone: _ModelPalette.android,
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final palette = _palettes[model] ?? _ModelPalette.windows;
    _DeviceRender.render(
      canvas: canvas,
      size: size,
      model: model,
      palette: palette,
      t: t,
    );
  }

  @override
  bool shouldRepaint(covariant _DevicePainter oldDelegate) =>
      oldDelegate.model != model || oldDelegate.t != t;
}

class _ModelPalette {
  const _ModelPalette({
    required this.bodyTop,
    required this.bodyBottom,
    required this.edge,
    required this.screenTop,
    required this.screenBottom,
    required this.accent,
    required this.shadowTint,
  });

  final Color bodyTop;
  final Color bodyBottom;
  final Color edge;
  final Color screenTop;
  final Color screenBottom;
  final Color accent;
  final Color shadowTint;

  static const mac = _ModelPalette(
    bodyTop: Color(0xFF3A3D42),
    bodyBottom: Color(0xFF1A1C1F),
    edge: Color(0xFF5A6068),
    screenTop: Color(0xFF1B3A5C),
    screenBottom: Color(0xFF071526),
    accent: Color(0xFF7AA2F7),
    shadowTint: Color(0xFF000000),
  );

  static const windows = _ModelPalette(
    bodyTop: Color(0xFF2D4A66),
    bodyBottom: Color(0xFF102030),
    edge: Color(0xFF4A7A9E),
    screenTop: Color(0xFF123A5E),
    screenBottom: Color(0xFF061326),
    accent: Color(0xFF60A5FA),
    shadowTint: Color(0xFF000000),
  );

  static const windowsDesktop = _ModelPalette(
    bodyTop: Color(0xFF3A4550),
    bodyBottom: Color(0xFF14181D),
    edge: Color(0xFF5A7285),
    screenTop: Color(0xFF1A3652),
    screenBottom: Color(0xFF07151F),
    accent: Color(0xFF3B82F6),
    shadowTint: Color(0xFF000000),
  );

  static const linux = _ModelPalette(
    bodyTop: Color(0xFF3D2E4E),
    bodyBottom: Color(0xFF160E22),
    edge: Color(0xFF6B4E8A),
    screenTop: Color(0xFF1E2E1E),
    screenBottom: Color(0xFF081608),
    accent: Color(0xFF86EFAC),
    shadowTint: Color(0xFF000000),
  );

  static const ios = _ModelPalette(
    bodyTop: Color(0xFF2E333A),
    bodyBottom: Color(0xFF111418),
    edge: Color(0xFF4A525C),
    screenTop: Color(0xFF1B2A44),
    screenBottom: Color(0xFF060E1C),
    accent: Color(0xFF38BDF8),
    shadowTint: Color(0xFF000000),
  );

  static const android = _ModelPalette(
    bodyTop: Color(0xFF2D3A30),
    bodyBottom: Color(0xFF0F1A12),
    edge: Color(0xFF4A6A4C),
    screenTop: Color(0xFF122A1A),
    screenBottom: Color(0xFF06140A),
    accent: Color(0xFF4ADE80),
    shadowTint: Color(0xFF000000),
  );
}

/// Screen aspect ratios per model. Values are (width, height) in local
/// units — the painter scales everything into the available card size.
class _DeviceRender {
  static void render({
    required Canvas canvas,
    required Size size,
    required SyncDeviceModel model,
    required _ModelPalette palette,
    required double t,
  }) {
    // Scale everything so the model fits nicely, with room for the shadow.
    final baseSize = model._baseSize;
    final scaleX = size.width / (baseSize.width * 1.2);
    final scaleY = size.height / (baseSize.height * 1.4);
    final scale = math.min(scaleX, scaleY);

    final center = Offset(size.width / 2, size.height * 0.45);
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..setEntry(3, 2, 0.0012)
      ..rotateX(0.12 + math.sin(t * 2 * math.pi) * 0.025)
      ..rotateZ(math.sin(t * 2 * math.pi + 1.1) * 0.03);

    // Soft oval shadow on the floor.
    canvas.save();
    canvas.translate(center.dx, center.dy + baseSize.height * 0.55 * scale);
    canvas.scale(scale);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: baseSize.width * 1.1,
        height: 18,
      ),
      Paint()
        ..color = palette.shadowTint.withValues(alpha: 0.42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: baseSize.width * 1.4,
        height: 26,
      ),
      Paint()
        ..color = palette.shadowTint.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
    canvas.restore();

    canvas.save();
    canvas.transform(matrix.storage);
    switch (model) {
      case SyncDeviceModel.macbook:
        _paintLaptop(
          canvas,
          palette,
          clamshellRatio: 0.62,
          keyboardRatio: 0.72,
        );
      case SyncDeviceModel.windowsLaptop:
        _paintLaptop(
          canvas,
          palette,
          clamshellRatio: 0.58,
          keyboardRatio: 0.70,
        );
      case SyncDeviceModel.windowsDesktop:
        _paintDesktop(canvas, palette);
      case SyncDeviceModel.linuxDesktop:
        _paintDesktop(canvas, palette);
      case SyncDeviceModel.iphone:
        _paintPhone(canvas, palette, wide: false);
      case SyncDeviceModel.ipad:
        _paintTablet(canvas, palette);
      case SyncDeviceModel.androidPhone:
        _paintPhone(canvas, palette, wide: true);
    }
    canvas.restore();
  }

  /// Draws a laptop-style clamshell: the lid tilted back at [clamshellRatio]
  /// and the keyboard deck slightly wider at [keyboardRatio].
  static void _paintLaptop(
    Canvas canvas,
    _ModelPalette palette, {
    required double clamshellRatio,
    required double keyboardRatio,
  }) {
    // Keyboard deck (bottom) — drawn first so the lid sits on top.
    final deck = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 220, height: 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      deck.shift(const Offset(0, 6)),
      Paint()..color = palette.bodyBottom,
    );
    canvas.drawRRect(
      deck,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.bodyTop, palette.bodyBottom],
        ).createShader(deck.outerRect),
    );

    // Lid — tilted "up" by painting its face above center.
    final lidHeight = 130.0;
    final lidTop = -16 - lidHeight;
    final lid = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, lidTop + lidHeight / 2),
        width: 220 * clamshellRatio / keyboardRatio,
        height: lidHeight,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      lid.shift(const Offset(0, 5)),
      Paint()..color = palette.bodyBottom,
    );
    canvas.drawRRect(
      lid,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bodyTop, palette.bodyBottom],
        ).createShader(lid.outerRect),
    );
    canvas.drawRRect(
      lid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.edge.withValues(alpha: 0.7),
    );

    // Screen inset.
    final screenRect = Rect.fromCenter(
      center: Offset(0, lidTop + lidHeight / 2),
      width: 200,
      height: lidHeight - 14,
    );
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(4),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.screenTop, palette.screenBottom],
        ).createShader(screenRect),
    );
    // Gloss highlight streak.
    canvas.save();
    canvas.clipRRect(screen);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(-30, screenRect.top + (screenRect.height) * 0.35),
        width: 180,
        height: 12,
      ),
      Paint()
        ..shader =
            LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.22),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCenter(center: Offset.zero, width: 180, height: 12),
            ),
    );
    canvas.restore();

    // Keyboard hint — a grid of tiny rects.
    final keyPaint = Paint()..color = palette.edge.withValues(alpha: 0.45);
    const rows = 4;
    const cols = 12;
    const keyW = 12.0;
    const keyH = 5.0;
    const gap = 2.0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final dx = -((cols - 1) * (keyW + gap)) / 2 + c * (keyW + gap);
        final dy = -4 + r * (keyH + gap);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(dx, dy, keyW, keyH),
            const Radius.circular(1),
          ),
          keyPaint,
        );
      }
    }

    // Trackpad hint — a small rounded rect below keyboard.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, 10), width: 60, height: 10),
        const Radius.circular(2),
      ),
      Paint()..color = palette.edge.withValues(alpha: 0.35),
    );
  }

  /// Desktop monitor + tower combo.
  static void _paintDesktop(Canvas canvas, _ModelPalette palette) {
    // Tower (right side).
    final tower = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(80, 10), width: 44, height: 130),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      tower.shift(const Offset(0, 4)),
      Paint()..color = palette.bodyBottom,
    );
    canvas.drawRRect(
      tower,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.bodyTop, palette.bodyBottom],
        ).createShader(tower.outerRect),
    );
    // Tower vertical accent line.
    canvas.drawLine(
      const Offset(95, -50),
      const Offset(95, 70),
      Paint()
        ..color = palette.accent.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );

    // Monitor.
    final stand = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, 28), width: 70, height: 8),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      stand,
      Paint()..color = palette.edge.withValues(alpha: 0.8),
    );
    final neck = Rect.fromCenter(
      center: const Offset(0, 10),
      width: 8,
      height: 22,
    );
    canvas.drawRect(neck, Paint()..color = palette.edge);

    final monitorRect = Rect.fromCenter(
      center: const Offset(0, -40),
      width: 170,
      height: 110,
    );
    final monitor = RRect.fromRectAndRadius(
      monitorRect,
      const Radius.circular(4),
    );
    canvas.drawRRect(
      monitor.shift(const Offset(0, 4)),
      Paint()..color = palette.bodyBottom,
    );
    canvas.drawRRect(
      monitor,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bodyTop, palette.bodyBottom],
        ).createShader(monitorRect),
    );
    canvas.drawRRect(
      monitor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.edge.withValues(alpha: 0.7),
    );

    // Screen.
    final screenRect = Rect.fromCenter(
      center: const Offset(0, -40),
      width: 156,
      height: 96,
    );
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(2),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.screenTop, palette.screenBottom],
        ).createShader(screenRect),
    );
    canvas.save();
    canvas.clipRRect(screen);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(-20, screenRect.top + screenRect.height * 0.35),
        width: 130,
        height: 10,
      ),
      Paint()
        ..shader =
            LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.22),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCenter(center: Offset.zero, width: 130, height: 10),
            ),
    );
    canvas.restore();
  }

  static void _paintPhone(
    Canvas canvas,
    _ModelPalette palette, {
    required bool wide,
  }) {
    final aspect = wide ? 0.48 : 0.42;
    final bodyRect = Rect.fromCenter(
      center: Offset.zero,
      width: 110 * aspect / 0.45,
      height: 220,
    );
    final body = RRect.fromRectAndRadius(
      bodyRect,
      Radius.circular(bodyRect.width * 0.18),
    );

    canvas.drawRRect(
      body.shift(const Offset(0, 5)),
      Paint()..color = palette.bodyBottom,
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bodyTop, palette.bodyBottom],
        ).createShader(bodyRect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.edge.withValues(alpha: 0.6),
    );

    // Screen inset.
    final inset = 4.0;
    final screenRect = bodyRect.deflate(inset);
    final screen = RRect.fromRectAndRadius(
      screenRect,
      Radius.circular(screenRect.width * 0.14),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.screenTop, palette.screenBottom],
        ).createShader(screenRect),
    );

    // Notch / camera pill.
    final pillRect = Rect.fromCenter(
      center: Offset(0, screenRect.top + 10),
      width: wide ? 50 : 40,
      height: 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(5)),
      Paint()..color = palette.bodyBottom,
    );

    // Home indicator (thin bar at bottom).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, screenRect.bottom - 10),
          width: 40,
          height: 4,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = palette.edge.withValues(alpha: 0.5),
    );
  }

  static void _paintTablet(Canvas canvas, _ModelPalette palette) {
    final bodyRect = Rect.fromCenter(
      center: Offset.zero,
      width: 190,
      height: 250,
    );
    final body = RRect.fromRectAndRadius(bodyRect, const Radius.circular(18));

    canvas.drawRRect(
      body.shift(const Offset(0, 5)),
      Paint()..color = palette.bodyBottom,
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bodyTop, palette.bodyBottom],
        ).createShader(bodyRect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = palette.edge.withValues(alpha: 0.6),
    );

    final screenRect = bodyRect.deflate(8);
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(12),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.screenTop, palette.screenBottom],
        ).createShader(screenRect),
    );

    // Camera.
    canvas.drawCircle(
      Offset(0, bodyRect.top + 8),
      3,
      Paint()..color = palette.edge.withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      Offset(0, bodyRect.top + 8),
      1.5,
      Paint()..color = palette.bodyBottom,
    );
  }
}

extension _DeviceModelGeometry on SyncDeviceModel {
  /// Approximate (width, height) in the local coordinate space each model
  /// paints in. Used to size and center the illustration.
  Size get _baseSize => switch (this) {
    SyncDeviceModel.macbook => const Size(220, 160),
    SyncDeviceModel.windowsLaptop => const Size(220, 160),
    SyncDeviceModel.windowsDesktop => const Size(220, 160),
    SyncDeviceModel.linuxDesktop => const Size(220, 160),
    SyncDeviceModel.iphone => const Size(95, 240),
    SyncDeviceModel.ipad => const Size(190, 250),
    SyncDeviceModel.androidPhone => const Size(105, 240),
  };
}
