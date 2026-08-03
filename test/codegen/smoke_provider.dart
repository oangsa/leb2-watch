import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'domain_value.dart';

part 'smoke_provider.g.dart';

@riverpod
DomainValue smokeValue(Ref ref) => const DomainValue(value: 'ready');
