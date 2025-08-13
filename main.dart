
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MandalaApp());
}

class MandalaApp extends StatelessWidget {
  const MandalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mandala Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const RootTabs(),
    );
  }
}

class RootTabs extends StatefulWidget {
  const RootTabs({super.key});

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int idx = 0;
  final galleryKey = GlobalKey<GalleryPageState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: idx,
        children: [
          MandalaHomePage(onSaved: () => galleryKey.currentState?.refresh()),
          GalleryPage(key: galleryKey),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (v) => setState(() => idx = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Générer'),
          NavigationDestination(icon: Icon(Icons.collections), label: 'Galerie'),
        ],
      ),
    );
  }
}

enum ColorStyle { auto, pastel, acrylique, mat, flash }

class MandalaHomePage extends StatefulWidget {
  final VoidCallback? onSaved;
  const MandalaHomePage({super.key, this.onSaved});

  @override
  State<MandalaHomePage> createState() => _MandalaHomePageState();
}

class _MandalaHomePageState extends State<MandalaHomePage> {
  int seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  int symmetry = 12;
  int layers = 6;
  double stroke = 2.0;
  bool dark = true;
  Size exportSize = const Size(2048, 2048);
  ColorStyle style = ColorStyle.auto;

  void regenerate() {
    setState(() {
      seed = Random().nextInt(1 << 31);
    });
  }

  Future<Uint8List?> _renderPng(Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    final painter = MandalaPainter(
      seed: seed,
      symmetry: symmetry,
      layers: layers,
      strokeWidth: stroke,
      dark: dark,
      style: style,
    );
    painter.paint(canvas, size);
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  }

