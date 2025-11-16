// ignore_for_file: unused_local_variable
// Copyright (c) 2025 Hussain Shah. All rights reserved.
// Use of this source code is governed by a MIT license in the LICENSE file.
// Recorder - A simple Flutter audio recording package.
// Provides start, pause, resume, and stop recording features.

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
