import 'dart:math';

/// Wektor 2D w lokalnej płaszczyźnie metrycznej (x = wschód, y = północ).
class Vec2 {
  const Vec2(this.x, this.y);

  final double x;
  final double y;

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);

  double dot(Vec2 o) => x * o.x + y * o.y;
  double get length => sqrt(x * x + y * y);

  Vec2 get normalized {
    final l = length;
    return l == 0 ? const Vec2(0, 0) : Vec2(x / l, y / l);
  }

  /// Obrót o +90° (w lewo od kierunku wektora).
  Vec2 get perpLeft => Vec2(-y, x);

  /// Obrót o −90° (w prawo).
  Vec2 get perpRight => Vec2(y, -x);

  @override
  String toString() => 'Vec2(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}
