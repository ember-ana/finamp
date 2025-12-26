import 'package:cast_plus/cast.dart';

extension GoogleCastDevice on CastDevice {
  String get friendlyName => extras["fn"] ?? name;
  String? get model => extras["md"];
  String get id => serviceName;
}
