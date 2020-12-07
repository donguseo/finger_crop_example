import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:image_picker/image_picker.dart' as ip;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';

void main() => runApp(MyApp());

final kCanvasSize = 200.0;

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Offset> points = <Offset>[];
  ByteData imgBytes;
  ui.Image image;

  @override
  Widget build(BuildContext context) {
    final Container sketchArea = Container(
      margin: EdgeInsets.all(1.0),
      alignment: Alignment.topLeft,
      color: Colors.blueGrey[50],
      child: CustomPaint(
        painter: Sketcher(points, image),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Sketcher'),
      ),
      body: imgBytes != null
          ? ClipPath(
              // clipper: ImageClipper(points),
              child: Center(
                  child: Image.memory(
                Uint8List.view(imgBytes.buffer),
              )),
            )
          : GestureDetector(
              onPanUpdate: (DragUpdateDetails details) {
                setState(() {
                  RenderBox box = context.findRenderObject();
                  Offset point = box.globalToLocal(details.globalPosition);
                  point =
                      point.translate(0.0, -(AppBar().preferredSize.height));

                  points = List.from(points)..add(point);
                });
              },
              onPanEnd: (DragEndDetails details) {
                points.add(null);
              },
              child: sketchArea,
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'clear Screen',
        backgroundColor: Colors.red,
        child: Icon(Icons.refresh),
        onPressed: () {
          if (image == null) {
            getImage();
          } else if (imgBytes != null) {
            setState(() {
              image.dispose();
              image = null;
              imgBytes = null;
              points.clear();
            });
          } else {
            generateImage();
          }
        },
      ),
    );
  }

  Future<void> getImage() async {
    final imagePath =
        (await ip.ImagePicker().getImage(source: ip.ImageSource.gallery)).path;
    final tmp = await decodeImage(imagePath);
    setState(() {
      image = tmp;
    });
  }

  Future<ui.Image> decodeImage(String path) async {
    Completer<ImageInfo> completer = Completer();
    var img = new FileImage(File(path));
    img
        .resolve(ImageConfiguration())
        .addListener(ImageStreamListener((ImageInfo info, bool _) {
      completer.complete(info);
    }));
    ImageInfo imageInfo = await completer.future;
    return imageInfo.image;
  }

  void generateImage() async {
    // final color = Colors.primaries[widget.rd.nextInt(widget.numColors)];

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder,
        Rect.fromPoints(Offset(0.0, 0.0), Offset(kCanvasSize, kCanvasSize)));

    var path = Path();
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        if (i == 0) {
          path.moveTo(points[i].dx, points[i].dy);
        } else {
          path.lineTo(points[i].dx, points[i].dy);
        }
      }
    }
    canvas.clipPath(path);

    if (image != null) {
      paintImage(
          canvas: canvas, rect: Rect.fromLTRB(0, 0, 400, 400), image: image);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(400, 400);
    final pngBytes = await img.toByteData(format: ImageByteFormat.png);

    setState(() {
      imgBytes = pngBytes;
    });
  }
}

class ImageClipper extends CustomClipper<Path> {
  ImageClipper(this.points);

  List<Offset> points;
  @override
  Path getClip(ui.Size size) {
    var path = Path();
    if (points == null) {
      return path;
    }
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        if (i == 0) {
          path.moveTo(points[i].dx, points[i].dy);
        } else {
          path.lineTo(points[i].dx, points[i].dy);
        }
      }
    }
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<ui.Path> oldClipper) {
    return false;
  }
}

class Sketcher extends CustomPainter {
  final List<Offset> points;
  ui.Image image;

  Sketcher(this.points, this.image);

  @override
  bool shouldRepaint(Sketcher oldDelegate) {
    return true;
    // oldDelegate.image != image || oldDelegate.points != points;
  }

  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

    if (image != null) {
      paintImage(
          canvas: canvas, rect: Rect.fromLTRB(0, 0, 400, 400), image: image);
    }

    paint = Paint()
      ..color = Colors.black.withAlpha(200)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;
    var path = Path();

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        if (i == 0) {
          path.moveTo(points[i].dx, points[i].dy);
        } else {
          path.lineTo(points[i].dx, points[i].dy);
        }
      }
    }

    canvas.drawPath(path, paint);
  }
}
