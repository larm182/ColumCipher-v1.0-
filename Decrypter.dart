import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;

void main() {
  runApp(const DecryptorApp());
}

class DecryptorApp extends StatelessWidget {
  const DecryptorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desencriptador de Carpetas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
      ),
      home: const DecryptorScreen(),
    );
  }
}

class KeyInfo {
  final String aesKey;
  final int profileId;
  final String timestamp;
  final String encryptedPath;
  final String iv;
  final int totalFiles;

  KeyInfo({
    required this.aesKey,
    required this.profileId,
    required this.timestamp,
    required this.encryptedPath,
    required this.iv,
    required this.totalFiles,
  });

  factory KeyInfo.fromJson(Map<String, dynamic> json) {
    return KeyInfo(
      aesKey: json['aes_key'] as String,
      profileId: json['profile_id'] as int,
      timestamp: json['timestamp'] as String,
      encryptedPath: json['encrypted_path'] as String,
      iv: json['iv'] as String,
      totalFiles: json['total_files'] as int,
    );
  }
}

class DecryptorScreen extends StatefulWidget {
  const DecryptorScreen({Key? key}) : super(key: key);

  @override
  State<DecryptorScreen> createState() => _DecryptorScreenState();
}

class _DecryptorScreenState extends State<DecryptorScreen> {
  final TextEditingController _serverController = TextEditingController(
    text: 'http://192.168.1.100:5000',
  );
  final TextEditingController _profileIdController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();

