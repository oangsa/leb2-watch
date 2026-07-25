// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'smoke_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(smokeValue)
final smokeValueProvider = SmokeValueProvider._();

final class SmokeValueProvider
    extends $FunctionalProvider<DomainValue, DomainValue, DomainValue>
    with $Provider<DomainValue> {
  SmokeValueProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'smokeValueProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$smokeValueHash();

  @$internal
  @override
  $ProviderElement<DomainValue> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DomainValue create(Ref ref) {
    return smokeValue(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DomainValue value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DomainValue>(value),
    );
  }
}

String _$smokeValueHash() => r'a5aa6b71afd1c3ea26dc080a43536d89db62aa59';
