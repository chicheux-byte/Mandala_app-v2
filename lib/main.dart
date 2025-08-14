import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MandalaApp());
}

class MandalaApp extends StatelessWidget {
  const MandalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mandala + Dessin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: idx,
        children: const [
          MandalaHomePage(),   // Générateur auto
          FreeDrawPage(),      // Dessin à la main (nouveau)
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (v) => setState(() => idx = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Générer'),
          NavigationDestination(icon: Icon(Icons.brush), label: 'Dessiner'),
        ],
      ),
    );
  }
}

///// ---------- 1) GENERATEUR MANDALA (résumé, comme avant) ----------

class MandalaHomePage extends StatefulWidget {
  const MandalaHomePage({super.key});
  @override
  State<MandalaHomePage> createState() => _MandalaHomePageState();
}

class _MandalaHomePageState extends State<MandalaHomePage> {
  final GlobalKey repaintKey = GlobalKey();
  int seed = DateTime.now().millisecondsSinceEpoch;
  int symmetry = 12;
  int complexity = 8;
  double stroke = 2.5;

  void regenerate() => setState(() => seed = Random().nextInt(1 << 31));

  Future<void> _sharePng() async {
    final bytes = await _capturePng(repaintKey);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/mandala_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(f.path)]);
  }

  Future<void> _savePng() async {
    final bytes = await _capturePng(repaintKey);
    if (bytes == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/mandalas');
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final f = File('${outDir.path}/mandala_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(bytes, flush: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enregistré (mandalas/)')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mandala Generator'),
        actions: [
          IconButton(icon: const Icon(Icons.casino), tooltip: 'Nouveau', onPressed: regenerate),
          IconButton(icon: const Icon(Icons.download), tooltip: 'Enregistrer', onPressed: _savePng),
          IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Partager', onPressed: _sharePng),
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
                    key: repaintKey,
                    child: Container(
                      color: Colors.black,
                      child: CustomPaint(
                        painter: MandalaPainter(
                          seed: seed, symmetry: symmetry, complexity: complexity, stroke: stroke),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(children: [
                Row(children: [
                  const Text('Symétrie'),
                  Expanded(child: Slider(min: 4, max: 36, divisions: 32, value: symmetry.toDouble(), onChanged: (v) => setState(() => symmetry = v.round()))),
                  Text('$symmetry'),
                ]),
                Row(children: [
                  const Text('Complexité'),
                  Expanded(child: Slider(min: 2, max: 16, divisions: 14, value: complexity.toDouble(), onChanged: (v) => setState(() => complexity = v.round()))),
                  Text('$complexity'),
                ]),
                Row(children: [
                  const Text('Épaisseur'),
                  Expanded(child: Slider(min: 0.5, max: 6, value: stroke, onChanged: (v) => setState(() => stroke = v))),
                  Text(stroke.toStringAsFixed(1)),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class MandalaPainter extends CustomPainter {
  final int seed, symmetry, complexity;
  final double stroke;
  MandalaPainter({required this.seed, required this.symmetry, required this.complexity, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.48;
    final palette = [
      const Color(0xff00F5D4), const Color(0xff9B5DE5), const Color(0xffF15BB5),
      const Color(0xffFEE440), const Color(0xff06D6A0), const Color(0xffEF476F), const Color(0xff118AB2),
    ];
    final wedge = (2 * pi) / symmetry;

    final ring = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 1.2;
    canvas.drawCircle(center, radius, ring);

    for (int l = 0; l < complexity; l++) {
      final color = palette[l % palette.length];
      final p = Paint()
        ..color = color.withOpacity(0.95)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = (stroke * (0.7 + l / max(1, complexity))).clamp(0.5, 6);

      final int steps = 24 + rng.nextInt(48);
      final base = Path();
      double r = radius * (0.15 + rng.nextDouble() * 0.8);
      double a = (rng.nextDouble() - 0.5) * wedge * 0.3;
      base.moveTo(center.dx + cos(a) * r, center.dy + sin(a) * r);
      for (int i = 0; i < steps; i++) {
        r = (r + (rng.nextDouble() - 0.5) * radius * 0.06).clamp(radius * 0.05, radius * 0.95);
        a = (a + (rng.nextDouble() - 0.5) * wedge * 0.15).clamp(-wedge * 0.45, wedge * 0.45);
        base.lineTo(center.dx + cos(a) * r, center.dy + sin(a) * r);
      }
      for (int k = 0; k < symmetry; k++) {
        final ang = k * wedge;
        final m = Matrix4.identity()..translate(center.dx, center.dy)..rotateZ(ang)..translate(-center.dx, -center.dy);
        canvas.drawPath(base.transform(m.storage), p);
        final m2 = Matrix4.identity()..translate(center.dx, center.dy)..rotateZ(ang)..scale(1, -1, 1)..translate(-center.dx, -center.dy);
        canvas.drawPath(base.transform(m2.storage), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MandalaPainter old) =>
      old.seed != seed || old.symmetry != symmetry || old.complexity != complexity || old.stroke != stroke;
}

Future<Uint8List?> _capturePng(GlobalKey key) async {
  final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: 3);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
}

///// ---------- 2) DESSIN À LA MAIN (4 pinceaux) ----------

enum BrushType { crayon, marqueur, calligraphie, neon }

class Stroke {
  final List<Offset> points;
  final Color color;
  final double size;
  final BrushType type;
  Stroke({required this.points, required this.color, required this.size, required this.type});
}

class FreeDrawPage extends StatefulWidget {
  const FreeDrawPage({super.key});
  @override
  State<FreeDrawPage> createState() => _FreeDrawPageState();
}

class _FreeDrawPageState extends State<FreeDrawPage> {
  final GlobalKey repaintKey = GlobalKey();
  final List<Stroke> strokes = [];
  final List<Stroke> undone = [];
  BrushType current = BrushType.crayon;
  double size = 8;
  Color color = Colors.cyanAccent;
  bool dark = true;

  void _start(Offset p) {
    undone.clear();
    strokes.add(Stroke(points: [p], color: color, size: size, type: current));
    setState(() {});
  }

  void _update(Offset p) {
    if (strokes.isEmpty) return;
    strokes.last.points.add(p);
    setState(() {});
  }

  void _end() {
    setState(() {});
  }

  void _undo() {
    if (strokes.isNotEmpty) {
      undone.add(strokes.removeLast());
      setState(() {});
    }
  }

  void _redo() {
    if (undone.isNotEmpty) {
      strokes.add(undone.removeLast());
      setState(() {});
    }
  }

  Future<void> _save() async {
    final bytes = await _capturePng(repaintKey);
    if (bytes == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/drawings');
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final f = File('${outDir.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(bytes, flush: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enregistré (drawings/)')));
    }
  }

  Future<void> _share() async {
    final bytes = await _capturePng(repaintKey);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(f.path)], text: 'Mon dessin');
  }

  @override
  Widget build(BuildContext context) {
    final bg = dark ? Colors.black : Colors.white;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dessiner'),
        actions: [
          IconButton(onPressed: _undo, tooltip: 'Annuler', icon: const Icon(Icons.undo)),
          IconButton(onPressed: _redo, tooltip: 'Rétablir', icon: const Icon(Icons.redo)),
          IconButton(onPressed: _save, tooltip: 'Enregistrer', icon: const Icon(Icons.download)),
          IconButton(onPressed: _share, tooltip: 'Partager', icon: const Icon(Icons.ios_share)),
          IconButton(
            tooltip: dark ? 'Fond clair' : 'Fond sombre',
            icon: Icon(dark ? Icons.dark_mode : Icons.light_mode),
            onPressed: () => setState(() => dark = !dark),
          ),
        ],
      ),
      body: Column(
        children: [
          // Zone de dessin
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: RepaintBoundary(
                  key: repaintKey,
                  child: GestureDetector(
                    onPanStart: (d) => _start(d.localPosition),
                    onPanUpdate: (d) => _update(d.localPosition),
                    onPanEnd: (_) => _end(),
                    child: Container(
                      color: bg,
                      child: CustomPaint(
                        painter: FreeDrawPainter(strokes: strokes, dark: dark),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Outils
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Column(
              children: [
                // Choix pinceaux (4)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _BrushButton(
                      icon: Icons.edit,
                      label: 'Crayon',
                      selected: current == BrushType.crayon,
                      onTap: () => setState(() => current = BrushType.crayon),
                    ),
                    _BrushButton(
                      icon: Icons.border_color,
                      label: 'Marqueur',
                      selected: current == BrushType.marqueur,
                      onTap: () => setState(() => current = BrushType.marqueur),
                    ),
                    _BrushButton(
                      icon: Icons.title, // pen inclinée ~ calligraphie
                      label: 'Calli',
                      selected: current == BrushType.calligraphie,
                      onTap: () => setState(() => current = BrushType.calligraphie),
                    ),
                    _BrushButton(
                      icon: Icons.blur_on,
                      label: 'Néon',
                      selected: current == BrushType.neon,
                      onTap: () => setState(() => current = BrushType.neon),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Taille
                Row(children: [
                  const Text('Taille'),
                  Expanded(child: Slider(min: 2, max: 40, value: size, onChanged: (v) => setState(() => size = v))),
                  Text(size.toStringAsFixed(0)),
                ]),
                // Couleurs rapides (pas de dépendance)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in [
                      Colors.white, Colors.black, Colors.redAccent, Colors.orangeAccent, Colors.amberAccent,
                      Colors.limeAccent, Colors.lightGreenAccent, Colors.cyanAccent, Colors.lightBlueAccent,
                      Colors.purpleAccent, Colors.pinkAccent,
                    ])
                      GestureDetector(
                        onTap: () => setState(() => color = c),
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black12, width: 1),
                            boxShadow: [if (color == c) const BoxShadow(blurRadius: 6)],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // Effacer tout
                Row(
                  children: [
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() { strokes.clear(); undone.clear(); }),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Effacer tout'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrushButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BrushButton({required this.icon, required this.label, required this.selected, required this.onTap, super.key});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.15) : Colors.transparent,
          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.black12),
        ),
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)]),
      ),
    );
  }
}

class FreeDrawPainter extends CustomPainter {
  final List<Stroke> strokes;
  final bool dark;
  FreeDrawPainter({required this.strokes, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      switch (s.type) {
        case BrushType.crayon:
          _drawLineStroke(canvas, s, opacity: 1.0, cap: StrokeCap.round, widthMul: 1.0);
          break;
        case BrushType.marqueur:
          _drawLineStroke(canvas, s, opacity: 0.35, cap: StrokeCap.round, widthMul: 2.0);
          break;
        case BrushType.neon:
          _drawNeonStroke(canvas, s);
          break;
        case BrushType.calligraphie:
          _drawCalligraphyStroke(canvas, s, angleRad: pi / 6); // ~30°
          break;
      }
    }
  }

  void _drawLineStroke(Canvas canvas, Stroke s, {double opacity = 1.0, StrokeCap cap = StrokeCap.round, double widthMul = 1.0}) {
    if (s.points.length < 2) {
      if (s.points.isNotEmpty) {
        final p = Paint()
          ..color = s.color.withOpacity(opacity)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(s.points.first, s.size * 0.5 * widthMul, p);
      }
      return;
    }
    final paint = Paint()
      ..color = s.color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = cap
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.size * widthMul;
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (int i = 1; i < s.points.length; i++) {
      path.lineTo(s.points[i].dx, s.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawNeonStroke(Canvas canvas, Stroke s) {
    // halo flou
    final blurPaint = Paint()
      ..color = s.color.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.size * 2.2
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    final corePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = max(1.0, s.size * 0.7);

    if (s.points.length < 2) {
      if (s.points.isNotEmpty) {
        canvas.drawCircle(s.points.first, s.size, blurPaint);
        canvas.drawCircle(s.points.first, s.size * 0.4, corePaint);
      }
      return;
    }
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (int i = 1; i < s.points.length; i++) {
      path.lineTo(s.points[i].dx, s.points[i].dy);
    }
    canvas.drawPath(path, blurPaint);
    canvas.drawPath(path, corePaint);
  }

  void _drawCalligraphyStroke(Canvas canvas, Stroke s, {required double angleRad}) {
    // pinceau "tampon" rectangulaire incliné pour effet calligraphie
    final paint = Paint()
      ..color = s.color
      ..style = PaintingStyle.fill;

    final double w = s.size * 1.8;  // longueur du tampon
    final double h = max(1.0, s.size * 0.5); // épaisseur

    for (final p in s.points) {
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angleRad);
      final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.5));
      canvas.drawRRect(rrect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant FreeDrawPainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.dark != dark;
}
