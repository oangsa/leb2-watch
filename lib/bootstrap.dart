import 'package:flutter/widgets.dart';

import 'src/app/leb2_watch_app.dart';
import 'src/core/config/app_configuration.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(Leb2WatchApp(configuration: AppConfiguration.fromEnvironment()));
}
