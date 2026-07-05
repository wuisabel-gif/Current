import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fast_noise/fast_noise.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'save_image/save_image.dart';

void main() => runApp(const CurrentApp());

class CurrentApp extends StatelessWidget {
  const CurrentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CurrentScreen(),
    );
  }
}

const double _kNoiseFrequency = 0.00135;
const double _kTimeSpeed = 0.008;
const double _kHueSpread = 24;
const double _kAttractorRadius = 330;
const double _kAttractorOrbit = 0.38;
const double _kDriftStrength = 0.55;
const double _kClusterSpawnChance = 0.58;
const Color _kBackground = Color(0xFF0A0A14);

class FlowSettings {
  const FlowSettings({
    required this.particleCount,
    required this.speed,
    required this.strokeWidth,
    required this.fadeOpacity,
    required this.hueBase,
    required this.attractorPull,
  });

  final int particleCount;
  final double speed;
  final double strokeWidth;
  final double fadeOpacity;
  final double hueBase;
  final double attractorPull;

  FlowSettings copyWith({
    int? particleCount,
    double? speed,
    double? strokeWidth,
    double? fadeOpacity,
    double? hueBase,
    double? attractorPull,
  }) {
    return FlowSettings(
      particleCount: particleCount ?? this.particleCount,
      speed: speed ?? this.speed,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      fadeOpacity: fadeOpacity ?? this.fadeOpacity,
      hueBase: hueBase ?? this.hueBase,
      attractorPull: attractorPull ?? this.attractorPull,
    );
  }
}

class Particle {
  Offset pos;
  Offset prev;
  Offset velocity;
  double brightness;
  double speedScale;
  double strokeScale;

  Particle(this.pos, Random rng)
    : prev = pos,
      velocity = Offset.zero,
      brightness = 0.42 + rng.nextDouble() * 0.58,
      speedScale = 0.5 + rng.nextDouble() * 1.75,
      strokeScale = 0.4 + rng.nextDouble() * 2.1;
}

class CurrentScreen extends StatefulWidget {
  const CurrentScreen({super.key});

  @override
  State<CurrentScreen> createState() => _CurrentScreenState();
}

