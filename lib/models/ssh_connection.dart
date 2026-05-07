import 'dart:convert';

class SshConnection {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String group;
  final String? password;
  final String? hostKeyType;
  final String? hostKeyFingerprint;

  SshConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.group = '',
    this.password,
    this.hostKeyType,
    this.hostKeyFingerprint,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'group': group,
      'hostKeyType': hostKeyType,
      'hostKeyFingerprint': hostKeyFingerprint,
    };
  }

  SshConnection copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? group,
    String? password,
    String? hostKeyType,
    String? hostKeyFingerprint,
  }) {
    return SshConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      group: group ?? this.group,
      password: password ?? this.password,
      hostKeyType: hostKeyType ?? this.hostKeyType,
      hostKeyFingerprint: hostKeyFingerprint ?? this.hostKeyFingerprint,
    );
  }

  factory SshConnection.fromMap(Map<String, dynamic> map) {
    return SshConnection(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      host: map['host'] ?? '',
      port: map['port'] ?? 22,
      username: map['username'] ?? '',
      group: map['group'] ?? '',
      password: map['password'],
      hostKeyType: map['hostKeyType'],
      hostKeyFingerprint: map['hostKeyFingerprint'],
    );
  }

  String toJson() => json.encode(toMap());

  factory SshConnection.fromJson(String source) =>
      SshConnection.fromMap(json.decode(source));
}
