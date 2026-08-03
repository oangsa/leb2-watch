import 'dart:convert';
import 'dart:io';

import 'package:leb2_watch/src/features/authentication/application/session_mutation_gate.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 2) {
    exitCode = 64;
    return;
  }

  final waitForRelease =
      arguments.length == 2 && arguments[1] == '--wait-for-release';
  stdout.writeln('ready');
  final gate = FileSessionMutationGate(
    lockFileProvider: () async => File(arguments.first),
  );
  await gate.runExclusive(() async {
    stdout.writeln('entered');
    if (waitForRelease) {
      await stdin
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line == 'release');
    }
  });
  stdout.writeln('done');
}
