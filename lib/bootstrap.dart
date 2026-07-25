import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/leb2_watch_app.dart';
import 'src/core/config/app_configuration.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ProviderScope(
      child: Leb2WatchApp(configuration: AppConfiguration.fromEnvironment()),
    ),
  );
}
