import 'dart:core';

import 'package:cast_plus/cast.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/finamp_user_helper.dart';
import 'package:finamp/services/jellyfin_api.dart';
import 'package:finamp/services/jellyfin_api_helper.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

const defaultCastAppId = "F007D354";
const messageNamespace = "urn:x-cast:com.connectsdk";
typedef CastMessagePayload = Map<String, dynamic>;
final _jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
final _finampUserHelper = GetIt.instance<FinampUserHelper>();

class GoogleCast {
  final CastSessionManager sessionManager = CastSessionManager();
  final Logger _logger = Logger("GoogleCast");
  String? appId;
  String? senderDeviceId;
  CastDevice? device;
  CastSession? session;
  PublicSystemInfoResult? serverInfo;

  bool get ready => session?.state == CastSessionState.connected;

  Future<List<CastDevice>> search() async {
    return CastDiscoveryService().search();
  }

  Future<void> connect(CastDevice targetDevice) async {
    Future<void> ensureServerInfo() async {
      serverInfo ??= await _jellyfinApiHelper.loadServerPublicInfo();
    }

    Future<void> ensureDeviceId() async {
      senderDeviceId ??= await getDeviceInfo().then((info) => info.id);
    }

    Future<void> ensureAppId() async {
      if (appId == null) {
        final userInfo = await _jellyfinApiHelper.getUser();
        appId = userInfo.configuration?.castReceiverId ?? defaultCastAppId;
      }
    }

    Future<void> setupReceiver(CastDevice targetDevice) async {
      // _launch/0 requires appId to be present and _connect/1 to have happened
      await Future.wait([ensureAppId(), _acquireSession(targetDevice)]);
      if (!ready) await _launch();
    }

    /* serverInfo and deviceId are not required until we are sending messages,
       so they can be raced against getting the receiver ready here */
    await Future.wait([ensureServerInfo(), ensureDeviceId(), setupReceiver(targetDevice)]);
  }

  Future<void> _acquireSession(CastDevice targetDevice) async {
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
  }

  Future<void> _launch() async {
    _log("Launching app $appId");
    _sendMessage(CastSession.kNamespaceReceiver, {"type": "LAUNCH", "appId": appId});

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

  // https://github.com/jellyfin/jellyfin-web/blob/948d792677b62ac5afe28813fed827c5e24b7090/src/plugins/chromecastPlayer/plugin.js#L323
  void sendMessage(String command, [CastMessagePayload options = const {}]) {
    if (!ready) {
      _logger.warning("Failed to send message: not ready");
      throw "NOT_READY";
    }
    /* null-safety:
        ready ensures `device` is present by definition
        further, in the only place GoogleCast is accessed (OutputMenu),
        currentUser and serverInfo are ready as well
     */
    final user = _finampUserHelper.currentUser!;

    CastMessagePayload payload = {
      "command": command,
      "options": options,
      "userId": user.id,
      "deviceId": senderDeviceId,
      "accessToken": user.accessToken,
      "serverAddress": user.publicAddress,
      "serverId": user.serverId,
      "serverVersion": serverInfo!.version,
      "receiverName": device!.extras["fn"] ?? device!.name,
    };

    _sendMessage(messageNamespace, payload);
  }

  void _sendMessage(String namespace, CastMessagePayload payload) {
    _logger.finest("--> [$namespace]: $payload");
    session!.sendMessage(namespace, payload);
  }

  void _log(String message) {
    _logger.fine('[${session?.sessionId} on "${device?.name}"]: $message');
  }
}
