import 'srx_identity.dart';

class SrxBaseModel implements SrxIdentity {
  @override
  String? id;
  DateTime? createdOn;
  DateTime? lastModifiedOn;

  Map<String, dynamic> toJson() {
    throw UnimplementedError;
  }
}