  bool _isProcessing = false;
  String _status = 'Conecta al servidor para obtener llaves';
  double _progress = 0.0;
  int _filesProcessed = 0;
  int _totalFiles = 0;
  KeyInfo? _selectedKey;
  List<KeyInfo> _availableKeys = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
  }

  Future<void> _loadKeysFromServer() async {
    try {
      setState(() {
        _status = 'Cargando llaves del servidor...';
        _availableKeys = [];
        _selectedKey = null;
      });

      final response = await http
          .get(
            Uri.parse('${_serverController.text}/mobile-keys'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final keysData = data['mobile_keys'] as List;

        List<KeyInfo> keys = [];
        for (var keyData in keysData) {
          // Obtener la llave completa
          final keyResponse = await http
              .get(
                Uri.parse(
                    '${_serverController.text}/get-key/${keyData['profile_id']}'),
              )
              .timeout(const Duration(seconds: 5));

          if (keyResponse.statusCode == 200) {
            final completeKeyData = json.decode(keyResponse.body);
            keys.add(KeyInfo.fromJson(completeKeyData));
          }
        }

        setState(() {
          _availableKeys = keys;
          _status = '${keys.length} llaves cargadas del servidor';
        });

        if (keys.isEmpty) {
          _showErrorDialog('No hay llaves disponibles en el servidor');
        }
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _status = 'Error al cargar llaves: $e';
      });
      _showErrorDialog('No se pudo conectar al servidor: $e');
    }
  }

  Future<void> _getKeyByProfileId() async {
    if (_profileIdController.text.isEmpty) {
      _showErrorDialog('Ingresa un Profile ID');
      return;
    }

    try {
      final profileId = int.parse(_profileIdController.text);
      await _getKeyByProfileIdInt(profileId);
    } catch (e) {
      _showErrorDialog('Profile ID debe ser un número válido');
    }
  }

  Future<void> _getKeyByProfileIdInt(int profileId) async {
    try {
      setState(() {
        _status = 'Buscando llave Profile ID: $profileId...';
      });

      final response = await http
          .get(
            Uri.parse('${_serverController.text}/get-key/$profileId'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final keyData = json.decode(response.body);
        final keyInfo = KeyInfo.fromJson(keyData);

        setState(() {
          _selectedKey = keyInfo;
          _pathController.text = keyInfo.encryptedPath;
          _status =
              'Llave encontrada: ${keyInfo.totalFiles} archivos encriptados';
        });

        _showSuccessDialog('Llave cargada',
            'Profile ID: $profileId\nArchivos: ${keyInfo.totalFiles}');
      } else {
        throw Exception('Llave no encontrada');
      }
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
      _showErrorDialog('No se encontró la llave con Profile ID: $profileId');
    }
  }

  Future<void> _decryptFolder() async {
    if (_isProcessing) return;
    if (_selectedKey == null) {
      _showErrorDialog('Por favor selecciona una llave primero');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _filesProcessed = 0;
      _totalFiles = 0;
    });

    try {
      // 1. Decodificar llave y IV del servidor
      final keyBytes = base64.decode(_selectedKey!.aesKey);
      final key = encrypt.Key(Uint8List.fromList(keyBytes));

      final ivBytes = base64.decode(_selectedKey!.iv);
      final iv = encrypt.IV(ivBytes);

      // 2. Verificar carpeta
      final targetDir = Directory(_pathController.text);
      if (!await targetDir.exists()) {
        throw Exception('La carpeta no existe: ${_pathController.text}');
      }

      // 3. Contar archivos encriptados
      final files = await _getAllEncryptedFiles(targetDir);
      if (files.isEmpty) {
        throw Exception(
            'No se encontraron archivos encriptados (.enc) en la carpeta');
      }

      setState(() {
        _totalFiles = files.length;
        _status = 'Desencriptando ${files.length} archivos...';
      });

      // 4. Desencriptar cada archivo
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        await _decryptFile(file, encrypter, iv);

        setState(() {
          _filesProcessed = i + 1;
          _progress = (_filesProcessed / _totalFiles);
          _status = 'Desencriptando: $_filesProcessed de $_totalFiles';
        });
      }

      setState(() {
        _status =
            '¡Desencriptación completada! $_totalFiles archivos restaurados';
        _isProcessing = false;
      });

      _showSuccessDialog(
          '¡Éxito!', '$_totalFiles archivos desencriptados correctamente');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isProcessing = false;
      });

      _showErrorDialog(e.toString());
    }
  }

  Future<List<File>> _getAllEncryptedFiles(Directory dir) async {
    List<File> files = [];

    await for (var entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.enc')) {
        files.add(entity);
      }
    }

    return files;
  }

  Future<void> _decryptFile(
      File file, encrypt.Encrypter encrypter, encrypt.IV iv) async {
    try {
      // Leer archivo encriptado
      final bytes = await file.readAsBytes();

      // Desencriptar
      final decrypted = encrypter.decryptBytes(
        encrypt.Encrypted(Uint8List.fromList(bytes)),
        iv: iv,
      );

      // Obtener nombre original (quitar .enc)
      final originalPath = file.path.substring(0, file.path.length - 4);

      // Guardar archivo desencriptado
      final decryptedFile = File(originalPath);
      await decryptedFile.writeAsBytes(decrypted);

      // Eliminar archivo encriptado
      await file.delete();

      print('Desencriptado: $originalPath');
    } catch (e) {
      print('Error al desencriptar ${file.path}: $e');
      throw Exception(
          'Error al desencriptar: Llave/IV incorrectos o archivo corrupto');
    }
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 32),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Text('Error'),
          ],
        ),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showKeySelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Seleccionar Llave del Servidor'),
        content: SizedBox(
          width: double.maxFinite,
          child: _availableKeys.isEmpty
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No hay llaves disponibles'),
                    SizedBox(height: 8),
                    Text(
                      'Conéctate al servidor primero',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableKeys.length,
                  itemBuilder: (context, index) {
                    final key = _availableKeys[index];
                    final isSelected = _selectedKey?.profileId == key.profileId;

                    return Card(
                      color: isSelected ? Colors.green[50] : null,
                      child: ListTile(
                        leading: Icon(
                          Icons.key,
                          color: isSelected ? Colors.green : Colors.grey,
                        ),
                        title: Text('Profile ID: ${key.profileId}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ruta: ${key.encryptedPath}'),
                            Text('Archivos: ${key.totalFiles}'),
                            Text(
                              'Fecha: ${DateTime.parse(key.timestamp).toString().split('.')[0]}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedKey = key;
                            _pathController.text = key.encryptedPath;
                            _status =
                                'Llave seleccionada: Profile ID ${key.profileId}';
                          });
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: _loadKeysFromServer,
            child: const Text('Actualizar Lista'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('🔓 Desencriptador',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadKeysFromServer,
            tooltip: 'Actualizar llaves del servidor',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card de conexión al servidor
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Conexión al Servidor',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _serverController,
                      decoration: InputDecoration(
                        labelText: 'URL del Servidor',
                        hintText: 'http://192.168.1.100:5000',
                        prefixIcon: const Icon(Icons.cloud),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _profileIdController,
                            decoration: InputDecoration(
                              labelText: 'Profile ID específico',
                              hintText: '100001',
                              prefixIcon: const Icon(Icons.numbers),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _getKeyByProfileId,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                          ),
                          child: const Text('Buscar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadKeysFromServer,
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Cargar Todas las Llaves'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Card de llave seleccionada
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Llave de Desencriptación',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (_selectedKey != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.key, color: Colors.green),
                                const SizedBox(width: 8),
                                Text(
                                  'Profile ID: ${_selectedKey!.profileId}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('Ruta: ${_selectedKey!.encryptedPath}'),
                            Text(
                                'Archivos encriptados: ${_selectedKey!.totalFiles}'),
                            const SizedBox(height: 4),
                            Text(
                              'IV: ${_selectedKey!.iv.substring(0, 20)}...',
                              style: const TextStyle(
                                  fontSize: 10, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showKeySelector,
                        icon: const Icon(Icons.list),
                        label: const Text('Ver Todas las Llaves'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                  'No hay llave seleccionada. Conéctate al servidor.'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showKeySelector,
                        icon: const Icon(Icons.vpn_key),
                        label: const Text('Seleccionar Llave'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Card de ruta
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ruta a Desencriptar',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pathController,
                      decoration: InputDecoration(
                        labelText: 'Ruta de la carpeta encriptada',
                        hintText: '/storage/emulated/0/Prueba',
                        prefixIcon: const Icon(Icons.folder_open),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Card de estado
            Card(
              elevation: 2,
              color: Colors.green[50],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 48, color: Colors.green),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (_isProcessing) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: Colors.green[100],
                        color: Colors.green,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_filesProcessed de $_totalFiles archivos',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Botón de desencriptar
            ElevatedButton(
              onPressed: (_isProcessing || _selectedKey == null)
                  ? null
                  : _decryptFolder,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: _isProcessing
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Desencriptando...',
                            style: TextStyle(fontSize: 18)),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_open, size: 24),
                        SizedBox(width: 12),
                        Text('DESENCRIPTAR CARPETA',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
            ),
            const SizedBox(height: 20),

            // Información del servidor
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue),
              ),
              child: Column(
                children: [
                  const Icon(Icons.cloud, color: Colors.blue, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'MODO SERVIDOR',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Llaves disponibles: ${_availableKeys.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Todas las llaves se obtienen del servidor. No hay archivos locales.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    _profileIdController.dispose();
    _pathController.dispose();
    super.dispose();
  }
}
