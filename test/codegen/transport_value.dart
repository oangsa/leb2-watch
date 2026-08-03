import 'package:json_annotation/json_annotation.dart';

part 'transport_value.g.dart';

@JsonSerializable()
class TransportValue {
  const TransportValue({required this.value});

  factory TransportValue.fromJson(Map<String, Object?> json) =>
      _$TransportValueFromJson(json);

  final String value;

  Map<String, Object?> toJson() => _$TransportValueToJson(this);
}
