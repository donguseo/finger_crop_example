import 'dart:async';
import 'dart:ffi';
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
  bool remover = false;
  Completer<Color> colorPick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Sketcher'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            height: 100,
            child: Row(
              children: [
                IconButton(onPressed: getImage, icon: Icon(Icons.photo)),
                IconButton(
                    onPressed: () {
                      setState(() {
                        if (image != null) {
                          image.dispose();
                          image = null;
                        }
                        imgBytes = null;
                        points.clear();
                      });
                    },
                    icon: Icon(Icons.refresh)),
                FlatButton(
                    onPressed: () {
                      turnIntoGrayscale();
                    },
                    child: Text("흑백")),
                FlatButton(
                    onPressed: () async {
                      Color color = await pickColor(context);
                      deleteColorFromImage(
                          color.red, color.green, color.blue, color.alpha);
                    },
                    child: Text("투명")),
                IconButton(
                    onPressed: () {
                      setState(() {
                        remover = !remover;
                      });
                    },
                    icon: Icon(
                      Icons.remove,
                      color: (remover) ? Colors.red : null,
                    )),
                IconButton(onPressed: generateImage, icon: Icon(Icons.send)),
              ],
            ),
          ),
          Flexible(
              flex: 1,
              child: Builder(builder: (context) {
                return _buildImgView(context);
              })),
        ],
      ),
    );
  }

  Widget _buildImgView(BuildContext context) {
    final Container sketchArea = Container(
      margin: EdgeInsets.all(1.0),
      alignment: Alignment.topLeft,
      color: Colors.blueGrey[50],
      child: CustomPaint(
        painter: Sketcher(points, image),
      ),
    );
    return imgBytes != null
        ? Center(
            child: Image.memory(
            Uint8List.view(imgBytes.buffer),
          ))
        : GestureDetector(
            onPanDown: (DragDownDetails details) async {
              if (colorPick != null && !colorPick.isCompleted) {
                RenderBox box = context.findRenderObject();
                Offset point = box.globalToLocal(details.globalPosition);
                await pickColorWithOffset(point);
                colorPick = null;
                return;
              }
            },
            onPanUpdate: (DragUpdateDetails details) async {
              RenderBox box = context.findRenderObject();
              Offset point = box.globalToLocal(details.globalPosition);

              if (remover) {
                deleteImage(point);
                return;
              }
              setState(() {
                // points = List.from(points)..add(point);
              });
            },
            onPanEnd: (DragEndDetails details) {
              points.add(null);
            },
            child: sketchArea,
          );
  }

  Future<void> pickColorWithOffset(Offset point) async {
    var data = await image.toByteData();
    var index = pointToIndex(point);
    var color = Color.fromARGB(data.getUint8(index + 3), data.getUint8(index),
        data.getUint8(index + 1), data.getUint8(index + 2));
    colorPick.complete(color);
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
    if (!path.getBounds().isEmpty) {
      canvas.clipPath(path);
    }

    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTRB(0, 0, 400, 400),
        image: image,
      );
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(400, 400);
    final pngBytes = await img.toByteData(format: ImageByteFormat.png);

    setState(() {
      imgBytes = pngBytes;
    });
  }

  Future<void> deleteColorFromImage(int r, int g, int b, int a,
      {int offset = 20}) async {
    ByteData data = await image.toByteData();
    int length = data.lengthInBytes;
    for (int i = 0; i < length / 4; i++) {
      var pr = data.getUint8(i * 4);
      var pg = data.getUint8(i * 4 + 1);
      var pb = data.getUint8(i * 4 + 2);
      var pa = data.getUint8(i * 4 + 3);
      if ((pr > r - offset && pr < r + offset) &&
          (pg > g - offset && pg < g + offset) &&
          (pb > b - offset && pb < b + offset) &&
          (pa > a - offset && pa < a + offset)) {
        data.setUint32(i * 4, 0);
      }
    }
    ui.decodeImageFromPixels(data.buffer.asUint8List(), image.width,
        image.height, ui.PixelFormat.rgba8888, (result) {
      setState(() {
        image = result;
      });
    });
  }

  Future<void> deleteImage(Offset point) async {
    ByteData data = await image.toByteData();
    data.setInt32(pointToIndex(point), 0);
    ui.decodeImageFromPixels(data.buffer.asUint8List(), image.width,
        image.height, ui.PixelFormat.rgba8888, (result) {
      setState(() {
        image = result;
      });
    });
  }

  int pointToIndex(ui.Offset point) =>
      (point.dx.toInt() * 4 + point.dy.toInt() * 4 * image.width).toInt();

  Future<void> turnIntoGrayscale() async {
    ByteData data = await image.toByteData();
    int length = data.lengthInBytes;
    for (int i = 0; i < length / 4; i++) {
      var pr = data.getUint8(i * 4);
      var pg = data.getUint8(i * 4 + 1);
      var pb = data.getUint8(i * 4 + 2);
      var avg = ((pr + pg + pb) ~/ 3);
      data.setUint8(i * 4, avg);
      data.setUint8(i * 4 + 1, avg);
      data.setUint8(i * 4 + 2, avg);
    }
    ui.decodeImageFromPixels(data.buffer.asUint8List(), image.width,
        image.height, ui.PixelFormat.rgba8888, (result) {
      setState(() {
        image = result;
      });
    });
  }

  Future<Color> pickColor(BuildContext context) {
    colorPick = Completer();
    return colorPick.future;
  }
}

class Sketcher extends CustomPainter {
  final List<Offset> points;
  ui.Image image;

  Sketcher(this.points, this.image);

  @override
  bool shouldRepaint(Sketcher oldDelegate) {
    return true;
  }

  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTRB(
            0, 0, image.width.toDouble(), image.height.toDouble()),
        image: image,
      );
    }

    paint = Paint()
      ..color = Colors.black.withAlpha(20)
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
