import 'package:flutter_test/flutter_test.dart';
import 'package:termeh/models/ssh_connection.dart';

void main() {
  test('serialized connection metadata does not include password', () {
    final connection = SshConnection(
      id: 'server-1',
      name: 'Production',
      host: 'example.com',
      username: 'deploy',
      password: 'secret',
    );

    expect(connection.toMap(), isNot(contains('password')));
    expect(connection.toJson(), isNot(contains('secret')));
  });
}
