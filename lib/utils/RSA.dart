import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';
// Helper function to decode a PEM-encoded
 RSAPrivateKey parsePrivateKeyFromPem(String pem) {
   final key = pem.replaceAll('\n', '').replaceAll('-----BEGIN RSA PRIVATE KEY-----', '').replaceAll('-----END RSA PRIVATE KEY-----', '');
   final bytes = base64.decode(key);
   final parser = ASN1Parser(bytes);
   final sequence = parser.nextObject() as ASN1Sequence;
   final modulus = sequence.elements[1] as ASN1Integer;
   final privateExponent = sequence.elements[3] as ASN1Integer;
   final p = sequence.elements[4] as ASN1Integer;
   final q = sequence.elements[5] as ASN1Integer;
   return RSAPrivateKey(modulus.valueAsBigInteger!, privateExponent.valueAsBigInteger!, p.valueAsBigInteger!, q.valueAsBigInteger!);
 }

SecureRandom _secureRandom() {
   final secureRandom = SecureRandom('Fortuna') ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (n) => n))));
   return secureRandom;
 }

Uint8List createSignature(Uint8List payload, RSAPrivateKey privateKey) {
   final signer = Signer('SHA-256/RSA');
   final privateKeyParams = PrivateKeyParameter<RSAPrivateKey>(privateKey);
   final params = ParametersWithRandom(privateKeyParams, _secureRandom());
   signer.init(true, params); final signature = signer.generateSignature(payload) as RSASignature;
   return signature.bytes; }

Future<String> generateSignature(String data, String privateKeyPem) async {
  final payload = utf8.encode(data) as Uint8List;
  final privateKey = parsePrivateKeyFromPem(privateKeyPem);
  final signature = createSignature(payload, privateKey);
  return base64Encode(signature);
}