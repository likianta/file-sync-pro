/// Static slightly-tilted device illustrations for the device card.
///
/// Every model is rendered face-on with a tiny perspective tilt (≈5°) —
/// pure Canvas primitives (rounded rects, gradients, paths) so no image
/// assets are required. The model painter extends slightly below its
/// bounds so its soft shadow can overlap the card content beneath it,
/// creating a "pressing into the tags" visual depth.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/sync_client_config.dart';

class DeviceModel3D extends StatelessWidget {
  const DeviceModel3D({super.key, required this.model});

  final SyncDeviceModel model;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DevicePainter(model: model));
  }
}

class _DevicePainter extends CustomPainter {
  _DevicePainter({required this.model});

  final SyncDeviceModel model;

  static const _palettes = <SyncDeviceModel, _ModelPalette>{
    SyncDeviceModel.macbook: _ModelPalette.mac,
    SyncDeviceModel.windowsLaptop: _ModelPalette.windows,
    SyncDeviceModel.windowsDesktop: _ModelPalette.windowsDesktop,
    SyncDeviceModel.linuxDesktop: _ModelPalette.linux,
    SyncDeviceModel.iphone: _ModelPalette.iphone,
    SyncDeviceModel.ipad: _ModelPalette.ipad,
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
    );
  }

  @override
  bool shouldRepaint(covariant _DevicePainter oldDelegate) =>
      oldDelegate.model != model;
}

class _ModelPalette {
  const _ModelPalette({
    required this.bodyLight,
    required this.bodyDark,
    required this.bezel,
    required this.screenBgTop,
    required this.screenBgBottom,
    required this.screenAccent,
    required this.textHint,
    required this.shadow,
    required this.shadowEdge,
    this.emblem,
  });

  final Color bodyLight;
  final Color bodyDark;
  final Color bezel;
  final Color screenBgTop;
  final Color screenBgBottom;
  final Color screenAccent;
  final Color textHint;
  final Color shadow;
  final Color shadowEdge;
  final Color? emblem;

  static const mac = _ModelPalette(
    bodyLight: Color(0xFFBFC4CA),
    bodyDark: Color(0xFF6B7280),
    bezel: Color(0xFF111214),
    screenBgTop: Color(0xFF2E4A6B),
    screenBgBottom: Color(0xFF1A2332),
    screenAccent: Color(0xFF7AA2F7),
    textHint: Color(0xFF9CA3AF),
    shadow: Color(0xFF000000),
    shadowEdge: Color(0xFF000000),
    emblem: Color(0xFFF3F4F6),
  );

  static const windows = _ModelPalette(
    bodyLight: Color(0xFFD1D5DB),
    bodyDark: Color(0xFF4B5563),
    bezel: Color(0xFF1F2937),
    screenBgTop: Color(0xFF2563EB),
    screenBgBottom: Color(0xFF0F172A),
    screenAccent: Color(0xFF60A5FA),
    textHint: Color(0xFF94A3B8),
    shadow: Color(0xFF000000),
    shadowEdge: Color(0xFF000000),
    emblem: Color(0xFFFACC15),
  );

  static const windowsDesktop = _ModelPalette(
    bodyLight: Color(0xFFC0C7CF),
    bodyDark: Color(0xFF374151),
    bezel: Color(0xFF111827),
    screenBgTop: Color(0xFF1D4ED8),
    screenBgBottom: Color(0xFF0B1120),
    screenAccent: Color(0xFF60A5FA),
    textHint: Color(0xFF94A3B8),
    shadow: Color(0xFF000000),
    shadowEdge: Color(0xFF000000),
    emblem: Color(0xFFFACC15),
  );

  static const linux = _ModelPalette(
    bodyLight: Color(0xFFC4B5D6),
    bodyDark: Color(0xFF4A3860),
    bezel: Color(0xFF1E1330),
    screenBgTop: Color(0xFF14532D),
    screenBgBottom: Color(0xFF07160B),
    screenAccent: Color(0xFF86EFAC),
    textHint: Color(0xFFA78BFA),
    shadow: Color(0xFF000000),
    shadowEdge: Color(0xFF000000),
    emblem: Color(0xFFFBBF24),
  );

