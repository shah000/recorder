// ignore_for_file: unused_local_variable

import 'dart:io';

import 'package:recorder/recorder.dart';

void main() {
  Recorder(
    onSend: (data) {
      //split two parts duration and file
      final parts = data.split('|');
      final path = parts[0];
      final duration = parts[1];
      File audioFile = File(path);
      //send _handleAudioSend fun
      //await _handleAudioSend(audioFile, duration);
    },
    onStop: (data) {
      //split two parts duration and file
      final parts = data.split('|');
      final path = parts[0];
      final duration = parts[1];
      File audioFile = File(path);
      //send _handleAudioSend fun
      //await _handleAudioSend(audioFile, duration);
    },
  );
}
