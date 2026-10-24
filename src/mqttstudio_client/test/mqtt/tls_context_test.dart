import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt311_protocol_client.dart';
import 'package:mqttstudio/mqtt/mqtt5_protocol_client.dart';
import 'package:mqttstudio/mqtt/mqtt_protocol_client.dart';
import 'package:mqttstudio/mqtt/tls_context.dart';
import 'package:srx_flutter/srx_flutter.dart';

// certificates made by test/fixtures/certs/generate.sh
const String certs = 'test/fixtures/certs';

// Answers every CONNECT with a successful CONNACK over TLS, and requires a client certificate signed by the test CA.
class FakeTlsBroker {
  late SecureServerSocket _server;
  final List<String> clientSubjects = [];

  int get port => _server.port;

  Future start() async {
    var context = SecurityContext()
      ..useCertificateChain('$certs/server.crt')
      ..usePrivateKey('$certs/server.key')
      ..setTrustedCertificates('$certs/ca.crt')
      ..setClientAuthorities('$certs/ca.crt');
    _server = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, context, requireClientCertificate: true);
    _server.listen(_onConnection, onError: (_) {});
  }

  Future stop() async {
    await _server.close();
  }

  void _onConnection(SecureSocket socket) {
    clientSubjects.add(socket.peerCertificate?.subject ?? '');
    socket.listen((data) {
      // CONNECT packet: the protocol level follows the protocol name "MQTT"
      if (data.isNotEmpty && data[0] == 0x10) {
        var level = data[8];
        socket.add(level == 5 ? [0x20, 0x03, 0x00, 0x00, 0x00] : [0x20, 0x02, 0x00, 0x00]);
      }
    }, onError: (_) {});
  }
}

void main() {
  MqttSettings settings({String? ca, String? certificate, String? key, String? password}) {
    return MqttSettings('localhost', 'client', 8883, useSsl: true)
      ..caCertificatePath = ca
      ..clientCertificatePath = certificate
      ..clientKeyPath = key
      ..clientKeyPassword = password;
  }

  group('TlsContext.of', () {
    test('uses the default context without certificates', () {
      expect(TlsContext.of(settings()), isNull);
      expect(TlsContext.of(settings(ca: '', certificate: '')), isNull);
    });

    test('loads a CA, a client certificate and its key', () {
      expect(
          TlsContext.of(settings(ca: '$certs/ca.crt', certificate: '$certs/client.crt', key: '$certs/client.key')),
          isNotNull);
    });

    test('reads the key from the certificate file without a key file', () {
      expect(TlsContext.of(settings(certificate: '$certs/client-combined.pem')), isNotNull);
    });

    test('decrypts the key with its password', () {
      expect(
          TlsContext.of(
              settings(certificate: '$certs/client.crt', key: '$certs/client-encrypted.key', password: 'secret')),
          isNotNull);
    });

    test('names the file that cannot be loaded', () {
      expect(
          () => TlsContext.of(settings(certificate: '$certs/missing.crt')),
          throwsA(isA<SrxServiceException>()
              .having((exc) => exc.errorMessage, 'errorMessage', contains('client certificate $certs/missing.crt'))));
    });

    test('fails with a wrong key password', () {
      expect(
          () => TlsContext.of(
              settings(certificate: '$certs/client.crt', key: '$certs/client-encrypted.key', password: 'wrong')),
          throwsA(isA<SrxServiceException>()
              .having((exc) => exc.errorMessage, 'errorMessage', contains('private key'))));
    });

    test('fails when the key file has no key', () {
      expect(() => TlsContext.of(settings(certificate: '$certs/client.crt')), throwsA(isA<SrxServiceException>()));
    });
  });

  group('connecting with a client certificate', () {
    late FakeTlsBroker broker;

    setUp(() async {
      broker = FakeTlsBroker();
      await broker.start();
    });

    tearDown(() async {
      await broker.stop();
    });

    MqttSettings brokerSettings(MqttProtocolVersion version) {
      return settings(ca: '$certs/ca.crt', certificate: '$certs/client.crt', key: '$certs/client.key')
        ..port = broker.port
        ..protocolVersion = version;
    }

    for (var version in MqttProtocolVersion.values) {
      MqttProtocolClient createClient() =>
          version == MqttProtocolVersion.v5 ? Mqtt5ProtocolClient() : Mqtt311ProtocolClient();

      test('connects with ${version.displayName}', () async {
        var client = createClient();

        await client.connect(brokerSettings(version));

        expect(client.isConnected(), isTrue);
        expect(broker.clientSubjects.single, contains('mqttstudio-test-client'));
        client.disconnect();
      });

    }
  });
}