  static const iphone = _ModelPalette(
    bodyLight: Color(0xFFE5E7EB),
    bodyDark: Color(0xFF374151),
    bezel: Color(0xFF0A0A0C),
    screenBgTop: Color(0xFF3B1D5C),
    screenBgBottom: Color(0xFF1A0F2E),
    screenAccent: Color(0xFFA78BFA),
    textHint: Color(0xFFD1D5DB),
    shadow: Color(0xFF000000),
    shadowEdge: Color(0xFF000000),
  );

  static const ipad = _ModelPalette(
    bodyLight: Color(0xFFD1D5DB),
    bodyDark: Color(0xFF374151),
    bezel: Color(0xFF0A0A0C),
    screenBgTop: Color(0xFF1E3A5F),
    screenBgBottom: Color(0xFF0E1828),
    screenAccent: Color(0xFF60A5FA),
    textHint: Color(0xFFCBD5E1),
    shadow: Color(0xFF000000),
    shadowEdge: Color(0xFF000000),
  );

  static const android = _ModelPalette(
    bodyLight: Color(0xFFD4D4D8),
    bodyDark: Color(0xFF3F3F46),
    bezel: Color(0xFF0F0F14),
    screenBgTop: Color(0xFF166534),
    screenBgBottom: Color(0xFF052E16),
    screenAccent: Color(0xFF4ADE80),
    textHint: Color(0xFFA3A3A3),
    shadow: Color(0xFF000000),
    shadowEdge: Color(0xFF000000),
  );
}

class _DeviceRender {
  /// Tilt angle in radians — deliberately small so devices read as front-facing.
  static const _tiltX = 0.05; // ~3° slight top-back
  static const _tiltZ = -0.04; // ~2° slight left-rotation

  static void render({
    required Canvas canvas,
    required Size size,
    required SyncDeviceModel model,
    required _ModelPalette palette,
  }) {
    final baseSize = model._baseSize;
    final scaleX = size.width / (baseSize.width * 1.22);
    // The height available for the painting; we use only the top 75% for the
    // actual device body so the bottom 25% is free for a trailing soft shadow.
    final scaleY = (size.height * 0.70) / baseSize.height;
    final scale = math.min(scaleX, scaleY);

    // Center horizontally; place the device body so its bottom lands around
    // size.height * 0.70, leaving space below for the shadow trail that
    // will overlap whatever content sits in the card beneath us.
    final bottomY = size.height * 0.72;
    final center = Offset(
      size.width / 2,
      bottomY - baseSize.height * scale / 2,
    );
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..setEntry(3, 2, 0.0008)
      ..rotateX(_tiltX)
      ..rotateZ(_tiltZ);

    // --- TRAILING SHADOW (painted before device so device sits on top) ---
    canvas.save();
    // Translate to the floor plane of the device (bottom of the model).
    final floorY = baseSize.height * scale / 2 + 4;
    canvas.translate(center.dx, center.dy + floorY);
    canvas.scale(scale);
    _paintShadowPile(canvas, palette, baseSize);
    canvas.restore();

    // --- DEVICE ---
    canvas.save();
    canvas.transform(matrix.storage);
    switch (model) {
      case SyncDeviceModel.macbook:
        _paintMacBook(canvas, palette);
      case SyncDeviceModel.windowsLaptop:
        _paintWindowsLaptop(canvas, palette);
      case SyncDeviceModel.windowsDesktop:
        _paintWindowsDesktop(canvas, palette);
      case SyncDeviceModel.linuxDesktop:
        _paintLinuxDesktop(canvas, palette);
      case SyncDeviceModel.iphone:
        _paintIPhone(canvas, palette);
      case SyncDeviceModel.ipad:
        _paintIPad(canvas, palette);
      case SyncDeviceModel.androidPhone:
        _paintAndroidPhone(canvas, palette);
    }
    canvas.restore();
  }

