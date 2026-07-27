import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'storage.dart';
import 'secret_manager.dart';

class SyncService {
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  Timer? _pollingTimer;
  Timer? _discoveryTimer;

  String _lastCopiedText = '';
  final _syncController = StreamController<String>.broadcast();

  Stream<String> get onSynced => _syncController.stream;

  // Track the server port dynamically
  int get serverPort => 41234;
  int get udpPort => 41235;

  bool _isServerRunning = false;
  bool get isServerRunning => _isServerRunning;

  // ─── Clipboard Polling ─────────────────────────────────────────────────────

  void startClipboardPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      // Don't poll if secret mode is active or system clipboard cannot be read
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data == null || data.text == null) return;
        final text = data.text!;

        if (text.isEmpty) return;

        if (text != _lastCopiedText) {
          _lastCopiedText = text;

          // If Secret Mode is active, do not save to persistent history
          if (SecretManager.instance.isSecretModeActive) {
            // Schedule clipboard auto-deletion after configurable timeout
            await SecretManager.instance.copySecretText(text, AppStorage.instance.secretTimeoutSeconds);
            return;
          }

          // Save to persistent storage
          await AppStorage.instance.addClipboardItem(text);
          _syncController.add(text);

          // Sync to all paired LAN peers
          if (AppStorage.instance.autoSync) {
            syncToPeers(text);
          }
        }
      } catch (_) {
        // Clipboard empty or not ready
      }
    });
  }

  void stopClipboardPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // Update last copied text from within the app (e.g. when user clicks copy)
  void updateLastCopiedText(String text) {
    _lastCopiedText = text;
  }

  // ─── Network Info ──────────────────────────────────────────────────────────

  Future<String> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          // Filter common private IP subnets
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
      // Fallback to first non-loopback address
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  // ─── HTTP Server (Receiver) ────────────────────────────────────────────────

  Future<void> startServer() async {
    if (_isServerRunning) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, serverPort);
      _isServerRunning = true;
      _server!.listen(_handleHttpRequest);
      startUdpDiscovery();
    } catch (e) {
      _isServerRunning = false;
    }
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _isServerRunning = false;
    stopUdpDiscovery();
  }

  void _handleHttpRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;

    try {
      if (request.method == 'GET' && request.uri.path == '/status') {
        final ip = await getLocalIp();
        response.write(json.encode({
          'name': AppStorage.instance.deviceName,
          'ip': ip,
          'port': serverPort,
        }));
      } else if (request.method == 'POST' && request.uri.path == '/sync') {
        final bodyStr = await utf8.decoder.bind(request).join();
        final body = json.decode(bodyStr) as Map<String, dynamic>;
        final content = body['content'] as String;

        if (content.isNotEmpty) {
          // Avoid loopback adding
          _lastCopiedText = content;
          await Clipboard.setData(ClipboardData(text: content));

          // Save to local history
          await AppStorage.instance.addClipboardItem(content, category: 'Synced');
          _syncController.add(content);
        }

        response.write(json.encode({'status': 'success', 'message': 'Clipboard synced'}));
      } else if (request.method == 'POST' && request.uri.path == '/pair') {
        final bodyStr = await utf8.decoder.bind(request).join();
        final body = json.decode(bodyStr) as Map<String, dynamic>;
        final ip = body['ip'] as String;
        final port = body['port'] as int;
        final name = body['name'] as String;

        await AppStorage.instance.addOrUpdatePeer(ip, port, name, isPaired: true);

        response.write(json.encode({
          'status': 'paired',
          'name': AppStorage.instance.deviceName,
        }));
      } else {
        response.statusCode = HttpStatus.notFound;
        response.write(json.encode({'error': 'Not Found'}));
      }
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
      response.write(json.encode({'error': e.toString()}));
    } finally {
      await response.close();
    }
  }

  // ─── UDP Discovery ─────────────────────────────────────────────────────────

  Future<void> startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram == null) return;
          try {
            final message = utf8.decode(datagram.data);
            final data = json.decode(message) as Map<String, dynamic>;

            if (data['type'] == 'DISCOVER') {
              final peerIp = data['ip'] as String;
              final peerPort = data['port'] as int;
              final peerName = data['name'] as String;

              // Avoid adding self
              getLocalIp().then((myIp) {
                if (peerIp != myIp) {
                  AppStorage.instance.addOrUpdatePeer(peerIp, peerPort, peerName, isPaired: true);
                }
              });
            }
          } catch (_) {}
        }
      });

      // Broadcast presence every 10 seconds
      _discoveryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        broadcastPresence();
      });
      broadcastPresence(); // Immediate broadcast
    } catch (_) {}
  }

  void stopUdpDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
  }

  Future<void> broadcastPresence() async {
    if (_udpSocket == null) return;
    try {
      final ip = await getLocalIp();
      final packet = json.encode({
        'type': 'DISCOVER',
        'ip': ip,
        'port': serverPort,
        'name': AppStorage.instance.deviceName,
      });
      final bytes = utf8.encode(packet);
      _udpSocket!.send(bytes, InternetAddress('255.255.255.255'), udpPort);
    } catch (_) {}
  }

  // ─── HTTP Client Sync ──────────────────────────────────────────────────────

  Future<void> pairPeerManually(String ip, int port) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.post(ip, port, '/pair');
      request.headers.contentType = ContentType.json;

      final myIp = await getLocalIp();
      request.write(json.encode({
        'ip': myIp,
        'port': serverPort,
        'name': AppStorage.instance.deviceName,
      }));

      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        final bodyStr = await response.transform(utf8.decoder).join();
        final body = json.decode(bodyStr) as Map<String, dynamic>;
        final name = body['name'] as String? ?? 'Manual Peer';
        await AppStorage.instance.addOrUpdatePeer(ip, port, name, isPaired: true);
      }
    } finally {
      client.close();
    }
  }

  Future<void> syncToPeers(String content) async {
    final peers = AppStorage.instance.getPeers().where((p) => p.isPaired);
    if (peers.isEmpty) return;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);

    for (final peer in peers) {
      try {
        final request = await client.post(peer.ip, peer.port, '/sync');
        request.headers.contentType = ContentType.json;
        request.write(json.encode({
          'content': content,
          'sender': AppStorage.instance.deviceName,
        }));
        // We trigger connection and ignore response body
        final response = await request.close();
        if (response.statusCode == HttpStatus.ok) {
          // update last synced
          await AppStorage.instance.addOrUpdatePeer(peer.ip, peer.port, peer.name);
        }
      } catch (_) {
        // peer offline
      }
    }
    client.close();
  }
}
