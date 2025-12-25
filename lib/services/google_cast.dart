import 'dart:core';

import 'package:cast_plus/cast.dart';
import 'package:logging/logging.dart';

const defaultCastAppId = "F007D354";
const messageNamespace = "urn:x-cast:com.connectsdk";
typedef CastMessagePayload = Map<String, dynamic>;

class GoogleCast {
  final CastSessionManager sessionManager = CastSessionManager();
  final Logger _logger = Logger("GoogleCast");
  CastDevice? device;
  CastSession? session;

  Future<List<CastDevice>> search() async {
    return CastDiscoveryService().search();
  }

  Future<void> connect(CastDevice targetDevice) async {
    if (session != null) {
      if (targetDevice == device && ready) {
        _log("Reusing existing session");
        return;
      }
      await disconnect();
    }

    _log("Connecting");
    session = await sessionManager.startSession(targetDevice);
    device = targetDevice;

    session!.messageStream.listen((message) {
      _logger.finest("<-- $message");
    });
    _log("Connected");

    final subscription = session!.stateStream.listen((state) {
      _logger.finest("Session: $state");
    }, cancelOnError: true);
    subscription.onError((Object error) {
      _logger.warning("Session errored: $error");
      _disconnected();
    });
    subscription.onDone(() {
      _log("Session ended");
      _disconnected();
    });
    return;
  }

  Future<void> launch([String appId = defaultCastAppId]) async {
    _log("Launching app $appId");
    _sendMessage(CastSession.kNamespaceReceiver, {"type": "LAUNCH", "appId": appId}, checkReady: false);

    await for (CastMessagePayload payload in session!.messageStream) {
      switch (payload["type"]) {
        case "LAUNCH_ERROR":
          final reason = payload["reason"] as String;
          _logger.warning("Failed to launch application: $reason");
          throw reason;
        case "RECEIVER_STATUS":
          final apps = payload["status"]?["applications"] as List<dynamic>? ?? [];
          for (final app in apps) {
            if (app["appId"] == appId) {
              _log("Launched app $appId");
              return;
            }
          }
      }
    }
  }

  void sendMessage(String command, [CastMessagePayload options = const {}]) {
    CastMessagePayload payload = {"command": command, "options": options};
    _sendMessage(messageNamespace, payload);
  }

  void _sendMessage(String namespace, CastMessagePayload payload, {bool checkReady = true}) {
    _logger.finest("--> [$namespace]: $payload");
    if (checkReady && !ready) {
      _logger.warning("Failed to send message: not ready");
      throw "NOT_READY";
    }
    session!.sendMessage(namespace, payload);
  }

  bool get ready => session?.state == CastSessionState.connected;

  Future<void> disconnect() async {
    if (session == null) return;
    final sessionId = session!.sessionId;
    _log("Disconnecting");
    await sessionManager.endSession(sessionId);
    _disconnected();
  }

  void _disconnected() {
    session = null;
    device = null;
    _log("Disconnected");
  }

  void _log(String message) {
    _logger.fine('[${session?.sessionId} on "${device?.name}"]: $message');
  }
}
