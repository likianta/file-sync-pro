/// Front-facing flat device illustrations for the device card.
///
/// Every model is drawn straight-on (tilt=0) so its footprint reads cleanly
/// in the card. A trailing three-layer shadow extends below the painter
/// bounds so it gently overlaps the card content beneath.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
    required this.emblemIcon,
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
  final FaIconData emblemIcon;

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
    emblemIcon: FontAwesomeIcons.apple,
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
    emblemIcon: FontAwesomeIcons.windows,
  );

  static const linux = _ModelPalette(
    bodyLight: Color(0xFFBDB0D0),
    bodyDark: Color(0xFF3D2E54),
    bezel: Color(0xFF120C1E),
    shadow: Color(0xFF000000),
    emblem: Color(0xFFF3F4F6),
    wallpaperTop: Color(0xFF312E81),
    wallpaperBottom: Color(0xFF1E1B4B),
    wallpaperAccent1: Color(0xFF6366F1),
    wallpaperAccent2: Color(0xFF3730A3),
    emblemIcon: FontAwesomeIcons.linux,
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
    emblemIcon: FontAwesomeIcons.apple,
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
    emblemIcon: FontAwesomeIcons.android,
  );
}

class _ModelGeometry {
  const _ModelGeometry({
    required this.topY,
    required this.visualBottom,
    required this.baseW,
    required this.sidePadding,
  });

  final double topY;
  final double visualBottom;
  final double baseW;
  final double sidePadding;
}

class _DeviceRender {
  // Uniform padding so every model's top lands at topPadding and the
  // shadow trail sits consistently near bottomPadding.
  static const topPadding = 12.0;
  static const bottomPadding = 18.0;

  // Distance from device visual bottom to shadow top (after scale).
  static const shadowFloorGap = 6.0;

  // Per-model visual geometry (in the body-center relative coordinate
  // system at scale=1). topY = most negative Y from center, visualBottom
  // = most positive Y of the solid body. baseW = painter logical width.
  static const _geometry = <SyncDeviceModel, _ModelGeometry>{
    SyncDeviceModel.macbook: _ModelGeometry(
      topY: -128,
      visualBottom: 6,
      baseW: 220,
      sidePadding: 16,
    ),
    SyncDeviceModel.windowsLaptop: _ModelGeometry(
      topY: -128,
      visualBottom: 6,
      baseW: 220,
      sidePadding: 16,
    ),
    SyncDeviceModel.linuxDesktop: _ModelGeometry(
      topY: -128,
      visualBottom: 6,
      baseW: 220,
      sidePadding: 16,
    ),
    SyncDeviceModel.iphone: _ModelGeometry(
      topY: -68,
      visualBottom: 68,
      baseW: 220,
      sidePadding: 16,
    ),
    SyncDeviceModel.androidPhone: _ModelGeometry(
      topY: -68,
      visualBottom: 68,
      baseW: 220,
      sidePadding: 16,
    ),
  };

  static void render({
    required Canvas canvas,
    required Size size,
    required SyncDeviceModel model,
    required _ModelPalette palette,
  }) {
    if (size.isEmpty) return;
    final g = _geometry[model]!;
    const baseH = 160.0;
    final availableH = size.height - topPadding - bottomPadding;
    final availableW = size.width - g.sidePadding * 2;
    final scaleX = availableW / g.baseW;
    final scaleY = availableH / baseH;
    final scale = math.min(scaleX, scaleY);

    // Pin the model's topmost visual point to topPadding, regardless of
    // how tall the model is. This gives every card the same top gap.
    final centerY = topPadding + (-g.topY) * scale;
    final center = Offset(size.width / 2, centerY);

    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);

    // Shadow sits visualBottom + shadowFloorGap below center.
    canvas.save();
    canvas.translate(
      center.dx,
      center.dy + g.visualBottom * scale + shadowFloorGap,
    );
    canvas.scale(scale);
    _paintShadowPile(canvas, palette, Size(g.baseW, baseH));
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
    // Wide ambient.
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
    // Contact.
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
    // Trailing bleed.
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

  // --- ICON DRAWING ------------------------------------------------------

  /// Draw a FontAwesome glyph on the canvas at [center] with [fontSize].
  /// Uses a text painter so brand logos render crisply at any size.
  static void _paintEmblem(
    Canvas canvas,
    _ModelPalette palette,
    Offset center,
    double fontSize, {
    double? opacity,
  }) {
    final icon = palette.emblemIcon.data;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          fontFamilyFallback: icon.fontFamilyFallback,
          package: icon.fontPackage,
          fontSize: fontSize,
          color: palette.emblem.withValues(alpha: opacity ?? 0.92),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = painter.width;
    final h = painter.height;
    painter.paint(canvas, Offset(center.dx - w / 2, center.dy - h / 2));
  }

  // --- LAPTOPS ------------------------------------------------------------

