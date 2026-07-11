import 'package:flutter/material.dart';

class RadarBrandTitle extends StatelessWidget {
  final Color textColor;
  final double logoHeight;
  final double leftPadding;

  const RadarBrandTitle({
    super.key,
    this.textColor = Colors.black,
    this.logoHeight = 24,
    this.leftPadding = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: leftPadding, right: 8),
          child: Image.asset(
            'assets/Radarlogo.png',
            height: logoHeight,
            errorBuilder: (ctx, err, st) =>
                SizedBox(width: logoHeight, height: logoHeight),
          ),
        ),
        Text(
          'RADAR',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: textColor,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}
