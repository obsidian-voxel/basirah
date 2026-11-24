import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../services/blur_engine.dart';
import '../services/native_bridge.dart';
import '../src/blur_painter.dart';
import '../src/detection_data.dart';
import '../src/detection_engine.dart';
import '../src/policy.dart';
import 'blockp_icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// Import an image, run the on-device cascade, preview the blur and save a
/// blurred copy. This is the feature the old build advertised but never had.
class ImageLabScreen extends StatefulWidget {
  const ImageLabScreen({super.key});

  @override
  State<ImageLabScreen> createState() => _ImageLabScreenState();
}

class _ImageLabScreenState extends State<ImageLabScreen> {
  static const int _maxSide = 1600;

  final DetectionEngine _engine = DetectionEngine();
  final ImagePicker _picker = ImagePicker();

  ui.Image? _source;              // For display
  img.Image? _sourceImg;          // For saving (package:image type)
  List<BlurRegion> _regions = const [];
  FrameResult? _frame;
  bool _loading = false;
  bool _picking = false;
  String? _error;
  String? _savedPath;
  bool _showOriginal = false;
  LiveCapture? _capture;
  bool _captureLoading = false;

  @override
  void initState() {
    super.initState();
    // Warm the model while the user is still choosing an image.
    _engine.initialize();
    _refreshCapture();
  }

  /// Pulls the last screenshot the protection service analysed, so a missed
  /// blur can be inspected without a debugger.
  Future<void> _refreshCapture() async {
    if (_captureLoading || !nativeBridge.isSupported) return;
    setState(() => _captureLoading = true);
    final capture = await nativeBridge.lastCapture();
    if (!mounted) return;
    setState(() {
      _capture = capture;
      _captureLoading = false;
    });
  }