  /// Paint a modern slim laptop.
  ///
  /// The notch sits ON the screen surface (not in the bezel), flush with the
  /// screen's top edge so it looks like the real MacBook Dynamic Island.
  static void _paintLaptop({
    required Canvas canvas,
    required _ModelPalette palette,
    required Offset lidCenter,
    required double lidW,
    required double lidH,
    required bool showNotch,
    required double emblemSize,
  }) {
    const deckW = 210.0;
    const deckH = 12.0;
    final lidTop = lidCenter.dy - lidH / 2;

    // Keyboard deck (bottom half — behind the lid).
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

    // Lid body.
    final lidBody = RRect.fromRectAndRadius(
      Rect.fromCenter(center: lidCenter, width: lidW, height: lidH),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      lidBody.shift(const Offset(0, 4)),
      Paint()..color = palette.bodyDark.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      lidBody,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bodyLight, palette.bodyDark],
        ).createShader(lidBody.outerRect),
    );
    canvas.drawRRect(
      lidBody,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.15),
    );

    // Screen inset with NARROW bezel (4px modern look).
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

    // Notch — ON the screen surface, top center.
    if (showNotch) {
      final notchCenter = Offset(screenRect.center.dx, screenRect.top + 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: notchCenter, width: 30, height: 6),
          const Radius.circular(3),
        ),
        Paint()..color = palette.bezel,
      );
      canvas.drawCircle(
        Offset(notchCenter.dx + 7, notchCenter.dy),
        1.4,
        Paint()..color = const Color(0xFF0F172A),
      );
    } else {
      // Thin webcam pinhole in bezel above screen.
      canvas.drawCircle(
        Offset(lidCenter.dx, lidTop + 2),
        1.2,
        Paint()..color = palette.bezel,
      );
    }

    // OS emblem centered on screen.
    _paintEmblem(canvas, palette, screenRect.center, emblemSize);

    // Keyboard + trackpad.
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

  // --- SPECIFIC MODELS ---------------------------------------------------

  static void _paintMacBook(Canvas canvas, _ModelPalette palette) {
    _paintLaptop(
      canvas: canvas,
      palette: palette,
      lidCenter: const Offset(0, -64),
      lidW: 210,
      lidH: 128,
      showNotch: true,
      emblemSize: 26,
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
      emblemSize: 24,
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
      emblemSize: 24,
    );
  }

  // --- APPLE DUAL (H-tablet + V-phone, same height) ----------------------

  static void _paintAppleDuo(Canvas canvas, _ModelPalette palette) {
    // iPad landscape + iPhone portrait, same height, horizontally centered.
    const ipadW = 136.0;
    const ipadH = 136.0;
    const phoneW = 68.0;
    const phoneH = 136.0;
    const gap = 6.0;
    const visualOffset = -2.0; // tiny left nudge, iPad's island adds weight
    final totalW = ipadW + gap + phoneW;
    final ipadCenter = Offset(-totalW / 2 + ipadW / 2 + visualOffset, 0);
    final phoneCenter = Offset(ipadCenter.dx + ipadW / 2 + gap + phoneW / 2, 0);

    _paintTablet(
      canvas: canvas,
      palette: palette,
      center: ipadCenter,
      bodyW: ipadW,
      bodyH: ipadH,
      showDynamicIsland: true,
      emblemSize: 22,
    );
    _paintPhone(
      canvas: canvas,
      palette: palette,
      center: phoneCenter,
      bodyW: phoneW,
      bodyH: phoneH,
      showDynamicIsland: true,
      emblemSize: 18,
    );
  }

  static void _paintAndroidDuo(Canvas canvas, _ModelPalette palette) {
    const tabW = 136.0;
    const tabH = 136.0;
    const phoneW = 68.0;
    const phoneH = 136.0;
    const gap = 6.0;
    const visualOffset = -2.0;
    final totalW = tabW + gap + phoneW;
    final tabCenter = Offset(-totalW / 2 + tabW / 2 + visualOffset, 0);
    final phoneCenter = Offset(tabCenter.dx + tabW / 2 + gap + phoneW / 2, 0);

    _paintTablet(
      canvas: canvas,
      palette: palette,
      center: tabCenter,
      bodyW: tabW,
      bodyH: tabH,
      showDynamicIsland: false,
      emblemSize: 22,
      isAndroid: true,
    );
    _paintPhone(
      canvas: canvas,
      palette: palette,
      center: phoneCenter,
      bodyW: phoneW,
      bodyH: phoneH,
      showDynamicIsland: false,
      emblemSize: 18,
      isAndroid: true,
    );
  }

  // --- TABLET / PHONE ----------------------------------------------------

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
    final body = RRect.fromRectAndRadius(bodyRect, const Radius.circular(8));

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

    const screenInset = 5.0;
    final screenRect = bodyRect.deflate(screenInset);
    final screen = RRect.fromRectAndRadius(
      screenRect,
      const Radius.circular(4),
    );
    _paintWallpaper(canvas, palette, screen);

    _paintEmblem(canvas, palette, screenRect.center, emblemSize);

    if (showDynamicIsland) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(screenRect.center.dx, screenRect.top + 5),
            width: 22,
            height: 5,
          ),
          const Radius.circular(2.5),
        ),
        Paint()..color = palette.bezel,
      );
    } else {
      canvas.drawCircle(
        Offset(screenRect.center.dx, screenRect.top + 5),
        1.8,
        Paint()..color = palette.bezel,
      );
    }
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

    _paintEmblem(canvas, palette, screenRect.center, emblemSize);

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
}
