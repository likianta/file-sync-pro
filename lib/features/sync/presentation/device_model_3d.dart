/// Static slightly-tilted device illustrations for the device card.
///
/// Phones/tablets keep a small perspective tilt (≈3°); desktops sit perfectly
/// front-facing so their footprint reads as a clean rectangle. A trailing
/// multi-layer shadow extends below the painter bounds so it overlaps the
/// card content beneath — a deliberate depth cue.
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
    required this.shadow,
    required this.emblem,
    required this.wallpaperTop,
    required this.wallpaperBottom,
    required this.wallpaperAccent1,
    required this.wallpaperAccent2,
  });

  final Color bodyLight;
  final Color bodyDark;
  final Color bezel;
  final Color shadow;
  final Color emblem;
  final Color wallpaperTop;
  final Color wallpaperBottom;
  final Color wallpaperAccent1;
  final Color wallpaperAccent2;

  // MacBook Pro — M-series space gray
  static const mac = _ModelPalette(
    bodyLight: Color(0xFFC8CCD1),
    bodyDark: Color(0xFF5B5F67),
    bezel: Color(0xFF0C0D10),
    shadow: Color(0xFF000000),
    emblem: Color(0xFFE8E8EA),
    // macOS Sonoma / Sequoia wallpaper — warm amber + cool teal abstract wave
    wallpaperTop: Color(0xFFF5B872),
    wallpaperBottom: Color(0xFF2A4F6F),
    wallpaperAccent1: Color(0xFFE87C4A),
    wallpaperAccent2: Color(0xFF3D9EAF),
  );

  static const windows = _ModelPalette(
    bodyLight: Color(0xFFCDD3DA),
    bodyDark: Color(0xFF485059),
    bezel: Color(0xFF12161C),
    shadow: Color(0xFF000000),
    emblem: Color(0xFFFACC15),
    // Windows 11 bloom — cyan to magenta soft gradient
    wallpaperTop: Color(0xFF22D3EE),
    wallpaperBottom: Color(0xFFA21C7A),
    wallpaperAccent1: Color(0xFF60A5FA),
    wallpaperAccent2: Color(0xFFF472B6),
  );

  static const windowsDesktop = _ModelPalette(
    bodyLight: Color(0xFFC0C6CE),
    bodyDark: Color(0xFF444B54),
    bezel: Color(0xFF0E1115),
    shadow: Color(0xFF000000),
    emblem: Color(0xFFFACC15),
    wallpaperTop: Color(0xFF60A5FA),
    wallpaperBottom: Color(0xFFA21C7A),
    wallpaperAccent1: Color(0xFF818CF8),
    wallpaperAccent2: Color(0xFFF472B6),
  );

  static const linux = _ModelPalette(
    bodyLight: Color(0xFFBDB0D0),
    bodyDark: Color(0xFF3D2E54),
    bezel: Color(0xFF120C1E),
    shadow: Color(0xFF000000),
    emblem: Color(0xFFFBBF24),
    // Ubuntu 24.04 Noble — purple to orange
    wallpaperTop: Color(0xFF7C3AED),
    wallpaperBottom: Color(0xFFF97316),
    wallpaperAccent1: Color(0xFFA78BFA),
    wallpaperAccent2: Color(0xFFFDBA74),
  );

  static const iphone = _ModelPalette(
    bodyLight: Color(0xFFE4E6EA),
    bodyDark: Color(0xFF383C42),
    bezel: Color(0xFF0A0B0D),
    shadow: Color(0xFF000000),
    emblem: Color(0xFFE8E8EA),
    // iOS 18 wave — rich teal to purple
    wallpaperTop: Color(0xFF0EA5E9),
    wallpaperBottom: Color(0xFF6366F1),
    wallpaperAccent1: Color(0xFF22D3EE),
    wallpaperAccent2: Color(0xFFA855F7),
  );

  static const ipad = _ModelPalette(
    bodyLight: Color(0xFFCFCFD4),
    bodyDark: Color(0xFF44484F),
    bezel: Color(0xFF0A0B0D),
    shadow: Color(0xFF000000),
    emblem: Color(0xFFE8E8EA),
    // iPadOS — blue aurora
    wallpaperTop: Color(0xFF3B82F6),
    wallpaperBottom: Color(0xFF1E3A8A),
    wallpaperAccent1: Color(0xFF60A5FA),
    wallpaperAccent2: Color(0xFFC4B5FD),
  );

  static const android = _ModelPalette(
    bodyLight: Color(0xFFD3D3D7),
    bodyDark: Color(0xFF3E3E46),
    bezel: Color(0xFF0B0C10),
    shadow: Color(0xFF000000),
    emblem: Color(0xFF4ADE80),
    // Android Material You — olive to mint
    wallpaperTop: Color(0xFF84CC16),
    wallpaperBottom: Color(0xFF065F46),
    wallpaperAccent1: Color(0xFFA3E635),
    wallpaperAccent2: Color(0xFF10B981),
  );
}