  Future<void> _copyCaptureLog() async {
    final log = await nativeBridge.captureLog();
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(
      text: log.isEmpty ? 'No captures logged yet.' : log,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(log.isEmpty
            ? 'No captures logged yet.'
            : 'Copied the last ${log.split('\n').length} capture lines'),
      ));
  }

  @override
  void dispose() {
    _source?.dispose();
    _engine.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_picking || _loading) return;
    setState(() => _picking = true);
    try {
      final bytes = await _loadBytes(source);
      if (bytes != null) await _analyze(bytes);
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  /// Android goes straight to the system document picker and camera app.
  /// image_picker's camera path needs a `<queries>` entry to see any camera on
  /// Android 11+ and returned "no_available_camera" without one, so the native
  /// intents are used there; iOS keeps the plugin.
  Future<Uint8List?> _loadBytes(ImageSource source) async {
    if (nativeBridge.isSupported) {
      return source == ImageSource.camera
          ? await nativeBridge.takePhoto()
          : await nativeBridge.pickImage();
    }
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
    );
    return file?.readAsBytes();
  }

  Future<void> _analyze(Uint8List bytes) async {
    setState(() {
      _loading = true;
      _error = null;
      _savedPath = null;
    });
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const FormatException('Unsupported or corrupt image file.');
      }
      final oriented = img.bakeOrientation(decoded);
      final prepared = _downscale(oriented, _maxSide);

      await _engine.initialize();
      // Live ML Kit face boxes, normalised to the picked image so the
      // downscaled copy can reuse them.
      final normalisedFaces = nativeBridge.isSupported
          ? await nativeBridge.detectFaces(bytes)
          : const <Rect>[];
      final faces = [
        for (final face in normalisedFaces)
          Rect.fromLTRB(
            face.left * prepared.width,
            face.top * prepared.height,
            face.right * prepared.width,
            face.bottom * prepared.height,
          ),
      ];
      final frame = await _engine.analyze(prepared, faces: faces);
      final regions = BlurPolicy(blurEngine.config).apply(frame);
      final source = await _toUiImage(prepared);

      if (!mounted) {
        source.dispose();
        return;
      }
      setState(() {
        _source?.dispose();
        _source = source;
        _sourceImg = prepared;
        _frame = frame;
        _regions = regions;
        _showOriginal = false;
        _loading = false;
      });

      if (regions.isNotEmpty) {
        final wholeFrame = regions.any((r) => r.kind == BlurKind.nudity);
        await blurEngine.recordBlur(
          packageName: 'com.haramblur.haram_blur',
          reason: wholeFrame ? 'nsfw' : 'exposure',
          confidence: regions
              .map((r) => r.confidence)
              .reduce((a, b) => a > b ? a : b),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  img.Image _downscale(img.Image image, int maxSide) {
    final longest = max(image.width, image.height);
    if (longest <= maxSide) return image;
    final scale = maxSide / longest;
    return img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  Future<ui.Image> _toUiImage(img.Image image) async {
    final png = img.encodePng(image);
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(png),
      targetWidth: image.width,
      targetHeight: image.height,
    );
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  Future<void> _save() async {
    final sourceImg = _sourceImg;
    if (sourceImg == null) return;
    final directory = await nativeBridge.appDocumentsDirectory();
    final file = File(
      '$directory/haram_blur_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(img.encodePng(sourceImg));
    if (!mounted) return;
    setState(() => _savedPath = file.path);
  }

  void _reset() {
    setState(() {
      _source?.dispose();
      _source = null;
      _sourceImg = null;
      _regions = const [];
      _frame = null;
      _error = null;
      _savedPath = null;
      _showOriginal = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image lab'),
        centerTitle: false,
        actions: [
          if (_source != null)
            IconButton(
              tooltip: 'Start over',
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionTitle(
            'Blur an image',
            subtitle:
                'Analysed fully on this device with the same models the '
                'screen service uses. Images are kept in memory.',
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading || _picking
                      ? null
                      : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(_picking ? 'Opening…' : 'From gallery'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading || _picking
                      ? null
                      : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (nativeBridge.isSupported) ...[
            _LiveCaptureCard(
              capture: _capture,
              loading: _captureLoading,
              onRefresh: _refreshCapture,
              onCopyLog: _copyCaptureLog,
            ),
            const SizedBox(height: 20),
          ],
          if (_loading) const _LoadingCard(),
          if (_error != null) _ErrorCard(message: _error!, onRetry: _reset),
          if (!_loading && _error == null && _source == null)
            const EmptyState(
              icon: Icons.image_outlined,
              title: 'Pick an image to process',
              message:
                  'Nudity is blocked for the whole Frame; uncovered awrah '
                  'bands are blurred for every person equally.',
            ),
          if (!_loading && _source != null) ..._result(context),
        ],
      ),
    );
  }

  List<Widget> _result(BuildContext context) {
    final source = _source!;
    final frame = _frame;
    final wholeFrame = _regions.any((r) => r.kind == BlurKind.nudity);

    return [
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: source.width / source.height,
          child: _showOriginal
              ? RawImage(image: source, fit: BoxFit.cover)
              : CustomPaint(
                  painter: BlurPainter(source: source, regions: _regions),
                  child: const SizedBox.expand(),
                ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Blurred')),
                ButtonSegment(value: true, label: Text('Original')),
              ],
              selected: {_showOriginal},
              onSelectionChanged: (value) =>
                  setState(() => _showOriginal = value.first),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      AppCard(
        color: wholeFrame
            ? AppColors.danger.withValues(alpha: 0.08)
            : AppColors.success.withValues(alpha: 0.08),
        borderColor: (wholeFrame ? AppColors.danger : AppColors.success)
            .withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _regions.isEmpty
                  ? 'Nothing to blur'
                  : wholeFrame
                      ? 'Whole frame blocked'
                      : '${_regions.length} region(s) blurred',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: context.paletteInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _regions.isEmpty
                  ? 'No nudity or uncovered awrah band was found at the '
                      'current sensitivity.'
                  : _regions.map((r) => r.evidence).toSet().join(' · '),
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: context.paletteMuted,
              ),
            ),
            if (frame != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill.withIcon(
                    Icons.analytics_outlined,
                    label: 'Nudity score ${(frame.nsfwScore * 100).round()}%',
                    color: AppColors.primary,
                  ),
                  StatusPill(
                    icon: BpAbstractIcon(
                      BpAbstractIcon.viewfinder,
                      size: 14,
                      color: AppColors.accent,
                      strokeWidth: 2.4,
                    ),
                    label: 'People detected ${frame.persons.length}',
                    color: AppColors.accent,
                  ),
                  StatusPill.withIcon(
                    Icons.tune,
                    label: 'Gate ${(blurEngine.config.nsfwFrameGate * 100).round()}%',
                    color: AppColors.warning,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _regions.isEmpty ? null : _save,
        icon: const Icon(Icons.save_alt),
        label: const Text('Save blurred copy'),
      ),
      if (_savedPath != null) ...[
        const SizedBox(height: 8),
        Text(
          'Saved to $_savedPath',
          style: TextStyle(fontSize: 12, color: context.paletteMuted),
        ),
      ],
      const SizedBox(height: 12),
      Text(
        'Processed at up to $_maxSide px on the long edge to keep memory use '
        'predictable.',
        style: TextStyle(fontSize: 12, color: context.paletteMuted),
      ),
      const SizedBox(height: 16),
      if (_frame != null)
        _DebugPanel(
          frame: _frame,
          regions: _regions,
          config: blurEngine.config,
        ),
    ];
  }
}

/// Shows exactly what the screen pipeline received and decided: dimensions,
/// row padding, gate score, exposed ratio, decision and region count.
class _LiveCaptureCard extends StatelessWidget {
  final LiveCapture? capture;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onCopyLog;

  const _LiveCaptureCard({
    required this.capture,
    required this.loading,
    required this.onRefresh,
    required this.onCopyLog,
  });

  Color _decisionColor(BuildContext context) {
    return switch (capture?.decision) {
      'blur' => AppColors.success,
      'clean' => AppColors.primary,
      'engine_error' => AppColors.danger,
      _ => AppColors.muted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final live = capture;
    return AppCard(
      color: AppColors.primary.withValues(alpha: 0.05),
      borderColor: AppColors.primary.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.screenshot_monitor,
                  size: 18, color: context.paletteInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Live capture',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: context.paletteInk,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          if (live == null)
            Text(
              'No screen capture yet. Enable protection and switch to an app.',
              style: TextStyle(fontSize: 13, color: context.paletteMuted),
            )
          else ...[
            if (live.preview != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Center(
                    child: Image.memory(
                      live.preview!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill.withIcon(
                  Icons.aspect_ratio,
                  label: '${live.width}×${live.height}',
                  color: AppColors.primary,
                ),
                StatusPill.withIcon(
                  Icons.view_column_outlined,
                  label: 'rowPadding ${live.rowPadding}px',
                  color: live.rowPadding > 0
                      ? AppColors.warning
                      : AppColors.success,
                ),
                StatusPill.withIcon(
                  Icons.analytics_outlined,
                  label: 'Gate ${(live.score * 100).round()}% '
                      '/ ${(live.gate * 100).round()}%',
                  color: AppColors.accent,
                ),
                StatusPill(
                  icon: BpAbstractIcon(
                    BpAbstractIcon.ratio,
                    size: 14,
                    color: AppColors.warning,
                    strokeWidth: 2.4,
                  ),
                  label: 'Exposed ${(live.exposed * 100).round()}%',
                  color: AppColors.warning,
                ),
                StatusPill.withIcon(
                  Icons.visibility_off_outlined,
                  label: '${live.decision} · ${live.regions} region(s)',
                  color: _decisionColor(context),
                ),
                StatusPill.withIcon(
                  Icons.timer_outlined,
                  label: '${live.elapsedMs} ms',
                  color: AppColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${live.packageName} · full-frame score '
              '${(live.fullScore * 100).round()}% · ${live.persons} person(s)',
              style: TextStyle(fontSize: 12, color: context.paletteMuted),
            ),
            if (live.detectorError != null)
              Text(
                'Detector: ${live.detectorError}',
                style: const TextStyle(fontSize: 12, color: AppColors.danger),
              ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: onCopyLog,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copy logs'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebugPanel extends StatelessWidget {
  final FrameResult? frame;
  final List<BlurRegion> regions;
  final BlurConfig config;

  const _DebugPanel({
    required this.frame,
    required this.regions,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    if (frame == null) return const SizedBox.shrink();

    return AppCard(
      color: AppColors.warning.withValues(alpha: 0.08),
      borderColor: AppColors.warning.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Debug — pipeline stages',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF92400E),
            ),
          ),
          const SizedBox(height: 10),
          ...[
            _StatTile.withIcon(
              Icons.analytics_outlined,
              label: 'NSFW gate score',
              value: '${(frame!.nsfwScore * 100).round()}%',
              color: AppColors.primary,
            ),
            _StatTile.withIcon(
              Icons.tune,
              label: 'NSFW threshold',
              value: '${(config.nsfwFrameGate * 100).round()}%',
              color: AppColors.primary,
            ),
            _StatTile(
              icon: BpAbstractIcon(
                BpAbstractIcon.viewfinder,
                size: 16,
                color: AppColors.accent,
                strokeWidth: 2.2,
              ),
              label: 'People detected',
              value: '${frame!.persons.length}',
              color: AppColors.accent,
            ),
            ...frame!.persons.asMap().entries.map((e) {
              final i = e.key;
              final p = e.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Person ${i + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _StatTile.withIcon(
                    Icons.layers,
                    label: 'Awrah band skin',
                    value: '${(p.awrahSkinFraction * 100).round()}% (thresh ${(config.awrahSkinThreshold * 100).round()}%)',
                    color: AppColors.warning,
                  ),
                  _StatTile(
                    icon: BpAbstractIcon(
                      BpAbstractIcon.ratio,
                      size: 16,
                      color: AppColors.warning,
                      strokeWidth: 2.2,
                    ),
                    label: 'Exposed skin ratio',
                    value: '${(p.exposedRatio * 100).round()}% (thresh ${(config.skinThreshold * 100).round()}%)',
                    color: AppColors.warning,
                  ),
                  _StatTile.withIcon(
                    Icons.aspect_ratio,
                    label: 'Box size',
                    value: '${p.box.width.round()}×${p.box.height.round()}',
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: 8),
                ],
              );
            }),
            ...regions.map((r) {
              return _StatTile.withIcon(
                Icons.blur_on,
                label: 'Blur region: ${r.kind.name}',
                value: '${(r.confidence * 100).round()}%',
                color: AppColors.primary,
              );
            }),
          ].expand((w) => [w, const SizedBox(height: 6)]),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Widget icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  /// A tile whose leading glyph is a Material icon.
  _StatTile.withIcon(
    IconData iconData, {
    required this.label,
    required this.value,
    required this.color,
  }) : icon = Icon(iconData, size: 16, color: color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        icon,
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: 14),
          Text(
            'Running the on-device models…',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.paletteInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The first run also loads the 88 MB classifier, which can take a '
            'few seconds on older phones.',
            style: TextStyle(fontSize: 12, color: context.paletteMuted),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.danger.withValues(alpha: 0.08),
      borderColor: AppColors.danger.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analysis failed',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.paletteInk,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(fontSize: 13, color: context.paletteMuted),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
