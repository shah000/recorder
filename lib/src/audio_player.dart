import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AudioPlayer extends StatefulWidget {
  /// Path from where to play recorded audio
  final String source;

  /// Callback when audio file should be removed
  /// Setting this to null hides the delete button
  final VoidCallback onDelete;
  final void Function(String path) onSend;

  const AudioPlayer({
    super.key,
    required this.source,
    required this.onDelete,
    required this.onSend,
  });

  @override
  AudioPlayerState createState() => AudioPlayerState();
}

class AudioPlayerState extends State<AudioPlayer> {
  static const double _controlSize = 56;
  static const double _deleteBtnSize = 24;

  final _audioPlayer = ap.AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  late StreamSubscription<void> _playerStateChangedSubscription;
  late StreamSubscription<Duration?> _durationChangedSubscription;
  late StreamSubscription<Duration> _positionChangedSubscription;
  Duration? _position;
  Duration? _duration;

  @override
  void initState() {
    _playerStateChangedSubscription = _audioPlayer.onPlayerComplete.listen((
      state,
    ) async {
      await stop();
    });
    _positionChangedSubscription = _audioPlayer.onPositionChanged.listen(
      (position) => setState(() {
        _position = position;
      }),
    );
    _durationChangedSubscription = _audioPlayer.onDurationChanged.listen(
      (duration) => setState(() {
        _duration = duration;
      }),
    );

    _audioPlayer.setSource(_source);

    super.initState();
  }

  @override
  void dispose() {
    _playerStateChangedSubscription.cancel();
    _positionChangedSubscription.cancel();
    _durationChangedSubscription.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Column(
            // mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _buildControl(),
                  _buildWaveformProgress(constraints.maxWidth),
                  //  _buildSlider(constraints.maxWidth),
                ],
              ),
              const SizedBox(height: 5),
              Text(_formatDuration(_remainingDuration())),
              const SizedBox(height: 10),
              // Align(
              //   alignment: Alignment.center,
              //   child: Row(
              //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
              //     children: [
              //       IconButton(
              //         icon: const Icon(Iconsax.trash, size: _deleteBtnSize),
              //         onPressed: () {
              //           if (_audioPlayer.state == ap.PlayerState.playing) {
              //             stop().then((value) => widget.onDelete());
              //           } else {
              //             widget.onDelete();
              //           }
              //           Navigator.pop(context);
              //         },
              //       ),
              //       IconButton(
              //         icon: const Icon(Icons.send, size: _deleteBtnSize),
              //         onPressed: () => widget.onSend(widget.source),
              //       ),
              //     ],
              //   ),
              // ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '00:00';
    final total = d.inSeconds;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Duration? _remainingDuration() {
    if (_duration == null) return null;
    final pos = _position ?? Duration.zero;
    final rem = _duration! - pos;
    if (rem.isNegative) return Duration.zero;
    return rem;
  }

  Widget _buildControl() {
    Icon icon;
    Color color;

    if (_audioPlayer.state == ap.PlayerState.playing) {
      icon = const Icon(Icons.pause, color: Colors.red, size: 30);
      color = Colors.red.withValues(alpha: 0.1);
    } else {
      final theme = Theme.of(context);
      icon = Icon(Icons.play_arrow, color: theme.primaryColor, size: 30);
      color = theme.primaryColor.withValues(alpha: 0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(
            width: _controlSize,
            height: _controlSize,
            child: icon,
          ),
          onTap: () {
            if (_audioPlayer.state == ap.PlayerState.playing) {
              pause();
            } else {
              play();
            }
          },
        ),
      ),
    );
  }

  Widget _buildWaveformProgress(double widgetWidth) {
    final duration = _duration;
    final position = _position;

    final total = duration?.inMilliseconds ?? 1;
    final current = position?.inMilliseconds ?? 0;
    final progress = (current / total).clamp(0.0, 1.0);

    const int barCount = 45; // number of small bars like WhatsApp
    const double minHeight = 8;
    const double maxHeight = 25;
    const double barWidth = 3;
    const double spacing = 2;

    double width = widgetWidth - _controlSize - _deleteBtnSize * 2;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        if (duration != null) {
          final dx = details.localPosition.dx.clamp(0, width);
          final seekToMs = (dx / width) * total;
          _audioPlayer.seek(Duration(milliseconds: seekToMs.round()));
        }
      },
      child: SizedBox(
        width: 250,
        height: 36,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(barCount, (i) {
              // give a natural random height pattern like WhatsApp
              final normalized = (sin(i * 0.3) * 0.2 + 1.0);
              final h = minHeight + (maxHeight - minHeight) * normalized;

              final barProgress = (i / barCount);
              final isPlayed = barProgress <= progress;

              return Container(
                width: barWidth,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: spacing / 2),
                decoration: BoxDecoration(
                  color: isPlayed
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(50),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Future<void> play() => _audioPlayer.play(_source);

  Future<void> pause() async {
    await _audioPlayer.pause();
    setState(() {});
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    setState(() {});
  }

  Source get _source =>
      kIsWeb ? ap.UrlSource(widget.source) : ap.DeviceFileSource(widget.source);
}
