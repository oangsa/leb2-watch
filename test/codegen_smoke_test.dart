import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'codegen/domain_value.dart';
import 'codegen/smoke_provider.dart';
import 'codegen/transport_value.dart';

void main() {
  test('generated Freezed, JSON, and Riverpod code works', () {
    const domainValue = DomainValue(value: 'ready');
    final transportValue = TransportValue.fromJson(const <String, Object?>{
      'value': 'ready',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(domainValue.copyWith(value: 'updated').value, 'updated');
    expect(transportValue.toJson(), const <String, Object?>{'value': 'ready'});
    expect(container.read(smokeValueProvider), domainValue);
  });
}
