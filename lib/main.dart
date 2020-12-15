import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' as ip;

import 'package:flutter/services.dart' show SystemChrome, rootBundle;
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(MyApp());
}

final radius = 40.0;
final eraserRadius = 10.0;

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
  String imagePath;
  ui.Image image;

  Completer<Color> colorPick;

  List<List<Offset>> points = <List<Offset>>[];
  List<Offset> bgePoints = <Offset>[];

  int eragerMode = 0; //0 : idle, 1 : bg erager, 2: normal erager

  double scale = 1.0;
  double _baseScaleFactor = 1.0;
  double tx = 0, ty = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Sketcher'),
        actions: [
          FlatButton(
              onPressed: () {
                generateImage();
              },
              child: Text("생성"))
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            height: 50,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  flex: 1,
                  child: FlatButton(
                    onPressed: getImage,
                    child: Text('사진 가져오기'),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: FlatButton(
                    color: eragerMode == 3 ? Colors.red : null,
                    onPressed: fingerCrop,
                    child: Text('잘라내기'),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: FlatButton(
                    color: eragerMode == 1 ? Colors.red : null,
                    onPressed: backgroundErager,
                    child: Text('배경 지우개'),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 50,
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: FlatButton(
                    color: eragerMode == 2 ? Colors.red : null,
                    onPressed: erager,
                    child: Text('지우개'),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: FlatButton(
                    onPressed: turnIntoGrayscale,
                    child: Text('흑백'),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: FlatButton(
                    onPressed: painting,
                    child: Text('painting effect'),
                  ),
                ),
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

  Offset lastPoint;

  Widget _buildImgView(BuildContext context) {
    final Container sketchArea = Container(
      margin: EdgeInsets.all(1.0),
      alignment: Alignment.topLeft,
      color: Colors.white,
      child: CustomPaint(
        painter: Sketcher(points, bgePoints, image, scale, tx, ty, eragerMode),
      ),
    );
    if (eragerMode == 0) {
      return GestureDetector(
        onScaleStart: (ScaleStartDetails detail) {
          _baseScaleFactor = scale;
          lastPoint = detail.focalPoint;
        },
        onScaleUpdate: (ScaleUpdateDetails detail) {
          setState(() {
            scale = _baseScaleFactor * detail.scale;
            tx += detail.focalPoint.dx - lastPoint.dx;
            ty += detail.focalPoint.dy - lastPoint.dy;
            lastPoint = detail.focalPoint;
          });
        },
        onScaleEnd: (ScaleEndDetails detail) {},
        child: sketchArea,
      );
    }

    return GestureDetector(
      onPanDown: (DragDownDetails details) async {
        if (eragerMode == 1) {
          return;
        }
        points.add(<Offset>[]);
        // RenderBox box = context.findRenderObject();
        // Offset point = box.globalToLocal(details.globalPosition);
      },
      onPanUpdate: (DragUpdateDetails details) async {
        RenderBox box = context.findRenderObject();
        Offset point = box.globalToLocal(details.globalPosition);
        //
        Offset trans = Offset(-tx, -ty);
        point += trans;
        point /= scale;

        setState(() {
          if (eragerMode == 1 || eragerMode == 3) {
            bgePoints.add(point);
            return;
          }
          points[points.length - 1].add(point);
        });
      },
      onPanEnd: (DragEndDetails details) async {
        if (eragerMode == 1) {
          await removeBg();
          setState(() {
            bgePoints.clear();
          });
          return;
        } else if (eragerMode == 3) {
          await deleteOutSideOfPoints();
          setState(() {
            bgePoints.clear();
          });
          return;
        }
        // points.clear();
      },
      child: sketchArea,
    );
  }

  Future<void> pickColorWithOffset(Offset point) async {
    var data = await image.toByteData();
    var index = pointToIndex(point, image);
    var color = Color.fromARGB(data.getUint8(index + 3), data.getUint8(index),
        data.getUint8(index + 1), data.getUint8(index + 2));
    colorPick.complete(color);
  }

  Future<void> getImage() async {
    if (image != null) {
      image.dispose();
      setState(() {
        image = null;
      });
    }
    points.clear();
    scale = 1.0;
    tx = 0;
    ty = 0;
    eragerMode = 0;

    imagePath =
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
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
        recorder,
        Rect.fromPoints(Offset(0.0, 0.0),
            Offset(image.width.toDouble(), image.height.toDouble())));

    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTRB(
            0, 0, image.width.toDouble(), image.height.toDouble()),
        image: image,
      );
    }

    for (var pList in points) {
      if (pList.length > 2) {
        Paint paint = Paint()
          ..color = Colors.white
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.colorDodge
          ..strokeWidth = eraserRadius;
        for (int i = 0; i < pList.length; i++) {
          if (i == 0) {
          } else {
            canvas.drawLine(pList[i - 1], pList[i], paint);
          }
        }
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(image.width, image.height);
    final pngBytes = await img.toByteData(format: ImageByteFormat.png);

    Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => ResultPage(data: pngBytes)));
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
    data.setInt32(pointToIndex(point, image), 0);
    ui.decodeImageFromPixels(data.buffer.asUint8List(), image.width,
        image.height, ui.PixelFormat.rgba8888, (result) {
      setState(() {
        image = result;
      });
    });
  }

  int pointToIndex(ui.Offset point, ui.Image img) =>
      (point.dx.toInt() * 4 + point.dy.toInt() * 4 * img.width).toInt();

  int xyToIndex(int x, int y, ui.Image img) =>
      (x * 4 + y.toInt() * 4 * img.width).toInt();

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

  backgroundErager() {
    if (eragerMode == 1) {
      setState(() {
        eragerMode = 0;
      });
    } else {
      setState(() {
        eragerMode = 1;
      });
    }
  }

  erager() {
    if (eragerMode == 2) {
      setState(() {
        eragerMode = 0;
      });
    } else {
      setState(() {
        eragerMode = 2;
      });
    }
  }

  fingerCrop() {
    if (eragerMode == 3) {
      setState(() {
        eragerMode = 0;
      });
    } else {
      setState(() {
        eragerMode = 3;
      });
    }
  }

  Future<void> removeBg() async {
    //
    try {
      ByteData data = await image.toByteData();
      Color selColor;
      if (bgePoints.length > 0) {
        selColor = await selectRefColor(
            data, image.width, image.height, bgePoints[0], radius / 2);
      }
      for (final point in bgePoints) {
        deleteCircle(
            data, point, radius / 2, selColor, image.width, image.height);
      }

      ui.decodeImageFromPixels(data.buffer.asUint8List(), image.width,
          image.height, ui.PixelFormat.rgba8888, (result) {
        setState(() {
          image = result;
        });
      });
    } catch (e) {}
  }

  Future<Color> selectRefColor(
      ByteData data, int width, int height, Offset point, double radius) async {
    var left = (point.dx - radius).toInt();
    var right = (point.dx + radius).toInt();
    var top = (point.dy - radius).toInt();
    var bottom = (point.dy + radius).toInt();

    if (left < 0) {
      left = 0;
    }

    if (top < 0) {
      top = 0;
    }

    if (right > width) {
      right = width - 1;
    }

    if (bottom > height) {
      bottom = height - 1;
    }

    int r = 0;
    int g = 0;
    int b = 0;
    int a = 0;
    int count = 0;

    for (int y = top; y < bottom; y++) {
      for (int x = left; x < right; x++) {
        var index = xyToIndex(x, y, image);
        if (index > 0 && data.lengthInBytes > index) {
          if (data.getUint8(index + 3) != 0) {
            r += data.getUint8(index);
            g += data.getUint8(index + 1);
            b += data.getUint8(index + 2);
            a += data.getUint8(index + 3);
            count++;
          }
        }
      }
    }
    return Color.fromARGB(a ~/ count, r ~/ count, g ~/ count, b ~/ count);
  }

  Future<void> deleteCircle(ByteData data, ui.Offset point, double radius,
      ui.Color selColor, int width, int height) {
    var left = (point.dx - radius).toInt();
    var right = (point.dx + radius).toInt();
    var top = (point.dy - radius).toInt();
    var bottom = (point.dy + radius).toInt();

    if (left < 0) {
      left = 0;
    }

    if (top < 0) {
      top = 0;
    }

    if (right > width) {
      right = width - 1;
    }

    if (bottom > height) {
      bottom = height - 1;
    }

    int r = selColor.red;
    int g = selColor.green;
    int b = selColor.blue;
    int a = selColor.alpha;
    int offset = 40;

    for (int y = top; y < bottom; y++) {
      for (int x = left; x < right; x++) {
        final i = xyToIndex(x, y, image);
        if (i >= 0 && i < data.lengthInBytes) {
          var pr = data.getUint8(i);
          var pg = data.getUint8(i + 1);
          var pb = data.getUint8(i + 2);
          var pa = data.getUint8(i + 3);
          if ((pr > r - offset && pr < r + offset) &&
              (pg > g - offset && pg < g + offset) &&
              (pb > b - offset && pb < b + offset) &&
              (pa > a - offset && pa < a + offset)) {
            if (calcDist(point.dx, point.dy, x, y) < radius) {
              data.setUint32(i, 0);
            }
          }
        }
      }
    }
  }

  Future<void> deleteOutSideOfPoints() async {
    try {
      ByteData data = await image.toByteData();
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          if (!isInsidePolygon(bgePoints, x, y)) {
            final i = xyToIndex(x, y, image);
            data.setUint32(i, 0);
          }
        }
      }

      ui.decodeImageFromPixels(data.buffer.asUint8List(), image.width,
          image.height, ui.PixelFormat.rgba8888, (result) {
        setState(() {
          image = result;
        });
      });
    } catch (e) {}
  }

  bool isInsidePolygon(List<Offset> path, int x, int y) {
    int counter = 0;
    int i;
    double xinters;
    Offset p1, p2;
    if (path == null || path.length == 0) {
      return false;
    }

    List<Offset> polygon = List.from(path)..add(path[0]);

    p1 = polygon[0];
    for (i = 1; i <= polygon.length; i++) {
      p2 = polygon[i % polygon.length];
      if (y > min(p1.dy, p2.dy)) {
        if (y <= max(p1.dy, p2.dy)) {
          if (x <= max(p1.dx, p2.dx)) {
            if (p1.dy != p2.dy) {
              xinters = (y - p1.dy) * (p2.dx - p1.dx) / (p2.dy - p1.dy) + p1.dx;
              if (p1.dx == p2.dx || x <= xinters) counter++;
            }
          }
        }
      }
      p1 = p2;
    }

    if (counter % 2 == 0)
      return false;
    else
      return true;
  }

  double calcDist(double dx, double dy, int x, int y) {
    return pow(pow(dx - x, 2) + pow(dy - y, 2), 0.5);
  }

  painting() async {
    //
    int rad = 1;
    int intensityLevels = 200;
    var data = await image.toByteData();
    ByteData target = ByteData(data.lengthInBytes);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        var intensityCount = List.filled(intensityLevels + 1, 0);
        var averageR = List.filled(intensityLevels + 1, 0);
        var averageG = List.filled(intensityLevels + 1, 0);
        var averageB = List.filled(intensityLevels + 1, 0);
        var averageA = 0;
        var left = (x - rad).toInt();
        var right = (x + rad).toInt();
        var top = (y - rad).toInt();
        var bottom = (y + rad).toInt();

        if (left < 0) {
          left = 0;
        }

        if (top < 0) {
          top = 0;
        }

        if (right > image.width) {
          right = image.width - 1;
        }

        if (bottom > image.height) {
          bottom = image.height - 1;
        }
        int count = 0;

        for (int yIn = top; yIn < bottom; yIn++) {
          for (int xIn = left; xIn < right; xIn++) {
            final i = xyToIndex(xIn, yIn, image);
            if (i >= 0 && i < data.lengthInBytes) {
              var pr = data.getUint8(i);
              var pg = data.getUint8(i + 1);
              var pb = data.getUint8(i + 2);
              var pa = data.getUint8(i + 3);
              int curIntensity =
                  ((pr + pg + pb) / 3 * intensityLevels / 255.0).round();
              intensityCount[curIntensity]++;
              averageR[curIntensity] += pr;
              averageG[curIntensity] += pg;
              averageB[curIntensity] += pb;
              averageA += pa;
              count++;
            }
          }
        }

        int curMax = 0;
        int maxIndex = -1;
        for (int i = 1; i < intensityLevels + 1; i++) {
          if (intensityCount[i] > curMax) {
            curMax = intensityCount[i];
            maxIndex = i;
          }
        }
        int index = xyToIndex(x, y, image);
        if (maxIndex >= 0) {
          var alpha = (averageA / count).round();
          if (alpha > 255) {
            alpha = 255;
          }
          target.setUint8(index, (averageR[maxIndex] / curMax).round());
          target.setUint8(index + 1, (averageG[maxIndex] / curMax).round());
          target.setUint8(index + 2, (averageB[maxIndex] / curMax).round());
          target.setUint8(index + 3, alpha);
        } else {
          target.setUint8(index + 0, data.getUint8(index + 0));
          target.setUint8(index + 1, data.getUint8(index + 1));
          target.setUint8(index + 2, data.getUint8(index + 2));
          target.setUint8(index + 3, data.getUint8(index + 3));
        }
      }
    }

    ui.decodeImageFromPixels(target.buffer.asUint8List(), image.width,
        image.height, ui.PixelFormat.rgba8888, (result) {
      setState(() {
        image = result;
      });
    });
  }
}