  /// A three-layer shadow that stretches downward beneath the device into
  /// whatever content the card lays out below. The blur is intentionally large
  /// so the edge is indistinct.
  static void _paintShadowPile(
    Canvas canvas,
    _ModelPalette palette,
    Size base,
  ) {
    // Layer 1: a very wide, very faint ambient shadow — barely visible, gives
    // the "standing on a surface" cue.
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(0, 2),
        width: base.width * 1.6,
        height: base.height * 0.08,
      ),
      Paint()
        ..color = palette.shadow.withValues(alpha: 0.11)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 48),
    );
    // Layer 2: contact shadow under the device's footprint.
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(0, 1),
        width: base.width * 1.08,
        height: 12,
      ),
      Paint()
        ..color = palette.shadow.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );
    // Layer 3: medium shadow trail for overlap effect — extends BELOW the
    // device floor so it will paint into card content.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, base.height * 0.14),
        width: base.width * 0.80,
        height: 34,
      ),
      Paint()
        ..color = palette.shadow.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
    );
  }

  // --- LAPTOPS ------------------------------------------------------------

  static void _paintLaptopBase(
    Canvas canvas,
    _ModelPalette palette, {
    required double clamshellWidthRatio, // lid width / deck width
    required bool showWindowsKey,
  }) {
    const deckW = 208.0;
    const deckH = 14.0;
    const lidH = 122.0;
    final lidW = deckW * clamshellWidthRatio;

    // Keyboard deck.
    final deck = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: deckW, height: deckH),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      deck.shift(const Offset(0, 5)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.6),
    );
    canvas.drawRRect(
      deck,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.bodyLight, palette.bodyDark],
        ).createShader(deck.outerRect),
    );

    // Lid.
    final lidTop = -deckH / 2 - lidH;
    final lidCenter = Offset(0, lidTop + lidH / 2);
    final lid = RRect.fromRectAndRadius(
      Rect.fromCenter(center: lidCenter, width: lidW, height: lidH),
      const Radius.circular(5),
    );
    // Lid drop shadow (small, close to the body).
    canvas.drawRRect(
      lid.shift(const Offset(0, 4)),
      Paint()..color = palette.bezel.withValues(alpha: 0.5),
    );
    canvas.drawRRect(
      lid,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bodyLight, palette.bodyDark],
        ).createShader(lid.outerRect),
    );
    // Lid rim highlight.
    canvas.drawRRect(
      lid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.15),
    );

    // Webcam pinhole at top-center of lid bezel.
    canvas.drawCircle(
      Offset(0, lidCenter.dy - lidH / 2 + 4),
      1.5,
      Paint()..color = palette.bezel,
    );
    canvas.drawCircle(
      Offset(0, lidCenter.dy - lidH / 2 + 4),
      0.6,
      Paint()..color = palette.screenAccent,
    );

    // Screen.
    final screenInset = 6.0;
    final screenRect = Rect.fromCenter(
      center: lidCenter,
      width: lidW - screenInset * 2,
      height: lidH - screenInset * 2 - 6,
    );
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(3),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.screenBgTop, palette.screenBgBottom],
        ).createShader(screenRect),
    );
    _paintScreenChrome(canvas, palette, screen);

    // Keyboard deck details — F-row, alphanumeric grid, trackpad.
    _paintKeyboard(canvas, palette, deckW);
    _paintTrackpad(canvas, palette, deckW);

    // Brand emblem on lid (centered, subtle, above screen top).
    _paintLidEmblem(canvas, palette, lidCenter, lidH, showWindowsKey);
  }

  static void _paintKeyboard(
    Canvas canvas,
    _ModelPalette palette,
    double deckW,
  ) {
    const rows = 4;
    const cols = 14;
    const keyW = 10.0;
    const keyH = 4.0;
    const gap = 1.6;
    final keyPaint = Paint()..color = palette.bezel.withValues(alpha: 0.28);
    final keyTopPaint = Paint()
      ..color = palette.bodyLight.withValues(alpha: 0.5);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final dx = -((cols - 1) * (keyW + gap)) / 2 + c * (keyW + gap);
        final dy = -6 + r * (keyH + gap);
        final keyRect = Rect.fromLTWH(dx, dy, keyW, keyH);
        canvas.drawRRect(
          RRect.fromRectAndRadius(keyRect, const Radius.circular(0.8)),
          keyPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(dx + 0.3, dy + 0.3, keyW - 0.6, 1.2),
            const Radius.circular(0.5),
          ),
          keyTopPaint,
        );
      }
    }
    // Spacebar — one wide key at bottom row, centered.
    final spacebar = Rect.fromCenter(
      center: const Offset(0, -6 + 4 * (keyH + gap)),
      width: 60,
      height: keyH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(spacebar, const Radius.circular(0.8)),
      keyPaint,
    );
  }

  static void _paintTrackpad(
    Canvas canvas,
    _ModelPalette palette,
    double deckW,
  ) {
    final trackpad = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: const Offset(0, 9),
        width: deckW * 0.36,
        height: 9,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      trackpad,
      Paint()
        ..color = palette.bodyDark.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );
    // Subtle top highlight.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(0, 6.8),
          width: deckW * 0.36 - 2,
          height: 1.5,
        ),
        const Radius.circular(1),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );
  }

  static void _paintScreenChrome(
    Canvas canvas,
    _ModelPalette palette,
    RRect screen,
  ) {
    canvas.save();
    canvas.clipRRect(screen);
    // Top status bar line.
    final screenRect = screen.outerRect;
    canvas.drawRect(
      Rect.fromLTWH(screenRect.left + 4, screenRect.top + 2, 40, 1),
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
    // A thin content row.
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          screenRect.left + 6,
          screenRect.top + 10 + i * 6,
          screenRect.width * 0.20 + (i * 6),
          2,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.18),
      );
    }
    // Gloss highlight streak.
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(
          screenRect.left + screenRect.width * 0.3,
          screenRect.top + screenRect.height * 0.3,
        ),
        width: screenRect.width * 0.6,
        height: 6,
      ),
      Paint()
        ..shader =
            LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.25),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTWH(
                screenRect.left,
                screenRect.top,
                screenRect.width,
                10,
              ),
            ),
    );
    canvas.restore();
  }

  static void _paintLidEmblem(
    Canvas canvas,
    _ModelPalette palette,
    Offset lidCenter,
    double lidH,
    bool showWindowsFlag,
  ) {
    if (palette.emblem == null) return;
    final paint = Paint()..color = palette.emblem!.withValues(alpha: 0.85);
    final center = Offset(lidCenter.dx, lidCenter.dy - lidH * 0.02);
    if (showWindowsFlag) {
      // Windows 4-square flag.
      const size = 8.0;
      for (var i = 0; i < 2; i++) {
        for (var j = 0; j < 2; j++) {
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(
                center.dx - size / 2 + i * size,
                center.dy - size / 2 + j * size,
              ),
              width: size * 0.85,
              height: size * 0.85,
            ),
            paint,
          );
        }
      }
    } else {
      // Apple-like leaf (simple path: teardrop shape with a stem).
      final leaf = Path()
        ..moveTo(center.dx, center.dy - 6)
        ..cubicTo(
          center.dx + 3,
          center.dy - 5,
          center.dx + 4,
          center.dy + 1,
          center.dx + 1,
          center.dy + 5,
        )
        ..cubicTo(
          center.dx - 1,
          center.dy + 6,
          center.dx - 4,
          center.dy + 2,
          center.dx - 3,
          center.dy - 3,
        )
        ..close();
      canvas.drawPath(leaf, paint);
      // Bite notch.
      canvas.drawCircle(
        Offset(center.dx + 3.5, center.dy - 2.5),
        1.8,
        Paint()..color = palette.bodyLight,
      );
    }
  }

  static void _paintMacBook(Canvas canvas, _ModelPalette palette) {
    _paintLaptopBase(
      canvas,
      palette,
      clamshellWidthRatio: 0.94,
      showWindowsKey: false,
    );
  }

  static void _paintWindowsLaptop(Canvas canvas, _ModelPalette palette) {
    _paintLaptopBase(
      canvas,
      palette,
      clamshellWidthRatio: 0.90,
      showWindowsKey: true,
    );
  }

  // --- DESKTOPS -----------------------------------------------------------

  static void _paintWindowsDesktop(Canvas canvas, _ModelPalette palette) {
    _paintDesktopBase(canvas, palette, towerOnRight: true);
  }

  static void _paintLinuxDesktop(Canvas canvas, _ModelPalette palette) {
    _paintDesktopBase(canvas, palette, towerOnRight: false);
  }

  static void _paintDesktopBase(
    Canvas canvas,
    _ModelPalette palette, {
    required bool towerOnRight,
  }) {
    // --- Tower ---
    final towerOffsetX = towerOnRight ? 74.0 : -74.0;
    final tower = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(towerOffsetX, -10),
        width: 40,
        height: 118,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      tower.shift(const Offset(0, 3)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.7),
    );
    canvas.drawRRect(
      tower,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.bodyLight, palette.bodyDark],
        ).createShader(tower.outerRect),
    );
    // Tower vertical accent strip (power LED).
    canvas.drawLine(
      Offset(towerOffsetX + 16, tower.outerRect.top + 8),
      Offset(towerOffsetX + 16, tower.outerRect.bottom - 8),
      Paint()
        ..color = palette.screenAccent.withValues(alpha: 0.75)
        ..strokeWidth = 1.2,
    );
    // Power LED dot.
    canvas.drawCircle(
      Offset(towerOffsetX + 16, tower.outerRect.top + 6),
      1.2,
      Paint()..color = palette.screenAccent,
    );

    // --- Monitor ---
    final stand = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, 22), width: 64, height: 7),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      stand,
      Paint()
        ..shader = LinearGradient(colors: [palette.bodyLight, palette.bodyDark])
            .createShader(stand.outerRect),
    );
    final neckRect = Rect.fromCenter(
      center: const Offset(0, 6),
      width: 8,
      height: 20,
    );
    canvas.drawRect(neckRect, Paint()..color = palette.bodyDark);
    canvas.drawLine(
      Offset(neckRect.left, neckRect.top + 4),
      Offset(neckRect.right, neckRect.top + 4),
      Paint()
        ..color = palette.bodyLight.withValues(alpha: 0.4)
        ..strokeWidth = 0.5,
    );

    const monitorH = 104.0;
    const monitorW = 162.0;
    final monitorCenter = const Offset(0, -46);
    final monitor = RRect.fromRectAndRadius(
      Rect.fromCenter(center: monitorCenter, width: monitorW, height: monitorH),
      const Radius.circular(5),
    );
    // Monitor drop shadow.
    canvas.drawRRect(
      monitor.shift(const Offset(0, 3)),
      Paint()..color = palette.bezel.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      monitor,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bodyLight, palette.bodyDark],
        ).createShader(monitor.outerRect),
    );
    canvas.drawRRect(
      monitor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    // Screen.
    final screenRect = Rect.fromCenter(
      center: monitorCenter,
      width: monitorW - 14,
      height: monitorH - 14,
    );
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(2),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.screenBgTop, palette.screenBgBottom],
        ).createShader(screenRect),
    );
    _paintScreenChrome(canvas, palette, screen);

    // Monitor brand emblem (bottom bezel center).
    final emblem = palette.emblem;
    if (emblem != null) {
      canvas.drawCircle(
        Offset(monitorCenter.dx, monitorCenter.dy + monitorH / 2 - 5),
        1.4,
        Paint()..color = emblem.withValues(alpha: 0.8),
      );
    }

    // Cable hint running from tower to monitor back.
    canvas.drawPath(
      Path()
        ..moveTo(
          towerOffsetX + (towerOnRight ? -20 : 20),
          tower.outerRect.top + 12,
        )
        ..quadraticBezierTo(
          towerOffsetX + (towerOnRight ? 30 : -30),
          -40,
          monitorCenter.dx + (towerOnRight ? -monitorW / 2 : monitorW / 2),
          monitorCenter.dy,
        ),
      Paint()
        ..color = palette.bezel.withValues(alpha: 0.6)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
  }

  // --- PHONES -------------------------------------------------------------

  static void _paintIPhone(Canvas canvas, _ModelPalette palette) {
    const bodyW = 72.0;
    const bodyH = 180.0;
    final bodyRect = Rect.fromCenter(
      center: Offset.zero,
      width: bodyW,
      height: bodyH,
    );
    final radius = Radius.circular(bodyW * 0.22);
    final body = RRect.fromRectAndRadius(bodyRect, radius);

    // Body drop shadow underpaint.
    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      Paint()..color = palette.bezel.withValues(alpha: 0.55),
    );
    // Titanium frame gradient.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.bodyLight, palette.bodyDark],
        ).createShader(bodyRect),
    );
    // Frame highlight (top rim).
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    // Side buttons — iPhone has 3 buttons on left, 1 on right.
    final buttonPaint = Paint()
      ..color = palette.bodyDark.withValues(alpha: 0.6);
    // Left side: Action (top), Vol+, Vol-
    final leftX = bodyRect.left - 1.5;
    for (final (y, h) in [
      (-58.0, 9.0), // Action button
      (-40.0, 11.0), // Vol+
      (-22.0, 11.0), // Vol-
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(leftX, y), width: 2, height: h),
          const Radius.circular(1),
        ),
        buttonPaint,
      );
    }
    // Right side: Side button (Power)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bodyRect.right + 1.5, -40),
          width: 2,
          height: 16,
        ),
        const Radius.circular(1),
      ),
      buttonPaint,
    );

    // Screen.
    final screenInset = 2.2;
    final screenRect = bodyRect.deflate(screenInset);
    final screenRadius = Radius.circular(screenRect.width * 0.20);
    final screen = RRect.fromRectAndRadius(screenRect, screenRadius);
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.screenBgTop, palette.screenBgBottom],
        ).createShader(screenRect),
    );

    // Dynamic Island (wider than old notch).
    final islandRect = Rect.fromCenter(
      center: Offset(0, screenRect.top + 11),
      width: 46,
      height: 12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(islandRect, const Radius.circular(6)),
      Paint()..color = palette.bezel,
    );
    // Camera lens inside island.
    canvas.drawCircle(
      Offset(islandRect.center.dx + 9, islandRect.center.dy),
      2.2,
      Paint()..color = const Color(0xFF0F172A),
    );
    canvas.drawCircle(
      Offset(islandRect.center.dx + 9, islandRect.center.dy),
      1.2,
      Paint()..color = palette.screenAccent.withValues(alpha: 0.5),
    );
    // Flash/IR dot.
    canvas.drawCircle(
      Offset(islandRect.center.dx + 14, islandRect.center.dy),
      0.8,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );

    // Status bar (top of screen).
    _paintStatusBar(canvas, palette, screenRect, showTimeOnLeft: false);

    // Wallpaper detail — subtle icon grid above dock.
    _paintIPhoneAppGrid(canvas, palette, screenRect);

    // Home indicator bar.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, screenRect.bottom - 6),
          width: 34,
          height: 3,
        ),
        const Radius.circular(1.5),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );

    // Bottom edge detail: speaker grille + USB-C.
    _paintBottomEdge(canvas, palette, bodyRect, bodyW);
  }

  static void _paintAndroidPhone(Canvas canvas, _ModelPalette palette) {
    const bodyW = 78.0;
    const bodyH = 178.0;
    final bodyRect = Rect.fromCenter(
      center: Offset.zero,
      width: bodyW,
      height: bodyH,
    );
    final radius = Radius.circular(bodyW * 0.22);
    final body = RRect.fromRectAndRadius(bodyRect, radius);

    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      Paint()..color = palette.bezel.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bodyLight, palette.bodyDark],
        ).createShader(bodyRect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.white.withValues(alpha: 0.25),
    );

    // Side buttons (right side only on Android).
    final buttonPaint = Paint()
      ..color = palette.bodyDark.withValues(alpha: 0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bodyRect.right + 1.5, -42),
          width: 2,
          height: 12,
        ),
        const Radius.circular(1),
      ),
      buttonPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bodyRect.right + 1.5, -26),
          width: 2,
          height: 16,
        ),
        const Radius.circular(1),
      ),
      buttonPaint,
    );

    // Screen.
    final screenInset = 2.0;
    final screenRect = bodyRect.deflate(screenInset);
    final screen = RRect.fromRectAndRadius(
      screenRect,
      Radius.circular(screenRect.width * 0.20),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.screenBgTop, palette.screenBgBottom],
        ).createShader(screenRect),
    );

    // Punch-hole camera (centered at top of screen).
    final punchCenter = Offset(screenRect.center.dx, screenRect.top + 10);
    canvas.drawCircle(punchCenter, 3.8, Paint()..color = palette.bezel);
    canvas.drawCircle(
      punchCenter,
      2.6,
      Paint()..color = const Color(0xFF0F172A),
    );
    canvas.drawCircle(
      punchCenter + const Offset(0.8, -0.8),
      0.8,
      Paint()..color = palette.screenAccent.withValues(alpha: 0.6),
    );

    // Status bar.
    _paintStatusBar(canvas, palette, screenRect, showTimeOnLeft: true);

    // Material You wallpaper pattern (organic blobs).
    _paintAndroidWallpaper(canvas, palette, screenRect);

    // Navigation bar (gesture).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, screenRect.bottom - 6),
          width: 30,
          height: 2.5,
        ),
        const Radius.circular(1.25),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );

    _paintBottomEdge(canvas, palette, bodyRect, bodyW);
  }

  static void _paintStatusBar(
    Canvas canvas,
    _ModelPalette palette,
    Rect screenRect, {
    required bool showTimeOnLeft,
  }) {
    final timeDotPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final (timeCx, timeCy) = showTimeOnLeft
        ? (screenRect.left + 10.0, screenRect.top + 4.5)
        : (screenRect.right - 16.0, screenRect.top + 4.5);
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        Offset(timeCx - 4 + i * 2.7, timeCy),
        0.9,
        timeDotPaint,
      );
    }

    // Signal bars.
    final sigRight = showTimeOnLeft
        ? screenRect.right - 4
        : screenRect.right - 26;
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          sigRight + i * 1.8,
          screenRect.top + 3.5 - i * 0.8,
          1.1,
          2 + i * 0.8,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
    // Battery outline.
    final batRight = showTimeOnLeft
        ? screenRect.right - 4
        : screenRect.right - 6;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(batRight - 7, screenRect.top + 3.5, 6, 2.6),
        const Radius.circular(0.8),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.drawRect(
      Rect.fromLTWH(batRight - 6.5, screenRect.top + 4, 3.5, 1.6),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  static void _paintIPhoneAppGrid(
    Canvas canvas,
    _ModelPalette palette,
    Rect screenRect,
  ) {
    canvas.save();
    canvas.clipRect(screenRect);
    final top = screenRect.top + 20;
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 4; col++) {
        final cx = screenRect.left + 10 + col * 13;
        final cy = top + row * 13;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy), width: 8, height: 8),
            const Radius.circular(2),
          ),
          Paint()
            ..color = palette.screenAccent.withValues(alpha: 0.40 + row * 0.10),
        );
      }
    }
    canvas.restore();
  }

  static void _paintAndroidWallpaper(
    Canvas canvas,
    _ModelPalette palette,
    Rect screenRect,
  ) {
    canvas.save();
    canvas.clipRect(screenRect);
    // Organic blobs.
    final blobs = <(Offset center, double radius, Color color)>[
      (
        Offset(screenRect.center.dx - 14, screenRect.top + 30),
        32,
        palette.screenAccent.withValues(alpha: 0.35),
      ),
      (
        Offset(screenRect.center.dx + 18, screenRect.top + 50),
        26,
        palette.screenBgTop.withValues(alpha: 0.5),
      ),
      (
        Offset(screenRect.center.dx - 4, screenRect.bottom - 30),
        34,
        palette.screenAccent.withValues(alpha: 0.28),
      ),
    ];
    for (final (center, radius, color) in blobs) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.restore();
  }

  static void _paintBottomEdge(
    Canvas canvas,
    _ModelPalette palette,
    Rect bodyRect,
    double bodyW,
  ) {
    // Speaker grille — 6 tiny circles on one side.
    final speakerCx = bodyRect.center.dx - 12;
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(
        Offset(speakerCx + i * 2.2, bodyRect.bottom - 2.2),
        0.6,
        Paint()..color = palette.bezel.withValues(alpha: 0.7),
      );
    }
    // USB-C port (oval slot).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, bodyRect.bottom - 2.2),
          width: 9,
          height: 1.8,
        ),
        const Radius.circular(0.9),
      ),
      Paint()..color = palette.bezel,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, bodyRect.bottom - 2.2),
          width: 6.5,
          height: 0.9,
        ),
        const Radius.circular(0.45),
      ),
      Paint()..color = palette.bodyLight.withValues(alpha: 0.3),
    );
    // SIM tray pinhole on the long edge.
    canvas.drawCircle(
      Offset(bodyRect.left + 1, bodyRect.top + bodyW * 0.2),
      0.5,
      Paint()..color = palette.bezel.withValues(alpha: 0.6),
    );
  }

  // --- TABLET -------------------------------------------------------------

  static void _paintIPad(Canvas canvas, _ModelPalette palette) {
    const bodyW = 150.0;
    const bodyH = 196.0;
    final bodyRect = Rect.fromCenter(
      center: Offset.zero,
      width: bodyW,
      height: bodyH,
    );
    final body = RRect.fromRectAndRadius(bodyRect, const Radius.circular(12));

    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      Paint()..color = palette.bezel.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bodyLight, palette.bodyDark],
        ).createShader(bodyRect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.3),
    );

    // Screen (bezel is relatively thick on iPad).
    final screenInset = 7.0;
    final screenRect = bodyRect.deflate(screenInset);
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(6),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.screenBgTop, palette.screenBgBottom],
        ).createShader(screenRect),
    );

    // Top camera module (two lenses + flash on a square plate).
    final camPlateCenter = Offset(bodyRect.left + 7, bodyRect.top + 7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: camPlateCenter, width: 11, height: 11),
        const Radius.circular(3),
      ),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.5),
    );
    // Lens 1.
    canvas.drawCircle(
      camPlateCenter + const Offset(-2.5, -2),
      1.8,
      Paint()..color = const Color(0xFF0F172A),
    );
    canvas.drawCircle(
      camPlateCenter + const Offset(-2.5, -2),
      0.9,
      Paint()..color = palette.screenAccent.withValues(alpha: 0.6),
    );
    // Lens 2.
    canvas.drawCircle(
      camPlateCenter + const Offset(2.5, 2),
      1.8,
      Paint()..color = const Color(0xFF0F172A),
    );
    // Flash.
    canvas.drawCircle(
      camPlateCenter + const Offset(2.5, -2.5),
      0.8,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );

    // Status bar.
    _paintStatusBar(canvas, palette, screenRect, showTimeOnLeft: false);

    // Dock at bottom of screen.
    final dockRect = Rect.fromCenter(
      center: Offset(0, screenRect.bottom - 10),
      width: 62,
      height: 12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(dockRect, const Radius.circular(5)),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    for (var i = 0; i < 5; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(dockRect.left + 8 + i * 11, dockRect.center.dy),
            width: 7,
            height: 7,
          ),
          const Radius.circular(1.6),
        ),
        Paint()..color = palette.screenAccent.withValues(alpha: 0.55),
      );
    }

    // Top-edge camera pinhole (for landscape use).
    canvas.drawCircle(
      Offset(bodyRect.center.dx, bodyRect.top + 2),
      1.2,
      Paint()..color = palette.bezel.withValues(alpha: 0.7),
    );

    // Right side button.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bodyRect.right + 1.5, -20),
          width: 2,
          height: 14,
        ),
        const Radius.circular(1),
      ),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.6),
    );

    // Charge port at bottom center.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, bodyRect.bottom - 2.5),
          width: 12,
          height: 2.2,
        ),
        const Radius.circular(1.1),
      ),
      Paint()..color = palette.bezel,
    );
  }
}

extension _DeviceModelGeometry on SyncDeviceModel {
  Size get _baseSize => switch (this) {
    SyncDeviceModel.macbook => const Size(208, 150),
    SyncDeviceModel.windowsLaptop => const Size(208, 150),
    SyncDeviceModel.windowsDesktop => const Size(210, 155),
    SyncDeviceModel.linuxDesktop => const Size(210, 155),
    SyncDeviceModel.iphone => const Size(72, 180),
    SyncDeviceModel.ipad => const Size(150, 196),
    SyncDeviceModel.androidPhone => const Size(78, 178),
  };
}
