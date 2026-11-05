// Genera los iconos de la app de CauceStream desde el logo original
// (assets/logo_iso.png: trazos naranjas #EA580C sobre transparente).
//
// Uso (desde frontend/):
//   dart run tool/gen_app_icons.dart   # fuentes + .ico de Windows
//   dart run flutter_launcher_icons   # mipmaps Android + iconos web
//
// Produce:
// - assets/icons/app_icon.png: cuadrado naranja con los trazos en
//   blanco (fuente para Android legacy y web).
// - assets/icons/app_icon_foreground.png: trazos blancos sobre
//   transparente al 85% del lienzo; flutter_launcher_icons aplica un
//   inset del 16%, dejandolos en ~58% (dentro de la zona segura del
//   66% de los iconos adaptativos).
// - windows/runner/resources/app_icon.ico: multi-tamano (16-256).

import 'dart:io';

import 'package:image/image.dart';

const source = 'assets/logo_iso.png';
final orange = ColorRgba8(234, 88, 12, 255); // naranja exacto del logo

Image whiteFromAlpha(Image src) {
  final out = Image(width: src.width, height: src.height, numChannels: 4);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final a = src.getPixel(x, y).a.toInt();
      out.setPixelRgba(x, y, 255, 255, 255, a);
    }
  }
  return out;
}

Image scaleTo(Image src, int size) => copyResize(src,
    width: size, height: size, interpolation: Interpolation.linear);

void main() {
  final img = decodePng(File(source).readAsBytesSync())!;
  // Caja delimitadora del contenido (alfa > 0) con margen para el
  // antialiasing.
  var minX = img.width, minY = img.height, maxX = 0, maxY = 0;
  for (final p in img) {
    if (p.a > 0) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
  }
  minX -= 2; minY -= 2; maxX += 2; maxY += 2;
  final strokes = whiteFromAlpha(copyCrop(img,
      x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1));

  Directory('assets/icons').createSync(recursive: true);

  // Icono base (1024x1024): naranja con los trazos en blanco al 72%.
  const legacySize = 1024;
  final legacy = Image(width: legacySize, height: legacySize, numChannels: 4);
  fill(legacy, color: orange);
  final ls = (legacySize * 0.72).round();
  final legacyStrokes = scaleTo(strokes, ls);
  compositeImage(legacy, legacyStrokes,
      dstX: (legacySize - ls) ~/ 2, dstY: (legacySize - ls) ~/ 2);
  File('assets/icons/app_icon.png').writeAsBytesSync(encodePng(legacy));

  // Foreground adaptativo (1024x1024, transparente) al 85%.
  const fgSize = 1024;
  final fg = Image(width: fgSize, height: fgSize, numChannels: 4);
  final fs = (fgSize * 0.85).round();
  final fgStrokes = scaleTo(strokes, fs);
  compositeImage(fg, fgStrokes,
      dstX: (fgSize - fs) ~/ 2, dstY: (fgSize - fs) ~/ 2);
  File('assets/icons/app_icon_foreground.png').writeAsBytesSync(encodePng(fg));

  // ICO de Windows con multiples tamanos.
  final icoSizes = [16, 24, 32, 48, 64, 128, 256];
  final frames = icoSizes.map((s) => scaleTo(legacy, s)).toList();
  File('windows/runner/resources/app_icon.ico')
      .writeAsBytesSync(IcoEncoder().encodeImages(frames));

  stdout.writeln('OK: assets/icons/app_icon.png, assets/icons/app_icon_foreground.png,'
      ' windows/runner/resources/app_icon.ico');
}
