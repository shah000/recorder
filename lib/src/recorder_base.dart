// ignore_for_file: unused_element, unused_local_variable, use_build_context_synchronously

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:recorder/src/audio_player.dart' show AudioPlayer;

class Recorder extends StatefulWidget {
  final void Function(String path) onStop;
  final void Function(String path) onSend;

  const Recorder({super.key, required this.onStop, required this.onSend});

  @override
  State<Recorder> createState() => _RecorderState();
}

class _RecorderState extends State<Recorder>
    with AudioRecorderMixin, TickerProviderStateMixin {
  int _recordDuration = 0;
  int _pausedDuration = 0; // Track accumulated duration during pauses
  Timer? _timer;
  late final AudioRecorder _audioRecorder;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  StreamSubscription<Amplitude>? _amplitudeSub;

  Timer? _autoStopTimer; // 🔹 Add this line
  final ValueNotifier<Amplitude> amplitudeNotifier = ValueNotifier(
    Amplitude(current: 0, max: 0),
  );
  String? audioPath;
  int? _recordedDuration;

  @override
  void initState() {
    super.initState();

    _audioRecorder = AudioRecorder();

    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });

    _amplitudeSub = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 300))
        .listen((amp) {
          amplitudeNotifier.value = amp;
        });

    // 👇 Auto start recording after init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _start();
    });
  }

  Future<void> _start() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        const encoder = AudioEncoder.aacLc;

        if (!await _isEncoderSupported(encoder)) {
          return;
        }

        final devs = await _audioRecorder.listInputDevices();
        debugPrint(devs.toString());

        const config = RecordConfig(encoder: encoder, numChannels: 1);

        // Record to file
        await recordFile(_audioRecorder, config);

        // Record to stream
        // await recordStream(_audioRecorder, config);

        _recordDuration = 0;

        _startTimer();
        // 🔹 Automatically stop after 30 seconds
        _autoStopTimer?.cancel();
        _autoStopTimer = Timer(const Duration(seconds: 30), () async {
          final path = await _audioRecorder.stop();
          // capture duration before any state reset
          _recordedDuration = _recordDuration;
          if (!mounted) return;
          setState(() {
            _recordState = RecordState.stop;
            audioPath = path;
          });
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  // Future<void> _stop() async {
  //   _autoStopTimer?.cancel(); // 🔹 Cancel auto-stop timer

  //   final path = await _audioRecorder.stop();

  //   if (path != null) {
  //     // save the recorded duration before any listeners reset it
  //     _recordedDuration = _recordDuration;
  //     setState(() {
  //       _recordState = RecordState.stop;
  //       audioPath = path;
  //     });
  //     final formattedTime =
  //         '${_formatNumber((_recordedDuration ?? _recordDuration) ~/ 60)}:${_formatNumber((_recordedDuration ?? _recordDuration) % 60)}';

  //     // widget.onStop('$path|$formattedTime'); // send both path and time

  //     // widget.onStop(path);
  //     // Navigator.pop(context);
  //     // downloadWebData(path);
  //   }
  // }

  Future<void> _send() async {
    _autoStopTimer?.cancel(); // 🔹 Cancel auto-stop timer
    // Capture final duration before any state changes triggered by stop()
    final int capturedDuration =
        _recordedDuration ??
        (_recordState == RecordState.pause ? _pausedDuration : _recordDuration);

    // If already stopped, use audioPath, otherwise stop recording now
    String? path = audioPath;
    if (path == null) {
      final stoppedPath = await _audioRecorder.stop();
      path = stoppedPath;
      // store captured duration so UI/other handlers can use it
      _recordedDuration = capturedDuration;
      if (path != null && mounted) {
        setState(() {
          _recordState = RecordState.stop;
          audioPath = path;
        });
      }
    }

    if (path != null) {
      // Format the captured duration
      final formattedTime =
          '${_formatNumber(capturedDuration ~/ 60)}:${_formatNumber(capturedDuration % 60)}';

      // Send the path and correct duration
      widget.onSend('$path|$formattedTime');

      if (mounted) {
        Navigator.pop(context);
      }
      downloadWebData(path);
    }
  }

  Future<void> _onlystop() async {
    _autoStopTimer?.cancel(); // 🔹 Cancel auto-stop timer
    // Capture duration before stopping to avoid race with state-change events
    final int capturedDuration = _recordDuration;

    final path = await _audioRecorder.stop();

    if (path != null) {
      _recordedDuration = capturedDuration;
      final formattedTime =
          '${_formatNumber(capturedDuration ~/ 60)}:${_formatNumber(capturedDuration % 60)}';

      widget.onStop('$path|$formattedTime'); // send both path and time
      // widget.onStop(path);
      // Navigator.pop(context);
      downloadWebData(path);
    }
  }

  Future<void> _pause() async {
    _autoStopTimer?.cancel(); // 🔹 Cancel auto-stop timer

    await _audioRecorder.pause();
  }

  Future<void> _stop() async {
    _autoStopTimer?.cancel(); // 🔹 Cancel auto-stop timer
    // Capture duration before stopping to avoid race with state-change events
    final int capturedDuration = _recordDuration;

    final path = await _audioRecorder.stop();

    if (path != null) {
      _recordedDuration = capturedDuration;
      setState(() {
        _recordState = RecordState.stop;
        audioPath = path;
      });
    }
  }

  Future<void> _resume() async {
    await _audioRecorder.resume();
    // Don't reset duration on resume, continue from paused duration
    _startTimer();
  }

  void _updateRecordState(RecordState recordState) {
    setState(() => _recordState = recordState);

    switch (recordState) {
      case RecordState.pause:
        _timer?.cancel();
        _pausedDuration = _recordDuration; // Store duration when pausing
        break;
      case RecordState.record:
        if (_pausedDuration > 0) {
          _recordDuration = _pausedDuration; // Restore duration when resuming
        }
        _startTimer();
        break;
      case RecordState.stop:
        _timer?.cancel();
        _recordDuration = 0;
        _pausedDuration = 0;
        break;
    }
  }

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder.isEncoderSupported(encoder);

    if (!isSupported) {
      debugPrint('${encoder.name} is not supported on this platform.');
      debugPrint('Supported encoders are:');

      for (final e in AudioEncoder.values) {
        if (await _audioRecorder.isEncoderSupported(e)) {
          debugPrint('- ${e.name}');
        }
      }
    }

    return isSupported;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          SizedBox(
            // color: Colors.amber,
            width: MediaQuery.of(context).size.width,
            height: 150,
            child: audioPath != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: AudioPlayer(
                      source: audioPath!,
                      onDelete: () {
                        // clear preview and reset recorder state
                        setState(() {
                          audioPath = null;
                          _recordedDuration = null;
                          _recordDuration = 0;
                          _recordState = RecordState.stop;
                        });
                        if (mounted) Navigator.pop(context);
                      },
                      onSend: (path) {
                        final dur = _recordedDuration ?? _recordDuration;
                        final formattedTime =
                            '${_formatNumber(dur ~/ 60)}:${_formatNumber(dur % 60)}';
                        widget.onSend('$path|$formattedTime');
                        if (mounted) Navigator.pop(context);
                        downloadWebData(path);
                      },
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 25),
                    child: Column(
                      children: [
                        _buildText(),
                        // _buildPauseResumeControl(),
                        const SizedBox(height: 19),
                      ],
                    ),
                  ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              //color: Colors.amber,
              width: MediaQuery.of(context).size.width,
              // height: 60,
              child: Padding(
                padding: const EdgeInsets.only(right: 10, left: 5),
                child: Row(
                  // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: IconButton(
                        onPressed: () async {
                          await _audioRecorder.stop();

                          Navigator.pop(context);
                          FocusScope.of(
                            context,
                          ).unfocus(); // This line unfocuses the current element
                        },
                        icon: const Icon(Icons.delete),
                      ),
                    ),
                    const Spacer(),
                    _recordState == RecordState.pause
                        ? IconButton(
                            onPressed: () async {
                              // start recording again (will check permissions)
                              await _stop();
                            },
                            icon: const Icon(
                              Icons.stop,
                              color: Colors.red,
                              size: 30,
                            ),
                          )
                        : const SizedBox(),
                    const SizedBox(width: 10),
                    audioPath != null
                        ? IconButton(
                            onPressed: () async {
                              // Clear preview and restart recording so the wave UI returns
                              setState(() {
                                audioPath = null;
                                _recordedDuration = null;
                                _recordDuration = 0;
                                _recordState = RecordState.record;
                              });

                              // start recording again (will check permissions)
                              await _start();
                            },
                            icon: const Icon(
                              Icons.mic_outlined,
                              color: Colors.red,
                              size: 30,
                            ),
                          )
                        : _buildPauseResumeControl(),
                    const Spacer(),
                    _buildRecordStopControl(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordSub?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder.dispose();
    _autoStopTimer?.cancel(); // 🔹 Clean up timer
    super.dispose();
  }

  Widget _buildRecordStopControl() {
    late Icon icon;
    late Color color;

    if (_recordState != RecordState.stop || _recordState != RecordState.pause) {
      icon = const Icon(Icons.send, size: 20);
      color = Colors.green.withValues(alpha: 0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 45, height: 45, child: icon),
          onTap: () async {
            // if ((_recordState != RecordState.stop ||
            //     _recordState != RecordState.pause)) {}
            await _send();

            // : _start();
          },
        ),
      ),
    );
  }

  // Widget _buildLiveWave(Amplitude amp) {
  //   double normalized = (amp.current) / 100; // normalize
  //   normalized = normalized.clamp(0.2, 1.0); // keep visible at low sound
  //   const double totalHeight = 90; // fixed container height (adjust if desired)
  //   const double minBar = 10;
  //   const double maxBar = 80;
  //   return SizedBox(
  //     height: totalHeight,
  //     child: Row(
  //       mainAxisSize: MainAxisSize.min,
  //       children: List.generate(12, (i) {
  //         // create slight phase shift to make it wave-like
  //         double factor = sin(i + DateTime.now().millisecond / 200);
  //         double barHeight = minBar + maxBar * normalized * factor.abs();

  //         return Align(
  //           // alignment: Alignment.bottomCenter,
  //           child: AnimatedContainer(
  //             duration: const Duration(milliseconds: 150),
  //             margin: const EdgeInsets.symmetric(horizontal: 4),
  //             height: barHeight,
  //             width: 6,
  //             decoration: BoxDecoration(
  //               color: Theme.of(context).brightness == Brightness.dark
  //                   ? Colors.white
  //                   : Colors.black38,
  //               borderRadius: BorderRadius.circular(9999),
  //             ),
  //           ),
  //         );
  //       }),
  //     ),
  //   );
  // }

  Widget _buildLiveWave(Amplitude amp) {
    final double normalized = (amp.current / 120).clamp(0.2, 1.0);
    const int barCount = 55; // more bars = smoother wave
    const double minBarHeight = 8;
    const double maxBarHeight = 32;
    const double barWidth = 3;
    const double spacing = 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;
        const double totalWaveWidth = barCount * (barWidth + spacing);
        final double horizontalPadding =
            (availableWidth - totalWaveWidth) / 2; // center horizontally

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding.clamp(0, 10),
          ),
          child: SizedBox(
            height: 90,
            width: 280,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(barCount, (i) {
                // create soft wave motion with time-based phase shift
                final t = DateTime.now().millisecondsSinceEpoch / 250.0;
                final factor = (sin(i * 1.2 + t) * 0.5 + 3.9);
                final barHeight =
                    minBarHeight +
                    (maxBarHeight - minBarHeight) * factor * normalized;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: spacing / 2),
                  width: barWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black26, // WhatsApp-like color
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPauseResumeControl() {
    if (_recordState == RecordState.stop) {
      return const SizedBox.shrink();
    }

    late Icon icon;
    late Color color;

    if (_recordState == RecordState.record) {
      icon = const Icon(Icons.pause, color: Colors.red, size: 30);
      color = Colors.transparent;
    } else {
      final theme = Theme.of(context);
      icon = const Icon(Icons.play_arrow, color: Colors.red, size: 30);
      color = theme.primaryColor.withValues(alpha: 0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 45, height: 45, child: icon),
          onTap: () {
            (_recordState == RecordState.pause) ? _resume() : _pause();
          },
        ),
      ),
    );
  }

  Widget _buildText() {
    if (_recordState != RecordState.stop) {
      return Row(
        // mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const SizedBox(width: 10),

          _buildTimer(), // existing timer
          // const SizedBox(width: 10),
          ValueListenableBuilder<Amplitude>(
            valueListenable: amplitudeNotifier,
            builder: (context, amp, _) {
              return
              // const CustomWaves();
              _buildLiveWave(amp);
            },
          ),

          //  _buildLiveWave() // 🔹 add this line for animated waves
        ],
      );
    }

    return const Text("");
  }

  Widget _buildTimer() {
    final String minutes = _formatNumber(_recordDuration ~/ 60);
    final String seconds = _formatNumber(_recordDuration % 60);

    // Force LTR so colon and numbers keep order in RTL locales (e.g. Arabic)
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        '$minutes:$seconds',
        style: TextStyle(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
      ),
    );
  }

  String _formatNumber(int number) {
    String numberStr = number.toString();
    if (number < 10) {
      numberStr = '0$numberStr';
    }

    return numberStr;
  }

  void _startTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() => _recordDuration++);
    });
  }
}

