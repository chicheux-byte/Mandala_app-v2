import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

void main() {
  runApp(const MandalaApp());
}

class MandalaApp extends StatelessWidget {
  const MandalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mandala Generator',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MandalaHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MandalaHomePage extends StatefulWidget {
  const MandalaHomePage({super.key});

  @override
  State<MandalaHomePage> createState() => _MandalaHomePageState();
}

class _MandalaHomePageState extends State<MandalaHomePage> {
  int symmetry = 8;
  int complexity = 6;
  double strokeWidth = 2.0;
  String style = "Pastel";
  GlobalKey mandalaKey = GlobalKey();

  final Map<String, List<Color>> palettes = {
    "Pastel": [
      Colors.pink.shade200,
      Colors.blue.shade200,
      Colors.green.shade200,
      Colors.yellow.shade200
    ],
    "Acrylique": [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.yellow
    ],
    "Mat": [
      Colors.brown,
      Colors.teal,
      Colors.indigo,
      Colors.grey
    ],
    "Flash": [
      Colors.pink,
      Colors.cyan,
      Colors.lime,
      Colors.amber
    ],
  };

  List<Color> currentPalette = [];

  @override
  void initState() {
    super.initState();
    currentPalette = palettes[style]!;
  }

  void generateRandomPalette() {
    final rand = Random();
    currentPalette = List.generate(
      4,
      (_) => Color.fromARGB(255, rand.nextInt(256), rand.nextInt(256), rand.nextInt(256)),
    );
  }

  void changeStyle(String newStyle) {
    setState(() {
      style = newStyle;
      if (newStyle == "Auto") {
        generateRandomPalette();
      } else {
        currentPalette = palettes[newStyle]!;
      }
    });
  }

  Future<void> shareMandala() async {
    try {
      RenderRepaintBoundary boundary =
          mandalaKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/mandala.png').create();
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles([XFile(file.path)], text: 'Mon mandala 🎨');
    } catch (e) {
      debugPrint("Erreur partage : $e");
    }
  }

  Future<void> saveMandala() async {
    try {
      RenderRepaintBoundary boundary =
          mandalaKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final dir = await getApplicationDocumentsDirectory();
      final file = await File('${dir.path}/mandala_${DateTime.now().millisecondsSinceEpoch}.png').create();
      await file.writeAsBytes(pngBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mandala enregistré dans la galerie interne 📂")),
      );
    } catch (e) {
      debugPrint("Erreur sauvegarde : $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mandala Generator"),
        actions: [
          IconButton(onPressed: saveMandala, icon: const Icon(Icons.download)),
          IconButton(onPressed: shareMandala, icon: const Icon(Icons.share)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RepaintBoundary(
              key: mandalaKey,
              child: CustomPaint(
                painter: MandalaPainter(symmetry, complexity, strokeWidth, currentPalette),
                child: Container(color: Colors.white),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                DropdownButton<String>(
                  value: style,
                  items: ["Pastel", "Acrylique", "Mat", "Flash", "Auto"]
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (val) => changeStyle(val!),
                ),
                Row(
                  children: [
                    const Text("Symmetry"),
                    Expanded(
                      child: Slider(
                        min: 4,
                        max: 36,
                        divisions: 32,
                        value: symmetry.toDouble(),
                        onChanged: (val) => setState(() => symmetry = val.toInt()),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text("Complexité"),
                    Expanded(
                      child: Slider(
                        min: 2,
                        max: 12,
                        divisions: 10,
                        value: complexity.toDouble(),
                        onChanged: (val) => setState(() => complexity = val.toInt()),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text("Épaisseur"),
                    Expanded(
                      child: Slider(
                        min: 0.5,
                        max: 6.0,
                        value: strokeWidth,
                        onChanged: (val) => setState(() => strokeWidth = val),
                      ),
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

class MandalaPainter extends CustomPainter {
  final int symmetry;
  final int complexity;
  final double strokeWidth;
  final List<Color> colors;

  MandalaPainter(this.symmetry, this.complexity, this.strokeWidth, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 * 0.9;
    final angleStep = (2 * pi) / symmetry;
    final rand = Random();

    for (int i = 0; i < complexity; i++) {
      paint.color = colors[rand.nextInt(colors.length)];
      final path = Path();
      path.moveTo(center.dx, center.dy);
      for (int s = 0; s < symmetry; s++) {
        double angle = s * angleStep;
        double x = center.dx + radius * cos(angle + (i * 0.1));
        double y = center.dy + radius * sin(angle + (i * 0.1));
        path.lineTo(x, y);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
