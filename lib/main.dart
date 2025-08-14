import 'dart:async';

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';


void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mandala Coloriage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.light,
      ),
      home: const Home(),
    );
  }
}

/// Outils disponibles
enum Tool { bucket, brush, eraser, pipette, pan }

/// Styles de génération
enum StylePreset { simple, detailed, ultra }

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  // Canvas offscreen
  static const int W = 1024, H = 1024;

  // Images de travail
  ui.Image? _lineArtImg;        // traits noirs en TRANSPARENT
  Uint8List? _maskRgba;         // line-art sur fond blanc (pour barrières)
  ui.Image? _colorImg;          // couche couleur (dessous)
  Uint8List _colorRgba = Uint8List(W * H * 4);

  // Génération
  int seed = DateTime.now().millisecondsSinceEpoch;
  int symmetry = 14;
  int rings = 6;
  double stroke = 2.0;
  double detail = 0.8;
  bool doodles = true;
  StylePreset style = StylePreset.detailed;

  // Outils
  Tool tool = Tool.bucket;
  Color paintColor = const Color(0xFF57E1FF);
  double brushSize = 22;

  final TransformationController _ctrl = TransformationController();
  bool _busy = false;
  Offset? _lastDrag;

  @override
  void initState() {
    super.initState();
    _applyPreset(style, regenerate: false);
    _regenerate();
  }

  // ============== Génération ==============

  Future<void> _regenerate() async {
    setState(() => _busy = true);

    // 1) Line-art TRANSPARENT (affichage)
    final rec1 = ui.PictureRecorder();
    final canvas1 = Canvas(rec1, Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
    final painter = LineArtMandalaPainter(
      seed: seed,
      symmetry: symmetry,
      rings: rings,
      stroke: stroke,
      density: detail,
      addDoodles: doodles,
      transparentBackground: true,
    );
    painter.paint(canvas1, Size(W.toDouble(), H.toDouble())); // <-- pas const
    _lineArtImg = await rec1.endRecording().toImage(W, H);

    // 2) Line-art sur FOND BLANC (barrières pour flood-fill)
    final rec2 = ui.PictureRecorder();
    final canvas2 = Canvas(rec2, Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
    final painterMask = LineArtMandalaPainter(
      seed: seed,
      symmetry: symmetry,
      rings: rings,
      stroke: stroke,
      density: detail,
      addDoodles: doodles,
      transparentBackground: false, // fond blanc obligatoire
    );
    painterMask.paint(canvas2, Size(W.toDouble(), H.toDouble()));
    final maskImage = await rec2.endRecording().toImage(W, H);
    final bd = await maskImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    _maskRgba = bd!.buffer.asUint8List();

    // 3) Couche couleur = vide (transparent)
    _colorRgba = Uint8List(W * H * 4);
    _colorImg = await _rgbaToImage(_colorRgba, W, H);

    setState(() => _busy = false);
  }

  Future<ui.Image> _rgbaToImage(Uint8List rgba, int w, int h) async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  // ============== Outils ==============

  Offset _toImageSpace(Offset p, Size box) {
    final s = min(box.width, box.height);
    final scale = W / s;
    return Offset(p.dx * scale, p.dy * scale);
  }

  Future<void> _refreshColorImage() async {
    _colorImg = await _rgbaToImage(_colorRgba, W, H);
    if (mounted) setState(() {});
  }

  void _paintAt(Offset pos, {required bool erase}) {
    final x = pos.dx.clamp(0, W - 1).toInt();
    final y = pos.dy.clamp(0, H - 1).toInt();
    final r = max(1, brushSize ~/ 2);
    final pr = paintColor;
    final cr = erase ? 0 : pr.red,
        cg = erase ? 0 : pr.green,
        cb = erase ? 0 : pr.blue,
        ca = erase ? 0 : pr.alpha;

    for (int j = -r; j <= r; j++) {
      final yy = y + j;
      if (yy < 0 || yy >= H) continue;
      for (int i = -r; i <= r; i++) {
        final xx = x + i;
        if (xx < 0 || xx >= W) continue;
        if (i * i + j * j > r * r) continue;
        final idx = (yy * W + xx) * 4;
        _colorRgba[idx + 0] = cr;
        _colorRgba[idx + 1] = cg;
        _colorRgba[idx + 2] = cb;
        _colorRgba[idx + 3] = ca;
      }
    }
  }

  void _bucketFill(Offset pos) {
    if (_maskRgba == null) return;
    final x0 = pos.dx.clamp(0, W - 1).toInt();
    final y0 = pos.dy.clamp(0, H - 1).toInt();

    bool isBarrierIndex(int pxIndex) {
      final r = _maskRgba![pxIndex + 0];
      final g = _maskRgba![pxIndex + 1];
      final b = _maskRgba![pxIndex + 2];
      return (r + g + b) < 150; // traits noirs/gris = barrière
    }

    final start = (y0 * W + x0) * 4;
    if (isBarrierIndex(start)) return;

    final cr = paintColor.red,
        cg = paintColor.green,
        cb = paintColor.blue,
        ca = paintColor.alpha;

    final visited = Uint8List(W * H);
    final qx = <int>[x0], qy = <int>[y0];

    while (qx.isNotEmpty) {
      final x = qx.removeLast();
      final y = qy.removeLast();
      final p = y * W + x;
      if (visited[p] == 1) continue;
      visited[p] = 1;

      final li = p * 4;
      if (isBarrierIndex(li)) continue;

      _colorRgba[li + 0] = cr;
      _colorRgba[li + 1] = cg;
      _colorRgba[li + 2] = cb;
      _colorRgba[li + 3] = ca;

      if (x > 0) {
        final pp = p - 1;
        if (visited[pp] == 0 && !isBarrierIndex(pp * 4)) {
          qx.add(x - 1);
          qy.add(y);
        }
      }
      if (x < W - 1) {
        final pp = p + 1;
        if (visited[pp] == 0 && !isBarrierIndex(pp * 4)) {
          qx.add(x + 1);
          qy.add(y);
        }
      }
      if (y > 0) {
        final pp = p - W;
        if (visited[pp] == 0 && !isBarrierIndex(pp * 4)) {
          qx.add(x);
          qy.add(y - 1);
        }
      }
      if (y < H - 1) {
        final pp = p + W;
        if (visited[pp] == 0 && !isBarrierIndex(pp * 4)) {
          qx.add(x);
          qy.add(y + 1);
        }
      }
    }
  }

  void _pipette(Offset pos) {
    final x = pos.dx.clamp(0, W - 1).toInt();
    final y = pos.dy.clamp(0, H - 1).toInt();
    final idx = (y * W + x) * 4;
    final r = _colorRgba[idx + 0];
    final g = _colorRgba[idx + 1];
    final b = _colorRgba[idx + 2];
    final a = _colorRgba[idx + 3];
    setState(() {
      paintColor = a == 0 ? Colors.white : Color.fromARGB(a, r, g, b);
    });
  }

  // ============== Styles ==============

  void _applyPreset(StylePreset preset, {bool regenerate = true}) {
    setState(() {
      style = preset;
      switch (preset) {
        case StylePreset.simple:
          symmetry = 10;
          rings = 5;
          stroke = 2.2;
          detail = 0.55;
          doodles = false;
          break;
        case StylePreset.detailed:
          symmetry = 14;
          rings = 6;
          stroke = 2.0;
          detail = 0.8;
          doodles = true;
          break;
        case StylePreset.ultra:
          symmetry = 22;
          rings = 8;
          stroke = 1.8;
          detail = 0.95;
          doodles = true;
          break;
      }
    });
    if (regenerate) _regenerate();
  }

  // ============== UI ==============

  @override
  Widget build(BuildContext context) {
    final canDraw = _lineArtImg != null && _colorImg != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mandala à colorier'),
        actions: [
          _presetChip('Simple', StylePreset.simple),
          _presetChip('Détaillé', StylePreset.detailed),
          _presetChip('Ultra', StylePreset.ultra),
          IconButton(
            icon: const Icon(Icons.casino),
            tooltip: 'Nouveau tirage',
            onPressed: () {
              setState(() => seed = Random().nextInt(1 << 31));
              _regenerate();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black12)],
                  ),
                  child: _busy || !canDraw
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (context, c) {
                            final box = Size(c.maxWidth, c.maxHeight);
                            return InteractiveViewer(
                              transformationController: _ctrl,
                              minScale: 0.6,
                              maxScale: 8.0,
                              panEnabled: tool == Tool.pan,
                              scaleEnabled: true,
                              child: GestureDetector(
                                onTapDown: (d) {
                                  final p = _toImageSpace(d.localPosition, box);
                                  if (tool == Tool.bucket) {
                                    _bucketFill(p);
                                    _refreshColorImage();
                                  } else if (tool == Tool.pipette) {
                                    _pipette(p);
                                  }
                                },
                                onPanStart: (d) {
                                  final p = _toImageSpace(d.localPosition, box);
                                  if (tool == Tool.brush || tool == Tool.eraser) {
                                    _paintAt(p, erase: tool == Tool.eraser);
                                    _lastDrag = p;
                                    _refreshColorImage();
                                  }
                                },
                                onPanUpdate: (d) {
                                  final p = _toImageSpace(d.localPosition, box);
                                  if (tool == Tool.brush || tool == Tool.eraser) {
                                    final steps = ((_lastDrag ?? p) - p).distance ~/ 1 + 1;
                                    for (int i = 0; i <= steps; i++) {
                                      final q = Offset.lerp(_lastDrag ?? p, p, i / max(1, steps))!;
                                      _paintAt(q, erase: tool == Tool.eraser);
                                    }
                                    _lastDrag = p;
                                    _refreshColorImage();
                                  }
                                },
                                onPanEnd: (_) => _lastDrag = null,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    RawImage(image: _colorImg),   // couleurs
                                    RawImage(image: _lineArtImg), // traits
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _toolbar(context),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _presetChip(String label, StylePreset preset) {
    final selected = style == preset;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _applyPreset(preset),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _toolButton(Icons.format_color_fill, 'Pot', Tool.bucket),
              _toolButton(Icons.brush, 'Pinceau', Tool.brush),
              _toolButton(Icons.auto_fix_high, 'Gomme', Tool.eraser),
              _toolButton(Icons.colorize, 'Pipette', Tool.pipette),
              _toolButton(Icons.back_hand, 'Main', Tool.pan),
              const SizedBox(width: 8),
              _palette(),
            ],
          ),
          if (tool == Tool.brush || tool == Tool.eraser)
            Row(
              children: [
                const SizedBox(width: 6),
                const Text('Taille'),
                Expanded(
                  child: Slider(
                    min: 4, max: 64,
                    value: brushSize,
                    onChanged: (v) => setState(() => brushSize = v),
                  ),
                ),
                Text(brushSize.toStringAsFixed(0)),
                const SizedBox(width: 6),
              ],
            ),
        ],
      ),
    );
  }

  Widget _palette() {
    final colors = <Color>[
      Colors.redAccent, Colors.orangeAccent, Colors.amberAccent,
      Colors.lightGreenAccent, Colors.cyanAccent, Colors.lightBlueAccent,
      Colors.purpleAccent, Colors.pinkAccent,
      const Color(0xFF6D4C41), const Color(0xFF37474F),
      Colors.white, Colors.black,
    ];
    return Wrap(
      spacing: 6,
      children: [
        for (final c in colors)
          GestureDetector(
            onTap: () => setState(() => paintColor = c),
            child: Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
                boxShadow: [
                  if (paintColor.value == c.value) const BoxShadow(blurRadius: 6),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _toolButton(IconData icon, String label, Tool t) {
    final selected = tool == t;
    return InkWell(
      onTap: () => setState(() => tool = t),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black26,
          ),
        ),
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)]),
      ),
    );
  }
}

