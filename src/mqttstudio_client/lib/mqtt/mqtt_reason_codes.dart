// The client packages only provide reason and return codes as enum names such as 'badUserNameOrPassword'. Turns them
// into readable text such as 'Bad user name or password (0x86)', followed by the broker's reason string if it sent
// one.
String describeReasonCode(String codeName, {int? value, String? reasonString}) {
  var words = codeName.replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (match) => ' ${match[1]!.toLowerCase()}');
  var text = words.isEmpty ? codeName : words[0].toUpperCase() + words.substring(1);
  if (value != null) {
    text += ' (0x${value.toRadixString(16).padLeft(2, '0')})';
  }
  if (reasonString != null && reasonString.isNotEmpty) {
    text += ': $reasonString';
  }
  return text;
}