class _CurrentScreenState extends State<CurrentScreen>
    with SingleTickerProviderStateMixin {
  final _captureKey = GlobalKey();
  late final AnimationController _controller;
  final List<Particle> _particles = [];
  final List<Offset> _clusterCenters = [];
  final _rng = Random();
  final _noise = PerlinNoise(seed: 1337, frequency: _kNoiseFrequency);

  var _settings = const FlowSettings(
    particleCount: 8500,
    speed: 1.65,
    strokeWidth: 0.65,
    fadeOpacity: 0.022,
    hueBase: 42,
    attractorPull: 1.8,
  );

  Size _size = Size.zero;
  Offset? _attractor;
  double _t = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _controller.addListener(_step);
  }

  void _seed(Size size) {
    _particles.clear();
    _seedClusters(size);
    _addParticles(_settings.particleCount, size);
  }

  void _seedClusters(Size size) {
    _clusterCenters
      ..clear()
      ..addAll(
        List.generate(
          7,
          (_) => Offset(
            _rng.nextDouble() * size.width,
            _rng.nextDouble() * size.height,
          ),
        ),
      );
  }

  void _addParticles(int count, Size size) {
    if (_clusterCenters.isEmpty) {
      _seedClusters(size);
    }

    for (int i = 0; i < count; i++) {
      _particles.add(Particle(_spawnPoint(size), _rng));
    }
  }

  Offset _spawnPoint(Size size) {
    if (_rng.nextDouble() > _kClusterSpawnChance) {
      return Offset(
        _rng.nextDouble() * size.width,
        _rng.nextDouble() * size.height,
      );
    }

    final center = _clusterCenters[_rng.nextInt(_clusterCenters.length)];
    final radius =
        min(size.width, size.height) * (0.04 + _rng.nextDouble() * 0.19);
    final angle = _rng.nextDouble() * pi * 2;
    final distance = pow(_rng.nextDouble(), 1.9).toDouble() * radius;
    return Offset(
      (center.dx + cos(angle) * distance) % size.width,
      (center.dy + sin(angle) * distance) % size.height,
    );
  }

  void _applySettings(FlowSettings settings) {
    setState(() {
      _settings = settings;
      if (_size != Size.zero) {
        if (_particles.length > settings.particleCount) {
          _particles.removeRange(settings.particleCount, _particles.length);
        } else if (_particles.length < settings.particleCount) {
          _addParticles(settings.particleCount - _particles.length, _size);
        }
      }
    });
  }

  double _fieldAngle(double x, double y) {
    final slow = _noise.getNoise3(x, y, _t * 34);
    final detail = _noise.getNoise3(x * 2.4 + 1700, y * 2.4 - 900, _t * 22);
    final shear = sin((x * 0.0019) + (y * 0.0007) + _t * 0.9);
    return (slow * 0.72 + detail * 0.24 + shear * 0.18) * pi * 2;
  }

  void _step() {
    if (_size == Size.zero) return;
    _t += _kTimeSpeed;
    final w = _size.width;
    final h = _size.height;

    for (final p in _particles) {
      final a = _fieldAngle(p.pos.dx, p.pos.dy);
      var velocity =
          Offset(cos(a), sin(a)) * _settings.speed +
          Offset(cos(_t * 0.7), sin(_t * 0.43)) * _kDriftStrength;

      final attractor = _attractor;
      if (attractor != null) {
        final delta = attractor - p.pos;
        final distance = delta.distance;
        if (distance > 0.001 && distance < _kAttractorRadius) {
          final direction = delta / distance;
          final tangent = Offset(-direction.dy, direction.dx);
          final falloff = pow(
            1 - distance / _kAttractorRadius,
            1.45,
          ).toDouble();
          final wake = Offset(cos(_t + distance * 0.018), sin(_t * 0.8));
          velocity +=
              direction * (_settings.attractorPull * falloff) +
              tangent * (_kAttractorOrbit * falloff) +
              wake * (0.8 * falloff);
        }
      }

      p.velocity = Offset.lerp(p.velocity, velocity * p.speedScale, 0.24)!;
      var nx = p.pos.dx + p.velocity.dx;
      var ny = p.pos.dy + p.velocity.dy;

      if (nx < 0) nx += w;
      if (nx >= w) nx -= w;
      if (ny < 0) ny += h;
      if (ny >= h) ny -= h;

      final previous = p.pos;
      p.pos = Offset(nx, ny);
      final trailAmount = 1 - (_settings.fadeOpacity - 0.012) / (0.07 - 0.012);
      p.prev = p.pos - p.velocity * (2.8 + trailAmount * 8.5 * p.strokeScale);

      if ((p.pos - previous).distanceSquared > _kAttractorRadius) {
        p.prev = p.pos;
      }
    }
    setState(() {});
  }

  Future<void> _savePng() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      image.dispose();

      if (bytes == null) return;
      await saveImage(
        bytes,
        'current-${DateTime.now().millisecondsSinceEpoch}.png',
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      body: Stack(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.none,
            onHover: (event) => _attractor = event.localPosition,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _attractor = details.localPosition,
              onPanDown: (details) => _attractor = details.localPosition,
              onPanUpdate: (details) => _attractor = details.localPosition,
              onDoubleTap: () => _seed(_size),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  if (size != _size) {
                    _size = size;
                    _seed(size);
                  }
                  return RepaintBoundary(
                    key: _captureKey,
                    child: CustomPaint(
                      painter: FlowFieldPainter(
                        particles: _particles,
                        t: _t,
                        attractor: _attractor,
                        settings: _settings,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: FlowControls(
                settings: _settings,
                isSaving: _isSaving,
                onChanged: _applySettings,
                onExport: _savePng,
                onReseed: () => _seed(_size),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FlowControls extends StatelessWidget {
  const FlowControls({
    super.key,
    required this.settings,
    required this.isSaving,
    required this.onChanged,
    required this.onExport,
    required this.onReseed,
  });

  final FlowSettings settings;
  final bool isSaving;
  final ValueChanged<FlowSettings> onChanged;
  final VoidCallback onExport;
  final VoidCallback onReseed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: min(MediaQuery.sizeOf(context).width - 24, 980),
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xD9111320),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _IconAction(
            icon: Icons.download_rounded,
            label: isSaving ? 'Saving' : 'PNG',
            onPressed: isSaving ? null : onExport,
          ),
          _IconAction(
            icon: Icons.shuffle_rounded,
            label: 'Reseed',
            onPressed: onReseed,
          ),
          _ControlSlider(
            label: 'Density',
            value: settings.particleCount.toDouble(),
            min: 2500,
            max: 14000,
            divisions: 23,
            display: settings.particleCount.toString(),
            onChanged: (value) => onChanged(
              settings.copyWith(particleCount: (value / 500).round() * 500),
            ),
          ),
          _ControlSlider(
            label: 'Trails',
            value: settings.fadeOpacity,
            min: 0.012,
            max: 0.07,
            display: _trailLabel(settings.fadeOpacity),
            onChanged: (value) =>
                onChanged(settings.copyWith(fadeOpacity: value)),
          ),
          _ControlSlider(
            label: 'Pull',
            value: settings.attractorPull,
            min: 0.3,
            max: 3.2,
            display: settings.attractorPull.toStringAsFixed(1),
            onChanged: (value) =>
                onChanged(settings.copyWith(attractorPull: value)),
          ),
          _ControlSlider(
            label: 'Palette',
            value: settings.hueBase,
            min: 0,
            max: 360,
            display: settings.hueBase.round().toString(),
            onChanged: (value) => onChanged(settings.copyWith(hueBase: value)),
          ),
        ],
      ),
    );
  }

  static String _trailLabel(double fadeOpacity) {
    final amount = 1 - (fadeOpacity - 0.012) / (0.07 - 0.012);
    return '${(amount * 100).round()}%';
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFFD36A),
        foregroundColor: const Color(0xFF1B1202),
        disabledBackgroundColor: const Color(0xFF7A6840),
        disabledForegroundColor: const Color(0xFFE8D8AA),
        minimumSize: const Size(96, 38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _ControlSlider extends StatelessWidget {
  const _ControlSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const Spacer(),
              Text(
                display,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 12,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: const Color(0xFFFFD36A),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class FlowFieldPainter extends CustomPainter {
  FlowFieldPainter({
    required this.particles,
    required this.t,
    required this.attractor,
    required this.settings,
  });

  final List<Particle> particles;
  final double t;
  final Offset? attractor;
  final FlowSettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _kBackground);

    final glowPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    final linePaint = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen;

    for (final p in particles) {
      final a = atan2(p.pos.dy - p.prev.dy, p.pos.dx - p.prev.dx);
      var hue = (settings.hueBase + sin(a) * _kHueSpread + t * 12) % 360;
      if (hue < 0) hue += 360;
      final speed = (p.pos - p.prev).distance.clamp(0, 42) / 42;
      final alpha = (0.24 + speed * 0.36) * p.brightness;
      final color = HSVColor.fromAHSV(
        alpha,
        hue,
        0.62 + speed * 0.18,
        0.92 + speed * 0.08,
      ).toColor();

      glowPaint
        ..strokeWidth = settings.strokeWidth * p.strokeScale * 4.2
        ..color = color.withValues(alpha: alpha * 0.16);
      canvas.drawLine(p.prev, p.pos, glowPaint);

      linePaint
        ..strokeWidth = settings.strokeWidth * p.strokeScale
        ..color = color;
      canvas.drawLine(p.prev, p.pos, linePaint);
    }

    final focus = attractor;
    if (focus != null) {
      final pulse = 0.5 + sin(t * 8) * 0.5;
      final glow = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.18 + pulse * 0.08),
            const Color(0xFFFFB000).withValues(alpha: 0.1),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: focus, radius: 72));
      canvas.drawCircle(focus, 72, glow);

      final ring = Paint()
        ..color = const Color(0xFFFFE2A3).withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(focus, 8 + pulse * 4, ring);
    }
  }

  @override
  bool shouldRepaint(covariant FlowFieldPainter old) => true;
}
