/// Front-facing flat device illustrations for the device card.
///
/// Every model is drawn straight-on (tilt=0) so its footprint reads cleanly
/// in the card. A trailing three-layer shadow extends below the painter
/// bounds so it gently overlaps the card content beneath.
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
    SyncDeviceModel.linuxDesktop: _ModelPalette.linux,
    SyncDeviceModel.iphone: _ModelPalette.ios,
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

  // MacBook Pro — space gray
  static const mac = _ModelPalette(
    bodyLight: Color(0xFFC8CCD1),
    bodyDark: Color(0xFF5B5F67),
    bezel: Color(0xFF0C0D10),
    shadow: Color(0xFF000000),
    emblem: Color(0xFFE8E8EA),
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
    wallpaperTop: Color(0xFF22D3EE),
    wallpaperBottom: Color(0xFFA21C7A),
    wallpaperAccent1: Color(0xFF60A5FA),
    wallpaperAccent2: Color(0xFFF472B6),
  );

  static const linux = _ModelPalette(
    bodyLight: Color(0xFFBDB0D0),
    bodyDark: Color(0xFF3D2E54),
    bezel: Color(0xFF120C1E),
    shadow: Color(0xFF000000),
    emblem: Color(0xFFFBBF24),
    wallpaperTop: Color(0xFF7C3AED),
    wallpaperBottom: Color(0xFFF97316),
    wallpaperAccent1: Color(0xFFA78BFA),
    wallpaperAccent2: Color(0xFFFDBA74),
  );

  static const ios = _ModelPalette(
    bodyLight: Color(0xFFE4E6EA),
    bodyDark: Color(0xFF383C42),
    bezel: Color(0xFF0A0B0D),
    shadow: Color(0xFF000000),
    emblem: Color(0xFFE8E8EA),
    wallpaperTop: Color(0xFF0EA5E9),
    wallpaperBottom: Color(0xFF6366F1),
    wallpaperAccent1: Color(0xFF22D3EE),
    wallpaperAccent2: Color(0xFFA855F7),
  );

  static const android = _ModelPalette(
    bodyLight: Color(0xFFD3D3D7),
    bodyDark: Color(0xFF3E3E46),
    bezel: Color(0xFF0B0C10),
    shadow: Color(0xFF000000),
    emblem: Color(0xFF4ADE80),
    wallpaperTop: Color(0xFF84CC16),
    wallpaperBottom: Color(0xFF065F46),
    wallpaperAccent1: Color(0xFFA3E635),
    wallpaperAccent2: Color(0xFF10B981),
  );
}

class _DeviceRender {
  static void render({
    required Canvas canvas,
    required Size size,
    required SyncDeviceModel model,
    required _ModelPalette palette,
  }) {
    const topPadding = 28.0;
    const bottomPadding = 22.0;
    const sidePadding = 16.0;

    final baseSize = const Size(220, 160);
    final availableH = size.height - topPadding - bottomPadding;
    final availableW = size.width - sidePadding * 2;
    final scaleX = availableW / baseSize.width;
    final scaleY = availableH / baseSize.height;
    final scale = math.min(scaleX, scaleY);

    final bodyH = baseSize.height * scale;
    final bottomY = size.height - bottomPadding - bodyH / 2;
    final center = Offset(size.width / 2, bottomY);
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);

    // Shadow (painted first so device sits on top).
    canvas.save();
    canvas.translate(center.dx, center.dy + bodyH / 2 + 3);
    canvas.scale(scale);
    _paintShadowPile(canvas, palette, baseSize);
    canvas.restore();

