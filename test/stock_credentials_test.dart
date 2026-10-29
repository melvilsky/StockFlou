import 'package:flutter_test/flutter_test.dart';
import '../lib/models/stock_credentials.dart';

void main() {
  group('StockCredentials', () {
    test('uses default Adobe host when storage string is empty', () {
      final creds = StockCredentials.fromStorageString(
        '',
        defaultHost: StockCredentials.defaultAdobeHost,
      );

      expect(creds.hostname, 'sftp.contributor.adobestock.com');
      expect(creds.isEmpty, isTrue);
    });

    test('strips sftp:// protocol prefix and trailing slashes from host', () {
      final raw = const StockCredentials(
        hostname: 'sftp://sftp.contributor.adobestock.com/',
        username: '123456',
        password: 'secret',
      ).toStorageString();

      final loaded = StockCredentials.fromStorageString(
        raw,
        defaultHost: StockCredentials.defaultAdobeHost,
      );

      expect(loaded.hostname, 'sftp.contributor.adobestock.com');
      expect(loaded.username, '123456');
      expect(loaded.password, 'secret');
      expect(loaded.isEmpty, isFalse);
    });

    test('falls back to defaultHost when saved hostname is blank', () {
      final raw = const StockCredentials(
        hostname: '   ',
        username: '123456',
        password: 'secret',
      ).toStorageString();

      final loaded = StockCredentials.fromStorageString(
        raw,
        defaultHost: StockCredentials.defaultAdobeHost,
      );

      expect(loaded.hostname, 'sftp.contributor.adobestock.com');
    });
  });
}