class Sketcher extends CustomPainter {
  final List<List<Offset>> pointsList;
  final List<Offset> bgePoints;
  ui.Image image;
  double scale, tx, ty;
  int eragerMode;

  Sketcher(this.pointsList, this.bgePoints, this.image, this.scale, this.tx,
      this.ty, this.eragerMode);

  @override
  bool shouldRepaint(Sketcher oldDelegate) {
    return true;
  }

  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTRB(0, 0, 400, 600));
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

    canvas.translate(tx, ty);
    canvas.scale(scale);

    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTRB(
            0, 0, image.width.toDouble(), image.height.toDouble()),
        image: image,
      );
    }

    for (int index = 0; index < pointsList.length; index++) {
      var points = pointsList[index];
      if (points.length > 2) {
        paint = Paint()
          ..color = Colors.white
          ..strokeCap = StrokeCap.round
          ..strokeWidth = eraserRadius;
        for (int i = 0; i < points.length; i++) {
          if (i == 0) {
          } else {
            canvas.drawLine(points[i - 1], points[i], paint);
          }
        }

        if (index == pointsList.length && eragerMode == 2) {
          paint = Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke;

          canvas.drawCircle(points[points.length - 1], eraserRadius / 2, paint);
        }
      }
    }

    if (bgePoints.length > 2) {
      paint = Paint()
        ..color = Colors.red.withAlpha(50)
        ..strokeCap = StrokeCap.round;
      if (eragerMode == 1) {
        paint.strokeWidth = radius;
      } else if (eragerMode == 3) {
        paint.strokeWidth = 2;
      }

      for (int i = 0; i < bgePoints.length; i++) {
        if (i == 0) {
        } else {
          canvas.drawLine(bgePoints[i - 1], bgePoints[i], paint);
        }
      }
    }
  }
}

class ResultPage extends StatelessWidget {
  final ByteData data;

  const ResultPage({Key key, this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(),
      body: InteractiveViewer(
        scaleEnabled: true,
        maxScale: 6,
        minScale: 0.5,
        child: Center(
          child: Image.memory(
            Uint8List.view(data.buffer),
            fit: BoxFit.fitHeight,
          ),
        ),
      ),
    );
  }
}