/// --------- Peintre du line-art (traits) ---------
/// transparentBackground=true : fond transparent (affichage)
/// transparentBackground=false : fond blanc (pour le flood-fill)
class LineArtMandalaPainter {
  final int seed;
  final int symmetry;
  final int rings;
  final double stroke;
  final double density;
  final bool addDoodles;
  final bool transparentBackground;

  LineArtMandalaPainter({
    required this.seed,
    required this.symmetry,
    required this.rings,
    required this.stroke,
    required this.density,
    required this.addDoodles,
    required this.transparentBackground,
  });

  final _black = const Color(0xFF000000);

  void paint(Canvas canvas, Size size) {
    if (!transparentBackground) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white,
      );
    }

    final rnd = Random(seed);
    final center = size.center(Offset.zero);
    final R = size.shortestSide * 0.47;

    Paint pen([double w = 1]) => Paint()
      ..color = _black
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.drawCircle(center, R, pen(stroke * 0.85));

    final ringR = List<double>.generate(rings + 1, (i) => R * i / rings);
    final wedge = 2 * pi / symmetry;

    // Rosace centrale
    {
      final rIn = ringR[1] * (0.55 + 0.2 * rnd.nextDouble());
      final rOut = ringR[2] * (0.55 + 0.2 * rnd.nextDouble());
      final petals = max(6, (symmetry / 2).round());
      final base = Path();
      final alpha = wedge / 2.2;
      for (int i = 0; i < petals; i++) {
        final a = i * (2 * pi / petals);
        final p1 = center + Offset.fromDirection(a - alpha, rIn);
        final p2 = center + Offset.fromDirection(a, rOut);
        final p3 = center + Offset.fromDirection(a + alpha, rIn);
        base.moveTo(p1.dx, p1.dy);
        base.quadraticBezierTo(
          center.dx + cos(a - alpha * 0.2) * (rOut * 0.6),
          center.dy + sin(a - alpha * 0.2) * (rOut * 0.6),
          p2.dx, p2.dy,
        );
        base.quadraticBezierTo(
          center.dx + cos(a + alpha * 0.2) * (rOut * 0.6),
          center.dy + sin(a + alpha * 0.2) * (rOut * 0.6),
          p3.dx, p3.dy,
        );
        base.close();
      }
      canvas.drawPath(base, pen(stroke));
    }

    // Anneaux concentriques
    for (int i = 2; i < rings; i++) {
      final ri = ringR[i] * (0.98 - 0.04 * rnd.nextDouble());
      final ro = ringR[i + 1] * (0.98 - 0.04 * rnd.nextDouble());
      final base = Path();
      final motif = rnd.nextInt(3); // 0 pétales, 1 écailles, 2 dentelle
      final segments = max(6, (symmetry * (0.8 + density)).round());

      for (int s = 0; s < segments; s++) {
        final a = s * (2 * pi / segments);
        switch (motif) {
          case 0: // pétales
            final a1 = a - wedge * 0.35;
            final a2 = a + wedge * 0.35;
            final p1 = center + Offset.fromDirection(a1, ri);
            final p2 = center + Offset.fromDirection(a, ro);
            final p3 = center + Offset.fromDirection(a2, ri);
            base.moveTo(p1.dx, p1.dy);
            base.quadraticBezierTo(
              center.dx + cos(a - wedge * 0.15) * (ro * 0.75),
              center.dy + sin(a - wedge * 0.15) * (ro * 0.75),
              p2.dx, p2.dy,
            );
            base.quadraticBezierTo(
              center.dx + cos(a + wedge * 0.15) * (ro * 0.75),
              center.dy + sin(a + wedge * 0.15) * (ro * 0.75),
              p3.dx, p3.dy,
            );
            base.close();
            break;

          case 1: // écailles
            final steps = 3 + rnd.nextInt(3);
            for (int t = 0; t < steps; t++) {
              final rr = ui.lerpDouble(ri, ro, t / (steps - 1))!;
              base.addArc(
                Rect.fromCircle(center: center, radius: rr),
                a - wedge * 0.40,
                wedge * 0.80,
              );
            }
            break;

          case 2: // dentelle (arcs internes)
            final a1b = a - wedge * 0.25;
            final a2b = a + wedge * 0.25;
            final q = 2 + rnd.nextInt(3);
            for (int k = 0; k < q; k++) {
              final t = (k + 1) / (q + 1);
              final rmid = ui.lerpDouble(ri, ro, 0.55)!;
              final p1 = center + Offset.fromDirection(ui.lerpDouble(a1b, a, t)!, ri);
              final p2 = center + Offset.fromDirection(a, rmid);
              final p3 = center + Offset.fromDirection(ui.lerpDouble(a, a2b, t)!, ri);
              base.moveTo(p1.dx, p1.dy);
              base.quadraticBezierTo(
                center.dx + cos(a) * (rmid * 0.8),
                center.dy + sin(a) * (rmid * 0.8),
                p2.dx, p2.dy,
              );
              base.quadraticBezierTo(
                center.dx + cos(a) * (rmid * 0.8),
                center.dy + sin(a) * (rmid * 0.8),
                p3.dx, p3.dy,
              );
            }
            break;
        }
      }

      // Répéter autour + miroir vertical (symétrie radiale)
      void repeat(Path basePath) {
        for (int k = 0; k < symmetry; k++) {
          final ang = k * wedge;
          final m = Matrix4.identity()
            ..translate(center.dx, center.dy)
            ..rotateZ(ang)
            ..translate(-center.dx, -center.dy);
          canvas.drawPath(basePath.transform(m.storage), pen(stroke));
          final m2 = Matrix4.identity()
            ..translate(center.dx, center.dy)
            ..rotateZ(ang)
            ..scale(1, -1, 1)
            ..translate(-center.dx, -center.dy);
          canvas.drawPath(basePath.transform(m2.storage), pen(stroke));
        }
      }

      repeat(base);
      canvas.drawCircle(center, ro, pen(stroke * 0.8));
    }

    // Petits détails aléatoires
    if (addDoodles) {
      final p = pen(max(0.8, stroke * 0.7));
      final dots = (120 * density).round();
      for (int i = 0; i < dots; i++) {
        final rr = R * (0.12 + rnd.nextDouble() * 0.85);
        final a = rnd.nextDouble() * 2 * pi;
        canvas.drawCircle(center + Offset.fromDirection(a, rr), p.strokeWidth, p);
      }
    }
  }
}