mixin AudioRecorderMixin {
  Future<void> recordFile(AudioRecorder recorder, RecordConfig config) async {
    final path = await _getPath();

    await recorder.start(config, path: path);
  }

  Future<void> recordStream(AudioRecorder recorder, RecordConfig config) async {
    final path = await _getPath();

    final file = File(path);

    final stream = await recorder.startStream(config);

    stream.listen(
      (data) {
        file.writeAsBytesSync(data, mode: FileMode.append);
      },
      onDone: () {
        print('End of stream. File written to $path.');
      },
    );
  }

  void downloadWebData(String path) {}

  Future<String> _getPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(
      dir.path,
      'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
  }
}

class CustomWaves extends StatelessWidget {
  const CustomWaves({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: const Color(0xFF16161B),
      child: FittedBox(
        child: SizedBox(
          width: 200,
          height: 50,
          child: CustomPaint(painter: WavePainter()),
        ),
      ),
    );
  }
}

final class WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()
      ..color = const Color(0xFFFAFAFA)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    var shift = 0.0;
    final verticalCenter = size.height / 2;
    final values = List<double>.generate(100, (_) {
      return Random().nextDouble() * verticalCenter;
    });

    for (var i = 0; i < values.length && shift < size.width; i++) {
      canvas.drawLine(
        Offset(shift, verticalCenter - values[i]),
        Offset(shift, verticalCenter + values[i]),
        brush,
      );

      shift += 6;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
