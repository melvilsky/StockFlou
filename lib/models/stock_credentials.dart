import 'dart:convert';

class StockCredentials {
  static const defaultAdobeHost = 'sftp.contributor.adobestock.com';

  final String hostname;
  final String username;
  final String password;

  const StockCredentials({
    this.hostname = '',
    this.username = '',
    this.password = '',
  });

  bool get isEmpty =>
      hostname.trim().isEmpty ||
      (username.trim().isEmpty && password.trim().isEmpty);

  static String sanitizeHost(String raw, {String defaultHost = ''}) {
    final cleaned = raw
        .trim()
        .replaceFirst(RegExp(r'^[a-zA-Z]+://'), '')
        .replaceAll(RegExp(r'/+$'), '')
        .trim();
    return cleaned.isEmpty ? defaultHost : cleaned;
  }

  StockCredentials copyWith({
    String? hostname,
    String? username,
    String? password,
  }) {
    return StockCredentials(
      hostname: hostname ?? this.hostname,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  // To/from separated string for easy storage (host|user|pass)
  // Base64 encoding the parts to avoid pipe collision in passwords
  String toStorageString() {
    final h = base64Encode(utf8.encode(hostname));
    final u = base64Encode(utf8.encode(username));
    final p = base64Encode(utf8.encode(password));
    return '$h|$u|$p';
  }

  static StockCredentials fromStorageString(
    String str, {
    String defaultHost = '',
  }) {
    if (str.isEmpty || !str.contains('|')) {
      return StockCredentials(hostname: defaultHost);
    }
    try {
      final parts = str.split('|');
      if (parts.length != 3) return StockCredentials(hostname: defaultHost);

      final h = sanitizeHost(
        utf8.decode(base64Decode(parts[0])),
        defaultHost: defaultHost,
      );
      final u = utf8.decode(base64Decode(parts[1]));
      final p = utf8.decode(base64Decode(parts[2]));

      return StockCredentials(hostname: h, username: u, password: p);
    } catch (_) {
      return StockCredentials(hostname: defaultHost);
    }
  }
}
