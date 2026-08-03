import 'package:freezed_annotation/freezed_annotation.dart';

part 'domain_value.freezed.dart';

@freezed
abstract class DomainValue with _$DomainValue {
  const factory DomainValue({required String value}) = _DomainValue;
}
