import '../service/srx_http_service.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

// use 'flutter pub run build_runner build' to run the code generator
part 'srx_session.g.dart';

@JsonSerializable(explicitToJson: true)
class SrxSession {
  late String accessToken;
  late String refreshToken;
  late DateTime accessTokenExpirationDateTime;
  Map<String, dynamic>? _tokenItems;
  Map<String, dynamic> customData = Map();

  SrxSession(this.accessToken, this.refreshToken, this.accessTokenExpirationDateTime);

  SrxSession.fromToken(SrxToken token) {
    setToken(token);
  }

  void setToken(SrxToken token) {
    accessToken = token.accessToken;
    accessTokenExpirationDateTime = DateTime.now().add(Duration(seconds: token.accessTokenExpirationTime));
    refreshToken = token.refreshToken;
  }

  bool get isAccessTokenExpired => accessTokenExpirationDateTime.isBefore(DateTime.now());

  String get userId {
    return getTokenItems()['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'];
  }

  String? getClaimData(String claimName) {
    return getTokenItems()[claimName];
  }

  Map<String, dynamic> getTokenItems() {
    if (_tokenItems == null) {
      _tokenItems = JwtDecoder.decode(accessToken);
    }
    return _tokenItems!;
  }

  factory SrxSession.fromJson(Map<String, dynamic> json) => _$SrxSessionFromJson(json);
  Map<String, dynamic> toJson() => _$SrxSessionToJson(this);
}