    // Device.
    canvas.save();
    canvas.transform(matrix.storage);
    switch (model) {
      case SyncDeviceModel.macbook:
        _paintMacBook(canvas, palette);
      case SyncDeviceModel.windowsLaptop:
        _paintWindowsLaptop(canvas, palette);
      case SyncDeviceModel.linuxDesktop:
        _paintLinuxLaptop(canvas, palette);
      case SyncDeviceModel.iphone:
        _paintAppleDuo(canvas, palette);
      case SyncDeviceModel.androidPhone:
        _paintAndroidDuo(canvas, palette);
    }
    canvas.restore();
  }

  static void _paintShadowPile(
    Canvas canvas,
    _ModelPalette palette,
    Size base,
  ) {
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

  /// Paint a modern slim laptop base, screen at [lidCenter], OS icon centered
  /// on the screen.
  static void _paintLaptop({
    required Canvas canvas,
    required _ModelPalette palette,
    required Offset lidCenter,
    required double lidW,
    required double lidH,
    required bool showNotch,
    required void Function(Canvas, Offset) paintScreenEmblem,
  }) {
    const deckW = 210.0;
    const deckH = 12.0;
    final lidTop = lidCenter.dy - lidH / 2;

    // Keyboard deck.
    final deck = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, 0), width: deckW, height: deckH),
      const Radius.circular(3),
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
    final lid = RRect.fromRectAndRadius(
      Rect.fromCenter(center: lidCenter, width: lidW, height: lidH),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      lid.shift(const Offset(0, 4)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.55),
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

    // Notch (MacBook-style) — Dynamic Island shape at top center.
    if (showNotch) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(lidCenter.dx, lidTop + 3),
            width: 32,
            height: 6,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = palette.bezel,
      );
      // Camera lens inside notch.
      canvas.drawCircle(
        Offset(lidCenter.dx + 8, lidTop + 3),
        1.5,
        Paint()..color = const Color(0xFF0F172A),
      );
    } else {
      // Thin webcam pinhole.
      canvas.drawCircle(
        Offset(lidCenter.dx, lidTop + 4),
        1.2,
        Paint()..color = palette.bezel,
      );
    }

    // Screen inset — narrow modern bezel.
    const screenInset = 4.0;
    final screenRect = Rect.fromCenter(
      center: lidCenter,
      width: lidW - screenInset * 2,
      height: lidH - screenInset * 2 - 2,
    );
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(2),
    );
    _paintWallpaper(canvas, palette, screen);

    // OS emblem centered on screen.
    paintScreenEmblem(canvas, screenRect.center);

    // Keyboard.
    _paintKeyboard(canvas, palette, deckW);
    _paintTrackpad(canvas, palette, deckW);
  }

  static void _paintKeyboard(
    Canvas canvas,
    _ModelPalette palette,
    double deckW,
  ) {
    const rows = 3;
    const cols = 14;
    const keyW = 9.5;
    const keyH = 3.5;
    const gap = 1.4;
    final keyPaint = Paint()..color = palette.bezel.withValues(alpha: 0.42);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final dx = -((cols - 1) * (keyW + gap)) / 2 + c * (keyW + gap);
        final dy = -4 + r * (keyH + gap);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(dx, dy, keyW, keyH),
            const Radius.circular(0.7),
          ),
          keyPaint,
        );
      }
    }
  }

  static void _paintTrackpad(
    Canvas canvas,
    _ModelPalette palette,
    double deckW,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(0, 8),
          width: deckW * 0.44,
          height: 11,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.32),
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
    canvas.save();
    canvas.clipRRect(screen);
    canvas.drawCircle(
      Offset(rect.width * 0.35, rect.height * 0.28),
      rect.width * 0.30,
      Paint()
        ..color = palette.wallpaperAccent1.withValues(alpha: 0.42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(
      Offset(rect.width * 0.72, rect.height * 0.62),
      rect.width * 0.26,
      Paint()
        ..color = palette.wallpaperAccent2.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.black.withValues(alpha: 0.14),
          ],
        ).createShader(rect),
    );
    canvas.restore();
  }

  // --- MODELS -------------------------------------------------------------

  static void _paintMacBook(Canvas canvas, _ModelPalette palette) {
    _paintLaptop(
      canvas: canvas,
      palette: palette,
      lidCenter: const Offset(0, -64),
      lidW: 210,
      lidH: 128,
      showNotch: true,
      paintScreenEmblem: (c, center) => _paintAppleLogo(c, palette, center, 22),
    );
  }

  static void _paintWindowsLaptop(Canvas canvas, _ModelPalette palette) {
    _paintLaptop(
      canvas: canvas,
      palette: palette,
      lidCenter: const Offset(0, -64),
      lidW: 200,
      lidH: 128,
      showNotch: false,
      paintScreenEmblem: (c, center) =>
          _paintWindowsLogo(c, palette, center, 22),
    );
  }

  static void _paintLinuxLaptop(Canvas canvas, _ModelPalette palette) {
    _paintLaptop(
      canvas: canvas,
      palette: palette,
      lidCenter: const Offset(0, -64),
      lidW: 200,
      lidH: 128,
      showNotch: false,
      paintScreenEmblem: (c, center) => _paintTuxLogo(c, palette, center, 22),
    );
  }

  // --- APPLE DUAL (iPad + iPhone) ----------------------------------------

  static void _paintAppleDuo(Canvas canvas, _ModelPalette palette) {
    // iPad (taller, wider) on the LEFT.
    const ipadW = 110.0;
    const ipadH = 140.0;
    final ipadCenter = const Offset(-52, -20);
    _paintTablet(
      canvas: canvas,
      palette: palette,
      center: ipadCenter,
      bodyW: ipadW,
      bodyH: ipadH,
      showDynamicIsland: true,
      emblemSize: 18,
    );

    // iPhone on the RIGHT, slightly lower.
    const phoneW = 58.0;
    const phoneH = 136.0;
    final phoneCenter = const Offset(52, -8);
    _paintPhone(
      canvas: canvas,
      palette: palette,
      center: phoneCenter,
      bodyW: phoneW,
      bodyH: phoneH,
      showDynamicIsland: true,
      emblemSize: 12,
    );
  }

  // --- ANDROID DUAL (tablet + phone) -------------------------------------

  static void _paintAndroidDuo(Canvas canvas, _ModelPalette palette) {
    const tabW = 110.0;
    const tabH = 140.0;
    final tabCenter = const Offset(-52, -20);
    _paintTablet(
      canvas: canvas,
      palette: palette,
      center: tabCenter,
      bodyW: tabW,
      bodyH: tabH,
      showDynamicIsland: false,
      emblemSize: 18,
      isAndroid: true,
    );

    const phoneW = 58.0;
    const phoneH = 136.0;
    final phoneCenter = const Offset(52, -8);
    _paintPhone(
      canvas: canvas,
      palette: palette,
      center: phoneCenter,
      bodyW: phoneW,
      bodyH: phoneH,
      showDynamicIsland: false,
      emblemSize: 12,
      isAndroid: true,
    );
  }

  // --- TABLET / PHONE SHARED ----------------------------------------------

  static void _paintTablet({
    required Canvas canvas,
    required _ModelPalette palette,
    required Offset center,
    required double bodyW,
    required double bodyH,
    required bool showDynamicIsland,
    required double emblemSize,
    bool isAndroid = false,
  }) {
    final bodyRect = Rect.fromCenter(
      center: center,
      width: bodyW,
      height: bodyH,
    );
    final body = RRect.fromRectAndRadius(bodyRect, const Radius.circular(10));

    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.5),
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
        ..strokeWidth = 0.7
        ..color = Colors.white.withValues(alpha: 0.25),
    );

    const screenInset = 6.0;
    final screenRect = bodyRect.deflate(screenInset);
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(4),
    );
    _paintWallpaper(canvas, palette, screen);

    // Screen emblem centered.
    final paintEmblem = isAndroid ? _paintAndroidLogo : _paintAppleLogo;
    paintEmblem(canvas, palette, screenRect.center, emblemSize);

    if (showDynamicIsland) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(screenRect.center.dx, screenRect.top + 6),
            width: 24,
            height: 6,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = palette.bezel,
      );
    } else {
      // Punch hole.
      canvas.drawCircle(
        Offset(screenRect.center.dx, screenRect.top + 6),
        2.0,
        Paint()..color = palette.bezel,
      );
    }

    // Camera module (top-left).
    final camCenter = Offset(bodyRect.left + 6, bodyRect.top + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: camCenter, width: 9, height: 9),
        const Radius.circular(3),
      ),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      Offset(camCenter.dx - 1.5, camCenter.dy - 1),
      1.4,
      Paint()..color = const Color(0xFF0F172A),
    );
  }

  static void _paintPhone({
    required Canvas canvas,
    required _ModelPalette palette,
    required Offset center,
    required double bodyW,
    required double bodyH,
    required bool showDynamicIsland,
    required double emblemSize,
    bool isAndroid = false,
  }) {
    final bodyRect = Rect.fromCenter(
      center: center,
      width: bodyW,
      height: bodyH,
    );
    final body = RRect.fromRectAndRadius(
      bodyRect,
      Radius.circular(bodyW * 0.22),
    );

    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.5),
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
        ..color = Colors.white.withValues(alpha: 0.3),
    );

    const screenInset = 2.2;
    final screenRect = bodyRect.deflate(screenInset);
    final screen = RRect.fromRectAndRadius(
      screenRect,
      Radius.circular(screenRect.width * 0.20),
    );
    _paintWallpaper(canvas, palette, screen);

    final paintEmblem = isAndroid ? _paintAndroidLogo : _paintAppleLogo;
    paintEmblem(canvas, palette, screenRect.center, emblemSize);

    if (showDynamicIsland) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(screenRect.center.dx, screenRect.top + 9),
            width: 30,
            height: 8,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = palette.bezel,
      );
      canvas.drawCircle(
        Offset(screenRect.center.dx + 6, screenRect.top + 9),
        1.4,
        Paint()..color = const Color(0xFF0F172A),
      );
    } else {
      canvas.drawCircle(
        Offset(screenRect.center.dx, screenRect.top + 9),
        2.8,
        Paint()..color = palette.bezel,
      );
      canvas.drawCircle(
        Offset(screenRect.center.dx, screenRect.top + 9),
        1.8,
        Paint()..color = const Color(0xFF0F172A),
      );
    }

    // Side buttons.
    final buttonPaint = Paint()
      ..color = palette.bodyDark.withValues(alpha: 0.5);
    final leftX = bodyRect.left - 1.2;
    for (final (y, h) in [(center.dy - 30, 7.0), (center.dy - 16, 9.0)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(leftX, y), width: 1.8, height: h),
          const Radius.circular(0.9),
        ),
        buttonPaint,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bodyRect.right + 1.2, center.dy - 22),
          width: 1.8,
          height: 11,
        ),
        const Radius.circular(0.9),
      ),
      buttonPaint,
    );
  }

  // --- OS EMBLEMS ---------------------------------------------------------

  /// Classic Apple logo (silhouette with leaf). [size] controls width.
  static void _paintAppleLogo(
    Canvas canvas,
    _ModelPalette palette,
    Offset center,
    double size,
  ) {
    final paint = Paint()..color = palette.emblem.withValues(alpha: 0.92);
    final halfW = size / 2;
    final apple = Path()
      ..moveTo(center.dx + halfW * 0.05, center.dy - halfW * 0.15)
      ..cubicTo(
        center.dx + halfW * 0.35,
        center.dy - halfW * 0.30,
        center.dx + halfW * 0.45,
        center.dy + halfW * 0.35,
        center.dx + halfW * 0.10,
        center.dy + halfW * 0.55,
      )
      ..cubicTo(
        center.dx - halfW * 0.15,
        center.dy + halfW * 0.70,
        center.dx - halfW * 0.45,
        center.dy + halfW * 0.35,
        center.dx - halfW * 0.40,
        center.dy - halfW * 0.15,
      )
      ..cubicTo(
        center.dx - halfW * 0.35,
        center.dy - halfW * 0.45,
        center.dx - halfW * 0.05,
        center.dy - halfW * 0.55,
        center.dx + halfW * 0.05,
        center.dy - halfW * 0.15,
      )
      ..close();
    canvas.drawPath(apple, paint);

    // Leaf.
    final leaf = Path()
      ..moveTo(center.dx - halfW * 0.05, center.dy - halfW * 0.55)
      ..cubicTo(
        center.dx + halfW * 0.15,
        center.dy - halfW * 0.85,
        center.dx + halfW * 0.50,
        center.dy - halfW * 0.75,
        center.dx + halfW * 0.40,
        center.dy - halfW * 0.55,
      )
      ..cubicTo(
        center.dx + halfW * 0.25,
        center.dy - halfW * 0.50,
        center.dx + halfW * 0.05,
        center.dy - halfW * 0.45,
        center.dx - halfW * 0.05,
        center.dy - halfW * 0.55,
      )
      ..close();
    canvas.drawPath(leaf, paint);
  }

  /// Windows 11-style 2x2 window grid. [size] = total width.
  static void _paintWindowsLogo(
    Canvas canvas,
    _ModelPalette palette,
    Offset center,
    double size,
  ) {
    final paint = Paint()..color = palette.emblem.withValues(alpha: 0.88);
    final cellW = size * 0.42;
    final cellH = size * 0.42;
    const gap = 1.0;
    for (var i = 0; i < 2; i++) {
      for (var j = 0; j < 2; j++) {
        final rect = Rect.fromCenter(
          center: Offset(
            center.dx - cellW / 2 + i * (cellW + gap),
            center.dy - cellH / 2 + j * (cellH + gap),
          ),
          width: cellW,
          height: cellH,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          paint,
        );
      }
    }
  }

  /// Simplified Tux penguin silhouette for Linux. [size] controls body width.
  static void _paintTuxLogo(
    Canvas canvas,
    _ModelPalette palette,
    Offset center,
    double size,
  ) {
    final bodyPaint = Paint()..color = palette.emblem.withValues(alpha: 0.88);
    final bellyPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);

    final w = size;
    final h = size * 1.15;

    // Body — fat teardrop shape.
    final body = Path()
      ..moveTo(center.dx, center.dy - h * 0.5)
      ..cubicTo(
        center.dx + w * 0.55,
        center.dy - h * 0.45,
        center.dx + w * 0.60,
        center.dy + h * 0.15,
        center.dx + w * 0.40,
        center.dy + h * 0.5,
      )
      ..cubicTo(
        center.dx + w * 0.20,
        center.dy + h * 0.62,
        center.dx - w * 0.20,
        center.dy + h * 0.62,
        center.dx - w * 0.40,
        center.dy + h * 0.5,
      )
      ..cubicTo(
        center.dx - w * 0.60,
        center.dy + h * 0.15,
        center.dx - w * 0.55,
        center.dy - h * 0.45,
        center.dx,
        center.dy - h * 0.5,
      )
      ..close();
    canvas.drawPath(body, bodyPaint);

    // Belly (white oval).
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + h * 0.10),
        width: w * 0.55,
        height: h * 0.55,
      ),
      bellyPaint,
    );

    // Head — distinct from body.
    canvas.drawCircle(
      Offset(center.dx, center.dy - h * 0.35),
      w * 0.32,
      bodyPaint,
    );

    // Eye whites.
    canvas.drawCircle(
      Offset(center.dx - w * 0.10, center.dy - h * 0.38),
      w * 0.09,
      bellyPaint,
    );
    canvas.drawCircle(
      Offset(center.dx + w * 0.10, center.dy - h * 0.38),
      w * 0.09,
      bellyPaint,
    );

    // Pupils.
    final pupilPaint = Paint()..color = palette.bezel;
    canvas.drawCircle(
      Offset(center.dx - w * 0.07, center.dy - h * 0.37),
      w * 0.045,
      pupilPaint,
    );
    canvas.drawCircle(
      Offset(center.dx + w * 0.13, center.dy - h * 0.37),
      w * 0.045,
      pupilPaint,
    );

    // Beak — small triangle between eyes.
    final beak = Path()
      ..moveTo(center.dx - w * 0.05, center.dy - h * 0.30)
      ..lineTo(center.dx + w * 0.05, center.dy - h * 0.30)
      ..lineTo(center.dx, center.dy - h * 0.23)
      ..close();
    canvas.drawPath(beak, Paint()..color = const Color(0xFFF97316));

    // Feet.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - w * 0.18, center.dy + h * 0.58),
        width: w * 0.22,
        height: h * 0.07,
      ),
      Paint()..color = const Color(0xFFF97316),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + w * 0.18, center.dy + h * 0.58),
        width: w * 0.22,
        height: h * 0.07,
      ),
      Paint()..color = const Color(0xFFF97316),
    );
  }

  /// Android robot head. [size] controls head diameter.
  static void _paintAndroidLogo(
    Canvas canvas,
    _ModelPalette palette,
    Offset center,
    double size,
  ) {
    final paint = Paint()..color = palette.emblem.withValues(alpha: 0.92);

    const headScale = 0.75;
    final headW = size * headScale;
    final headH = size * headScale * 0.85;

    // Head rounded rectangle.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy - size * 0.10),
          width: headW,
          height: headH,
        ),
        Radius.circular(headW * 0.30),
      ),
      paint,
    );

    // Antennas — two thin lines going up from head top.
    final antennaPaint = Paint()
      ..color = palette.emblem.withValues(alpha: 0.92)
      ..strokeWidth = size * 0.06
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - size * 0.18, center.dy - size * 0.52),
      Offset(center.dx - size * 0.10, center.dy - size * 0.45),
      antennaPaint,
    );
    canvas.drawLine(
      Offset(center.dx + size * 0.18, center.dy - size * 0.52),
      Offset(center.dx + size * 0.10, center.dy - size * 0.45),
      antennaPaint,
    );
    canvas.drawCircle(
      Offset(center.dx - size * 0.18, center.dy - size * 0.52),
      size * 0.05,
      paint,
    );
    canvas.drawCircle(
      Offset(center.dx + size * 0.18, center.dy - size * 0.52),
      size * 0.05,
      paint,
    );

    // Eyes — white circles.
    final eyePaint = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(center.dx - size * 0.13, center.dy - size * 0.15),
      size * 0.07,
      eyePaint,
    );
    canvas.drawCircle(
      Offset(center.dx + size * 0.13, center.dy - size * 0.15),
      size * 0.07,
      eyePaint,
    );

    // Body — trapezoid below head.
    final bodyW = size * 0.80;
    final bodyTop = center.dy + size * 0.28;
    final body = Path()
      ..moveTo(center.dx - bodyW * 0.35, bodyTop)
      ..lineTo(center.dx + bodyW * 0.35, bodyTop)
      ..lineTo(center.dx + bodyW * 0.55, bodyTop + size * 0.30)
      ..lineTo(center.dx - bodyW * 0.55, bodyTop + size * 0.30)
      ..close();
    canvas.drawPath(body, paint);

    // Arms — small circles on sides.
    canvas.drawCircle(
      Offset(center.dx - size * 0.48, center.dy + size * 0.22),
      size * 0.12,
      paint,
    );
    canvas.drawCircle(
      Offset(center.dx + size * 0.48, center.dy + size * 0.22),
      size * 0.12,
      paint,
    );
  }
}
