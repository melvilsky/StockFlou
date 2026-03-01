import 'dart:convert';

class StockCredentials {
  final String hostname;
  final String username;
  final String password;

  const StockCredentials({
    this.hostname = '',
    this.username = '',
    this.password = '',
  });

  bool get isEmpty => hostname.isEmpty && username.isEmpty && password.isEmpty;

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

  static StockCredentials fromStorageString(String str) {
    if (str.isEmpty || !str.contains('|')) return const StockCredentials();
    try {
      final parts = str.split('|');
      if (parts.length != 3) return const StockCredentials();

      final h = utf8.decode(base64Decode(parts[0]));
      final u = utf8.decode(base64Decode(parts[1]));
      final p = utf8.decode(base64Decode(parts[2]));

      return StockCredentials(hostname: h, username: u, password: p);
    } catch (_) {
      return const StockCredentials();
    }
  }
}
