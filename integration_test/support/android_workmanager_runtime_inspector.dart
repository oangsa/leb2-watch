import 'package:flutter/services.dart';

const _androidWorkmanagerRuntimeChannel = MethodChannel(
  'dev.oangsa.leb2watch.test/workmanager-runtime',
);

final class AndroidWorkmanagerRuntimeSnapshot {
  const AndroidWorkmanagerRuntimeSnapshot(this.records);

  final List<AndroidWorkmanagerRuntimeRecord> records;
}

final class AndroidWorkmanagerRuntimeRecord {
  const AndroidWorkmanagerRuntimeRecord({
    required this.state,
    required this.networkType,
    required this.isPeriodic,
    required this.generationTags,
  });

  final String state;
  final String networkType;
  final bool isPeriodic;
  final List<String> generationTags;
}

Future<AndroidWorkmanagerRuntimeSnapshot>
readAndroidWorkmanagerRuntimeSnapshot() async {
  final raw = await _androidWorkmanagerRuntimeChannel
      .invokeMapMethod<String, dynamic>('snapshot');
  final records = raw?['records'];
  if (records is! List) {
    throw StateError(
      'WorkManager runtime inspector returned an invalid snapshot.',
    );
  }
  return AndroidWorkmanagerRuntimeSnapshot(
    records.map(_recordFromRaw).toList(growable: false),
  );
}

AndroidWorkmanagerRuntimeRecord _recordFromRaw(Object? value) {
  if (value is! Map) {
    throw StateError(
      'WorkManager runtime inspector returned an invalid record.',
    );
  }
  final state = value['state'];
  final networkType = value['networkType'];
  final periodic = value['periodic'];
  final generationTags = value['generationTags'];
  if (state is! String ||
      networkType is! String ||
      periodic is! bool ||
      generationTags is! List ||
      generationTags.any((tag) => tag is! String)) {
    throw StateError(
      'WorkManager runtime inspector returned an invalid record.',
    );
  }
  return AndroidWorkmanagerRuntimeRecord(
    state: state,
    networkType: networkType,
    isPeriodic: periodic,
    generationTags: generationTags.cast<String>(),
  );
}