  Future<void> exportPngShare() async {
    final bytes = await _renderPng(exportSize);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/mandala_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Mandala généré avec Mandala Generator');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image exportée via partage.')));
    }
  }

  Future<void> saveToAppGallery() async {
    final bytes = await _renderPng(exportSize);
    if (bytes == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final galleryDir = Directory('${dir.path}/mandalas');
    if (!await galleryDir.exists()) {
      await galleryDir.create(recursive: true);
    }
    final fname = 'mandala_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${galleryDir.path}/$fname');
    await file.writeAsBytes(bytes, flush: true);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enregistré dans la galerie interne.')));
    }
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mandala Generator'),
        actions: [
          IconButton(
            tooltip: 'Nouveau',
            icon: const Icon(Icons.casino),
            onPressed: regenerate,
          ),
          IconButton(
            tooltip: 'Partager en PNG',
            icon: const Icon(Icons.ios_share),
            onPressed: exportPngShare,
          ),
          IconButton(
            tooltip: 'Enregistrer dans la galerie',
            icon: const Icon(Icons.download),
            onPressed: saveToAppGallery,
          ),
          IconButton(
            tooltip: dark ? 'Fond clair' : 'Fond sombre',
            icon: Icon(dark ? Icons.dark_mode : Icons.light_mode),
            onPressed: () => setState(() => dark = !dark),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: MandalaPainter(
                        seed: seed,
                        symmetry: symmetry,
                        layers: layers,
                        strokeWidth: stroke,
                        dark: dark,
                        style: style,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('Symétrie'),
                      Expanded(
                        child: Slider(
                          value: symmetry.toDouble(),
                          min: 4,
                          max: 36,
                          divisions: 32,
                          label: '$symmetry',
                          onChanged: (v) => setState(() => symmetry = v.round()),
                        ),
                      ),
                      Text('$symmetry')
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Complexité'),
                      Expanded(
                        child: Slider(
                          value: layers.toDouble(),
                          min: 2,
                          max: 12,
                          divisions: 10,
                          label: '$layers',
                          onChanged: (v) => setState(() => layers = v.round()),
                        ),
                      ),
                      Text('$layers')
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Épaisseur'),
                      Expanded(
                        child: Slider(
                          value: stroke,
                          min: 0.5,
                          max: 6.0,
                          divisions: 11,
                          label: stroke.toStringAsFixed(1),
                          onChanged: (v) => setState(() => stroke = v),
                        ),
                      ),
                      Text(stroke.toStringAsFixed(1))
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Style'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<ColorStyle>(
                          isExpanded: true,
                          value: style,
                          items: const [
                            DropdownMenuItem(value: ColorStyle.auto, child: Text('Auto')),
                            DropdownMenuItem(value: ColorStyle.pastel, child: Text('Pastel')),
                            DropdownMenuItem(value: ColorStyle.acrylique, child: Text('Acrylique')),
                            DropdownMenuItem(value: ColorStyle.mat, child: Text('Mat')),
                            DropdownMenuItem(value: ColorStyle.flash, child: Text('Flash')),
                          ],
                          onChanged: (v) => setState(() => style = v ?? ColorStyle.auto),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MandalaPainter extends CustomPainter {
  final int seed;
  final int symmetry;
  final int layers;
  final double strokeWidth;
  final bool dark;
  final ColorStyle style;

  MandalaPainter({
    required this.seed,
    required this.symmetry,
    required this.layers,
    required this.strokeWidth,
    required this.dark,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final bg = dark ? Colors.black : Colors.white;
    final fg = dark ? Colors.white : Colors.black;
    final palette = switch (style) {
      ColorStyle.auto => _randomPalette(rng),
      ColorStyle.pastel => _pickPalette(_palettesPastel, rng),
      ColorStyle.acrylique => _pickPalette(_palettesAcrylique, rng),
      ColorStyle.mat => _pickPalette(_palettesMat, rng),
      ColorStyle.flash => _pickPalette(_palettesFlash, rng),
    };

    // fond
    final rect = Offset.zero & size;
    final bgPaint = Paint()..color = bg;
    canvas.drawRect(rect, bgPaint);

    final center = size.center(Offset.zero);
    final radius = min(size.width, size.height) * 0.48;

    // halo doux
    final halo = Paint()
      ..shader = ui.Gradient.radial(center, radius, [
        bg,
        bg.withOpacity(0.0),
      ])
      ..blendMode = BlendMode.srcOver;
    canvas.drawCircle(center, radius * 0.99, halo);

    // anneau externe
    final ring = Paint()
      ..color = fg.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.2;
    canvas.drawCircle(center, radius, ring);

    for (int l = 0; l < layers; l++) {
      final color = palette[l % palette.length];
      final paint = Paint()
        ..color = color.withOpacity(0.92)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = (strokeWidth * (0.75 + l / layers)).clamp(0.5, 6.0);

      final wedgeAngle = (2 * pi) / symmetry;

      // points aléatoires
      final points = <Offset>[];
      final steps = 24 + rng.nextInt(64);
      double r = radius * (0.15 + rng.nextDouble() * 0.8);
      double a = rng.nextDouble() * wedgeAngle * 0.25;
      for (int i = 0; i < steps; i++) {
        r = (r + (rng.nextDouble() - 0.5) * radius * 0.06).clamp(radius * 0.05, radius * 0.95);
        a = (a + (rng.nextDouble() - 0.5) * wedgeAngle * 0.15).clamp(-wedgeAngle * 0.45, wedgeAngle * 0.45);
        points.add(center + Offset.fromDirection(a, r));
      }

      // courbe lissée
      final pathBase = Path();
      if (points.isNotEmpty) {
        pathBase.moveTo(points.first.dx, points.first.dy);
        for (int i = 0; i < points.length - 1; i++) {
          final p0 = i == 0 ? points[i] : points[i - 1];
          final p1 = points[i];
          final p2 = points[i + 1];
          final p3 = i + 2 < points.length ? points[i + 2] : p2;
          final c1 = p1 + (p2 - p0) * (1 / 6);
          final c2 = p2 - (p3 - p1) * (1 / 6);
          pathBase.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
        }
      }

      // répétitions
      for (int k = 0; k < symmetry; k++) {
        final angle = k * wedgeAngle;
        final m = Matrix4.identity()
          ..translate(center.dx, center.dy)
          ..rotateZ(angle)
          ..translate(-center.dx, -center.dy);
        final transformed = pathBase.transform(m.storage);
        canvas.drawPath(transformed, paint);

        final m2 = Matrix4.identity()
          ..translate(center.dx, center.dy)
          ..rotateZ(angle)
          ..scale(1.0, -1.0, 1.0)
          ..translate(-center.dx, -center.dy);
        final transformed2 = pathBase.transform(m2.storage);
        canvas.drawPath(transformed2, paint);
      }

      // ponctuation radiale (points)
      final dots = 30 + rng.nextInt(120);
      final dotPaint = Paint()
        ..color = palette[(l + 1) % palette.length].withOpacity(0.85)
        ..style = PaintingStyle.fill;
      for (int i = 0; i < dots; i++) {
        final rr = radius * (0.1 + rng.nextDouble() * 0.9);
        final baseAngle = (rng.nextDouble() - 0.5) * wedgeAngle * 0.4;
        final pt = center + Offset.fromDirection(baseAngle, rr);
        final d = (strokeWidth * 0.6 + rng.nextDouble() * strokeWidth * 0.9).clamp(0.4, 5.0);
        for (int k = 0; k < symmetry; k++) {
          final angle = k * wedgeAngle;
          final rot = _rotateAround(pt, center, angle);
          canvas.drawCircle(rot, d, dotPaint);
          final mir = _reflectAcrossAxis(rot, center, angle);
          canvas.drawCircle(mir, d * 0.9, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant MandalaPainter oldDelegate) {
    return oldDelegate.seed != seed ||
        oldDelegate.symmetry != symmetry ||
        oldDelegate.layers != layers ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dark != dark ||
        oldDelegate.style != style;
  }

  // --- Palettes jolies par styles ---
  static final List<List<Color>> _palettesPastel = [
    [const Color(0xffA5DEE5), const Color(0xffE3F0FF), const Color(0xffF7DAD9), const Color(0xffC6E2E9)],
    [const Color(0xffD3F8E2), const Color(0xffE4C1F9), const Color(0xffF694C1), const Color(0xffFFF1D0)],
    [const Color(0xffC1DBE3), const Color(0xffF2D3E9), const Color(0xffF9E2AE), const Color(0xffD7ECC8)],
  ];
  static final List<List<Color>> _palettesAcrylique = [
    [const Color(0xff0F4C5C), const Color(0xffFB8B24), const Color(0xffE36414), const Color(0xff9A031E)],
    [const Color(0xff1D3557), const Color(0xffE63946), const Color(0xffF1FAEE), const Color(0xff457B9D)],
    [const Color(0xff2D3142), const Color(0xffEF8354), const Color(0xff4F5D75), const Color(0xffBFC0C0)],
  ];
  static final List<List<Color>> _palettesMat = [
    [const Color(0xff22223B), const Color(0xff4A4E69), const Color(0xff9A8C98), const Color(0xffC9ADA7)],
    [const Color(0xff0B132B), const Color(0xff1C2541), const Color(0xff3A506B), const Color(0xff5BC0BE)],
    [const Color(0xff2F3E46), const Color(0xff354F52), const Color(0xff52796F), const Color(0xff84A98C)],
  ];
  static final List<List<Color>> _palettesFlash = [
    [const Color(0xff00F5D4), const Color(0xff9B5DE5), const Color(0xffF15BB5), const Color(0xffFEE440)],
    [const Color(0xff00BBF9), const Color(0xffFEE440), const Color(0xffFF006E), const Color(0xff8338EC)],
    [const Color(0xff06D6A0), const Color(0xffFFD166), const Color(0xffEF476F), const Color(0xff118AB2)],
  ];

  static List<Color> _pickPalette(List<List<Color>> bank, Random rng) {
    return bank[rng.nextInt(bank.length)];
  }

  static List<Color> _randomPalette(Random rng) {
    final all = <List<Color>>[]
      ..addAll(_palettesPastel)
      ..addAll(_palettesAcrylique)
      ..addAll(_palettesMat)
      ..addAll(_palettesFlash);
    return all[rng.nextInt(all.length)];
  }

  static Offset _rotateAround(Offset p, Offset c, double angle) {
    final s = sin(angle), q = cos(angle);
    final dx = p.dx - c.dx;
    final dy = p.dy - c.dy;
    return Offset(c.dx + dx * q - dy * s, c.dy + dx * s + dy * q);
  }

  static Offset _reflectAcrossAxis(Offset p, Offset c, double angle) {
    final dx = p.dx - c.dx;
    final dy = p.dy - c.dy;
    final cosA = cos(angle);
    final sinA = sin(angle);
    final x1 = dx * cosA + dy * sinA;
    final y1 = -dx * sinA + dy * cosA;
    final x2 = x1;
    final y2 = -y1;
    final xr = x2 * cosA - y2 * sinA;
    final yr = x2 * sinA + y2 * cosA;
    return Offset(c.dx + xr, c.dy + yr);
  }
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => GalleryPageState();
}

class GalleryPageState extends State<GalleryPage> {
  List<FileSystemEntity> images = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final dir = await getApplicationDocumentsDirectory();
    final galleryDir = Directory('${dir.path}/mandalas');
    if (!await galleryDir.exists()) {
      setState(() => images = []);
      return;
    }
    final list = await galleryDir.list().toList();
    list.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    setState(() => images = list.where((e) => e.path.toLowerCase().endsWith('.png')).toList());
  }

  Future<void> shareFile(File f) async {
    await Share.shareXFiles([XFile(f.path)], text: 'Mon mandala');
  }

  Future<void> deleteFile(File f) async {
    await f.delete();
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Galerie'),
        actions: [
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh))
        ],
      ),
      body: images.isEmpty
          ? const Center(child: Text('Aucun dessin pour le moment.\nEnregistre depuis l’onglet Générer.'))
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: images.length,
              itemBuilder: (context, i) {
                final f = File(images[i].path);
                return GestureDetector(
                  onLongPress: () async {
                    showModalBottomSheet(
                      context: context,
                      builder: (_) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.ios_share),
                              title: const Text('Partager'),
                              onTap: () { Navigator.pop(context); shareFile(f); },
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete_outline),
                              title: const Text('Supprimer'),
                              onTap: () { Navigator.pop(context); deleteFile(f); },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(f, fit: BoxFit.cover),
                  ),
                );
              },
            ),
    );
  }
}
