import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:termeh/models/ssh_connection.dart';
import 'package:termeh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  test('Connection host key fields survive storage round trip', () async {
    final service = StorageService();
    final connection = SshConnection(
      id: 'server-1',
      name: 'Production',
      host: 'example.com',
      username: 'deploy',
      password: 'secret',
      hostKeyType: 'ssh-ed25519',
      hostKeyFingerprint: 'aa:bb:cc',
    );

    await service.saveConnections(<SshConnection>[connection]);
    final connections = await service.getConnections();

    expect(connections, hasLength(1));
    expect(connections.single.hostKeyType, 'ssh-ed25519');
    expect(connections.single.hostKeyFingerprint, 'aa:bb:cc');
  });
}
