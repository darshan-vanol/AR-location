import 'package:flutter/material.dart';

class DirectionIndicatorPainter extends CustomPainter {
  final double opacity;
  final Color color;

  DirectionIndicatorPainter({this.opacity = 0.5, this.color = Colors.blue});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final centerX = width / 2;

    // Create gradient paint for the cone
    final Paint gradientPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(opacity),
          color.withOpacity(0.0),
        ],
        stops: const [0.0, 1.0],
        center: Alignment.bottomCenter, // Changed to bottom
        radius: 1.0,
      ).createShader(Rect.fromLTWH(0, 0, width, height));

    // Create the inverted cone path
    final Path conePath = Path()
      ..moveTo(centerX, height) // Start from bottom center
      ..lineTo(0, 0) // Line to top left
      ..lineTo(width, 0) // Line to top right
      ..lineTo(centerX, height) // Back to bottom center
      ..close();

    // Draw the cone
    canvas.drawPath(conePath, gradientPaint);

    // // Draw the center line
    // final Paint linePaint = Paint()
    //   ..color = Colors.blue.withOpacity(opacity * 0.8)
    //   ..strokeWidth = 2.0
    //   ..strokeCap = StrokeCap.round;

    // canvas.drawLine(
    //   Offset(centerX, 0),
    //   Offset(centerX, height),
    //   linePaint,
    // );
  }

  @override
  bool shouldRepaint(DirectionIndicatorPainter oldDelegate) {
    return oldDelegate.opacity != opacity;
  }
}

class DirectionIndicator extends StatelessWidget {
  final double height;
  final double width;
  final double opacity;
  final Color color;

  const DirectionIndicator({
    super.key,
    this.height = 200,
    this.width = 100,
    this.opacity = 0.5,
    this.color = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: DirectionIndicatorPainter(opacity: opacity, color: color),
      ),
    );
  }
}
