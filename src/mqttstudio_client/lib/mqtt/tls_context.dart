import 'dart:io';
import 'package:flutter/services.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';

// TLS context of the connections to a broker, desktop only. In the browser the TLS connection is made by the browser.
class TlsContext {
  static const String bundledCaAsset = 'assets/cert/mosquitto.org.crt';

  static Uint8List? _bundledCa;

  // trusts the CA of test.mosquitto.org in every connection
  static Future loadBundledCa() async {
    var data = await rootBundle.load(bundledCaAsset);
    _bundledCa = data.buffer.asUint8List();
    SecurityContext.defaultContext.setTrustedCertificatesBytes(_bundledCa!);
  }

  // A context with the certificates of the project, or null if the default context is enough.
  // Throws a SrxServiceException if a file cannot be read or the key password is wrong.
  static SecurityContext? of(MqttSettings settings) {
    if (!settings.hasCertificates) {
      return null;
    }

    var context = SecurityContext(withTrustedRoots: true);
    if (_bundledCa != null) {
      context.setTrustedCertificatesBytes(_bundledCa!);
    }
    var caPath = settings.caCertificatePath;
    if (_isSet(caPath)) {
      _load('CA certificate', caPath!, () => context.setTrustedCertificates(caPath));
    }
    var certificatePath = settings.clientCertificatePath;
    if (_isSet(certificatePath)) {
      _load('client certificate', certificatePath!, () => context.useCertificateChain(certificatePath));
      var keyPath = _isSet(settings.clientKeyPath) ? settings.clientKeyPath! : certificatePath;
      var password = _isSet(settings.clientKeyPassword) ? settings.clientKeyPassword : null;
      _load('private key', keyPath, () => context.usePrivateKey(keyPath, password: password));
    }
    return context;
  }

  static void _load(String what, String path, void Function() load) {
    try {
      load();
    } on FileSystemException catch (exc) {
      throw SrxServiceException(
          'Cannot load the $what $path: ${exc.osError?.message ?? exc.message}', ServiceError.MqttCannotConnect);
    } on TlsException catch (exc) {
      throw SrxServiceException('Cannot load the $what $path: ${exc.message}', ServiceError.MqttCannotConnect);
    } on ArgumentError catch (exc) {
      // a file without a key, or a wrong key password
      _clearTlsErrors();
      throw SrxServiceException('Cannot load the $what $path: ${exc.message}', ServiceError.MqttCannotConnect);
    }
  }

  // dart:io leaves the TLS error behind an ArgumentError in the error queue, and the next certificate that is loaded
  // fails with it. A call that fails with a TlsException reads and clears the queue.
  static void _clearTlsErrors() {
    try {
      SecurityContext().useCertificateChainBytes(<int>[]);
    } on TlsException {
      // expected
    }
  }

  static bool _isSet(String? value) => value != null && value.isNotEmpty;
}
