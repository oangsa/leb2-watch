import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/app_dependencies.dart';
import 'src/app/leb2_watch_app.dart';
import 'src/core/config/app_configuration.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();

  final configuration = AppConfiguration.fromEnvironment();
  runApp(
    ProviderScope(
      overrides: [appConfigurationProvider.overrideWithValue(configuration)],
      child: Leb2WatchApp(configuration: configuration),
    ),
  );
}