class _DeviceRender {
  static bool _isDesktop(SyncDeviceModel model) => switch (model) {
    SyncDeviceModel.windowsDesktop || SyncDeviceModel.linuxDesktop => true,
    _ => false,
  };

  static void render({
    required Canvas canvas,
    required Size size,
    required SyncDeviceModel model,
    required _ModelPalette palette,
  }) {
    final desktop = _isDesktop(model);
    const tiltX = 0.05;
    const tiltZ = -0.04;

    final baseSize = model._baseSize;
    // Extra topPadding keeps rotated device bodies far enough from the widget
    // top edge — iPad has the tallest tilted profile. bottomPadding reserves
    // space for the trailing shadow to bleed into the card's label row.
    const topPadding = 48.0;
    const bottomPadding = 28.0;
    const sidePadding = 16.0;

    final availableH = size.height - topPadding - bottomPadding;
    final availableW = size.width - sidePadding * 2;
    final scaleX = availableW / baseSize.width;
    final scaleY = availableH / baseSize.height;
    final scale = math.min(scaleX, scaleY);

    // Place center such that the device body (half of baseSize*scale) fits
    // inside [topPadding, size.height - bottomPadding].
    final bodyH = baseSize.height * scale;
    final bottomY = size.height - bottomPadding - bodyH / 2;
    final center = Offset(size.width / 2, bottomY);
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..setEntry(3, 2, desktop ? 0.0 : 0.0006)
      ..rotateX(desktop ? 0.0 : tiltX)
      ..rotateZ(desktop ? 0.0 : tiltZ);

    // --- TRAILING SHADOW (painted before device so device sits on top) ---
    canvas.save();
    final floorY = bodyH / 2 + 2;
    canvas.translate(center.dx, center.dy + floorY);
    canvas.scale(scale);
    _paintShadowPile(canvas, palette, baseSize);
    canvas.restore();

    // --- DEVICE ---
    canvas.save();
    canvas.transform(matrix.storage);
    switch (model) {
      case SyncDeviceModel.macbook:
        _paintMacBookPro(canvas, palette);
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

  /// Three-layer shadow, all with generous blur so the edge bleeds into
  /// whatever content sits beneath.
  static void _paintShadowPile(
    Canvas canvas,
    _ModelPalette palette,
    Size base,
  ) {
    // Ambient floor shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(0, 3),
        width: base.width * 1.7,
        height: base.height * 0.09,
      ),
      Paint()
        ..color = palette.shadow.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 56),
    );
    // Contact shadow directly under the device.
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(0, 1),
        width: base.width * 1.10,
        height: 14,
      ),
      Paint()
        ..color = palette.shadow.withValues(alpha: 0.36)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    // Downward trail — bleeds into card content below.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, base.height * 0.16),
        width: base.width * 0.82,
        height: 38,
      ),
      Paint()
        ..color = palette.shadow.withValues(alpha: 0.26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
    );
  }

  // --- LAPTOPS ------------------------------------------------------------

  static void _paintLaptopBase(
    Canvas canvas,
    _ModelPalette palette, {
    required double lidWidthRatio,
    required bool showWindowsKey,
    required bool showMacBookCutout,
  }) {
    const deckW = 220.0;
    const deckH = 16.0;
    const lidH = 130.0;
    final lidW = deckW * lidWidthRatio;

    // Keyboard deck.
    final deck = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: deckW, height: deckH),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      deck.shift(const Offset(0, 6)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.7),
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
      const Radius.circular(6),
    );
    canvas.drawRRect(
      lid.shift(const Offset(0, 5)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.6),
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
    canvas.drawRRect(
      lid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.15),
    );

    // MacBook Pro style — black keyboard well cutout, black bottom bezel strip.
    if (showMacBookCutout) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(0, deckH / 2 - 1),
            width: deckW - 20,
            height: 10,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = palette.bezel,
      );
      // Apple notch-like screen cutout (MacBook Pro 2021+).
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(0, lidCenter.dy - lidH / 2 + 2),
            width: 28,
            height: 4,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = palette.bezel,
      );
    }

    // Webcam pinhole at top-center of lid bezel.
    canvas.drawCircle(
      Offset(0, lidCenter.dy - lidH / 2 + 5),
      1.3,
      Paint()..color = palette.bezel,
    );

    // Screen inset.
    final screenInset = showMacBookCutout ? 7.0 : 6.0;
    final screenRect = Rect.fromCenter(
      center: lidCenter,
      width: lidW - screenInset * 2,
      height: lidH - screenInset * 2 - 6,
    );
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(2),
    );
    _paintWallpaper(canvas, palette, screen);

    // Keyboard grid.
    _paintKeyboard(canvas, palette, deckW);
    _paintTrackpad(canvas, palette, deckW);

    // Brand emblem on lid.
    if (showMacBookCutout) {
      _paintAppleLogo(canvas, palette, lidCenter + Offset(0, lidH * 0.15));
    } else {
      _paintWindowsLogo(canvas, palette, lidCenter + Offset(0, lidH * 0.18));
    }
  }

  static void _paintKeyboard(
    Canvas canvas,
    _ModelPalette palette,
    double deckW,
  ) {
    const rows = 4;
    const cols = 14;
    const keyW = 9.5;
    const keyH = 4.2;
    const gap = 1.4;
    final keyPaint = Paint()..color = palette.bezel.withValues(alpha: 0.42);
    final keyTopPaint = Paint()..color = Colors.white.withValues(alpha: 0.25);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final dx = -((cols - 1) * (keyW + gap)) / 2 + c * (keyW + gap);
        final dy = -5 + r * (keyH + gap);
        final keyRect = Rect.fromLTWH(dx, dy, keyW, keyH);
        canvas.drawRRect(
          RRect.fromRectAndRadius(keyRect, const Radius.circular(0.7)),
          keyPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(dx + 0.2, dy + 0.3, keyW - 0.4, 1.2),
            const Radius.circular(0.5),
          ),
          keyTopPaint,
        );
      }
    }
  }

  static void _paintTrackpad(
    Canvas canvas,
    _ModelPalette palette,
    double deckW,
  ) {
    final trackpad = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: const Offset(0, 10),
        width: deckW * 0.40,
        height: 11,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      trackpad,
      Paint()..color = palette.bodyDark.withValues(alpha: 0.35),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(0, 7.8),
          width: deckW * 0.40 - 2,
          height: 1.5,
        ),
        const Radius.circular(1),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
  }

  static void _paintWallpaper(
    Canvas canvas,
    _ModelPalette palette,
    RRect screen,
  ) {
    final rect = screen.outerRect;
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.wallpaperTop, palette.wallpaperBottom],
        ).createShader(rect),
    );
    // Soft accent blobs to suggest the OS wallpaper pattern.
    canvas.save();
    canvas.clipRRect(screen);
    final cx = rect.width * 0.35;
    final cy = rect.height * 0.3;
    canvas.drawCircle(
      Offset(cx, cy),
      rect.width * 0.32,
      Paint()
        ..color = palette.wallpaperAccent1.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(
      Offset(rect.width * 0.75, rect.height * 0.6),
      rect.width * 0.28,
      Paint()
        ..color = palette.wallpaperAccent2.withValues(alpha: 0.38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    // Second gradient pass for depth.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.12),
          ],
        ).createShader(rect),
    );
    // Top row hint — dock / menu bar indicator.
    canvas.drawRect(
      Rect.fromLTWH(rect.left + 6, rect.top + 4, rect.width - 12, 0.6),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.restore();
  }

  static void _paintAppleLogo(
    Canvas canvas,
    _ModelPalette palette,
    Offset center,
  ) {
    final paint = Paint()..color = palette.emblem.withValues(alpha: 0.85);
    final leaf = Path()
      ..moveTo(center.dx, center.dy - 5.5)
      ..cubicTo(
        center.dx + 2.8,
        center.dy - 4.5,
        center.dx + 3.8,
        center.dy + 1.2,
        center.dx + 1.0,
        center.dy + 4.5,
      )
      ..cubicTo(
        center.dx - 0.8,
        center.dy + 5.2,
        center.dx - 3.8,
        center.dy + 1.8,
        center.dx - 2.8,
        center.dy - 3.0,
      )
      ..close();
    canvas.drawPath(leaf, paint);
    canvas.drawCircle(
      Offset(center.dx + 3.0, center.dy - 1.8),
      1.4,
      Paint()..color = palette.bodyLight,
    );
  }

  static void _paintWindowsLogo(
    Canvas canvas,
    _ModelPalette palette,
    Offset center,
  ) {
    final paint = Paint()..color = palette.emblem.withValues(alpha: 0.8);
    const size = 4.0;
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
  }

  static void _paintMacBookPro(Canvas canvas, _ModelPalette palette) {
    _paintLaptopBase(
      canvas,
      palette,
      lidWidthRatio: 0.95,
      showWindowsKey: false,
      showMacBookCutout: true,
    );
  }

  static void _paintWindowsLaptop(Canvas canvas, _ModelPalette palette) {
    _paintLaptopBase(
      canvas,
      palette,
      lidWidthRatio: 0.90,
      showWindowsKey: true,
      showMacBookCutout: false,
    );
  }

  // --- DESKTOPS -----------------------------------------------------------

  static void _paintDesktopBase(
    Canvas canvas,
    _ModelPalette palette, {
    required bool towerOnRight,
  }) {
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
    canvas.drawLine(
      Offset(towerOffsetX + 16, tower.outerRect.top + 8),
      Offset(towerOffsetX + 16, tower.outerRect.bottom - 8),
      Paint()
        ..color = palette.wallpaperAccent1.withValues(alpha: 0.75)
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(
      Offset(towerOffsetX + 16, tower.outerRect.top + 6),
      1.2,
      Paint()..color = palette.wallpaperAccent1,
    );

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

    const monitorH = 104.0;
    const monitorW = 162.0;
    final monitorCenter = const Offset(0, -46);
    final monitor = RRect.fromRectAndRadius(
      Rect.fromCenter(center: monitorCenter, width: monitorW, height: monitorH),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      monitor.shift(const Offset(0, 3)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.6),
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

    final screenRect = Rect.fromCenter(
      center: monitorCenter,
      width: monitorW - 14,
      height: monitorH - 14,
    );
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(2),
    );
    _paintWallpaper(canvas, palette, screen);

    // Brand dot under monitor.
    canvas.drawCircle(
      Offset(monitorCenter.dx, monitorCenter.dy + monitorH / 2 - 5),
      1.4,
      Paint()..color = palette.emblem.withValues(alpha: 0.8),
    );

    // Cable from tower back to monitor.
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

  static void _paintWindowsDesktop(Canvas canvas, _ModelPalette palette) {
    _paintDesktopBase(canvas, palette, towerOnRight: true);
  }

  static void _paintLinuxDesktop(Canvas canvas, _ModelPalette palette) {
    _paintDesktopBase(canvas, palette, towerOnRight: false);
  }

  // --- PHONES -------------------------------------------------------------

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

  static void _paintIPhone(Canvas canvas, _ModelPalette palette) {
    const bodyW = 72.0;
    const bodyH = 180.0;
    final bodyRect = Rect.fromCenter(
      center: Offset.zero,
      width: bodyW,
      height: bodyH,
    );
    final body = RRect.fromRectAndRadius(
      bodyRect,
      Radius.circular(bodyW * 0.22),
    );

    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.bodyLight, palette.bodyDark],
        ).createShader(bodyRect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    // Side buttons.
    final buttonPaint = Paint()
      ..color = palette.bodyDark.withValues(alpha: 0.55);
    final leftX = bodyRect.left - 1.5;
    for (final (y, h) in [(-58.0, 9.0), (-40.0, 11.0), (-22.0, 11.0)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(leftX, y), width: 2, height: h),
          const Radius.circular(1),
        ),
        buttonPaint,
      );
    }
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
    final screen = RRect.fromRectAndRadius(
      screenRect,
      Radius.circular(screenRect.width * 0.20),
    );
    _paintWallpaper(canvas, palette, screen);

    // Dynamic Island.
    final islandRect = Rect.fromCenter(
      center: Offset(0, screenRect.top + 11),
      width: 46,
      height: 12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(islandRect, const Radius.circular(6)),
      Paint()..color = palette.bezel,
    );
    canvas.drawCircle(
      Offset(islandRect.center.dx + 9, islandRect.center.dy),
      2.2,
      Paint()..color = const Color(0xFF0F172A),
    );
    canvas.drawCircle(
      Offset(islandRect.center.dx + 9, islandRect.center.dy),
      1.2,
      Paint()..color = palette.wallpaperAccent1.withValues(alpha: 0.6),
    );
    canvas.drawCircle(
      Offset(islandRect.center.dx + 14, islandRect.center.dy),
      0.8,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );

    _paintStatusBar(canvas, palette, screenRect, showTimeOnLeft: false);

    // Home indicator.
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
    final body = RRect.fromRectAndRadius(
      bodyRect,
      Radius.circular(bodyW * 0.22),
    );

    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.55),
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

    final buttonPaint = Paint()
      ..color = palette.bodyDark.withValues(alpha: 0.55);
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

    final screenInset = 2.0;
    final screenRect = bodyRect.deflate(screenInset);
    final screen = RRect.fromRectAndRadius(
      screenRect,
      Radius.circular(screenRect.width * 0.20),
    );
    _paintWallpaper(canvas, palette, screen);

    // Punch-hole camera (centered top).
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
      Paint()..color = palette.wallpaperAccent1.withValues(alpha: 0.6),
    );

    _paintStatusBar(canvas, palette, screenRect, showTimeOnLeft: true);

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

  static void _paintBottomEdge(
    Canvas canvas,
    _ModelPalette palette,
    Rect bodyRect,
    double bodyW,
  ) {
    final speakerCx = bodyRect.center.dx - 12;
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(
        Offset(speakerCx + i * 2.2, bodyRect.bottom - 2.2),
        0.6,
        Paint()..color = palette.bezel.withValues(alpha: 0.7),
      );
    }
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
    final body = RRect.fromRectAndRadius(bodyRect, const Radius.circular(14));

    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.55),
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

    final screenInset = 8.0;
    final screenRect = bodyRect.deflate(screenInset);
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(6),
    );
    _paintWallpaper(canvas, palette, screen);

    // Camera module (top-left plate).
    final camPlateCenter = Offset(bodyRect.left + 7, bodyRect.top + 7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: camPlateCenter, width: 11, height: 11),
        const Radius.circular(3),
      ),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      camPlateCenter + const Offset(-2.5, -2),
      1.8,
      Paint()..color = const Color(0xFF0F172A),
    );
    canvas.drawCircle(
      camPlateCenter + const Offset(2.5, 2),
      1.8,
      Paint()..color = const Color(0xFF0F172A),
    );
    canvas.drawCircle(
      camPlateCenter + const Offset(-2.5, -2),
      0.7,
      Paint()..color = palette.wallpaperAccent1.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      camPlateCenter + const Offset(2.5, -2.5),
      0.8,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );

    _paintStatusBar(canvas, palette, screenRect, showTimeOnLeft: false);

    // Dock.
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
        Paint()..color = palette.wallpaperAccent1.withValues(alpha: 0.55),
      );
    }

    canvas.drawCircle(
      Offset(bodyRect.center.dx, bodyRect.top + 2),
      1.2,
      Paint()..color = palette.bezel.withValues(alpha: 0.7),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bodyRect.right + 1.5, -20),
          width: 2,
          height: 14,
        ),
        const Radius.circular(1),
      ),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.55),
    );

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
    SyncDeviceModel.macbook => const Size(220, 150),
    SyncDeviceModel.windowsLaptop => const Size(208, 150),
    SyncDeviceModel.windowsDesktop => const Size(210, 155),
    SyncDeviceModel.linuxDesktop => const Size(210, 155),
    SyncDeviceModel.iphone => const Size(72, 180),
    SyncDeviceModel.ipad => const Size(150, 196),
    SyncDeviceModel.androidPhone => const Size(78, 178),
  };
}
