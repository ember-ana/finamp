import 'dart:core';

import 'package:cast_plus/cast.dart';
import 'package:finamp/models/google_cast_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/finamp_user_helper.dart';
import 'package:finamp/services/jellyfin_api.dart';
import 'package:finamp/services/jellyfin_api_helper.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

const defaultCastAppId = "F007D354";
const messageNamespace = "urn:x-cast:com.connectsdk";
const ticksPerSecond =
    10000000; // ref: https://github.com/jellyfin/jellyfin-chromecast/blob/f8e263eaf02b57e495330f5022b0e6b58918928b/src/helpers.ts#L43

final _jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
final _finampUserHelper = GetIt.instance<FinampUserHelper>();

class GoogleCast {
  final CastSessionManager _sessionManager = CastSessionManager();
  final Logger _logger = Logger("GoogleCast");
  String? _appId;
  String? _senderDeviceId;
  CastDevice? _device;
  CastSession? _session;
  PublicSystemInfoResult? _serverInfo;
  Stream<GoogleCastPayload>? _messageStream;
  Stream<GoogleCastReceiverStatus>? _receiverStatusStream;

  bool get ready => _session?.state == CastSessionState.connected;

  Future<List<CastDevice>> search() async => CastDiscoveryService().search();

  Future<void> connect(CastDevice targetDevice) async {
    Future<void> ensureServerInfo() async {
      _serverInfo ??= await _jellyfinApiHelper.loadServerPublicInfo();
    }

    Future<void> ensureDeviceId() async {
      _senderDeviceId ??= await getDeviceInfo().then((info) => info.id);
    }

    Future<void> ensureAppId() async {
      if (_appId == null) {
        final userInfo = await _jellyfinApiHelper.getUser();
        _appId = userInfo.configuration?.castReceiverId ?? defaultCastAppId;
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

    /* not sure why this is necessary
       see: https://github.com/jellyfin/jellyfin-web/blob/ed4417b7de88bce02992f0ab91cde230c05d9fed/src/plugins/chromecastPlayer/plugin.js#L248 */
    identify();
  }

  Future<void> _acquireSession(CastDevice targetDevice) async {
    if (_session != null) {
      if (targetDevice == _device && ready) {
        _log("Reusing existing session");
        return;
      }
      await disconnect();
    }

    _log("Connecting");
    _session = await _sessionManager.startSession(targetDevice);
    _device = targetDevice;

    Stream<GoogleCastPayload> setupMessageStream(CastSession session) {
      session.messageStream.listen((message) {
        _logger.finest("<-- $message");
      });

      return session.messageStream;
    }

    Stream<GoogleCastReceiverStatus> setupReceiverStatusStream(CastSession session) async* {
      await for (final payload in session.messageStream) {
        if (payload["type"] != "RECEIVER_STATUS") continue;

        yield GoogleCastReceiverStatus.fromJson(payload["status"] as GoogleCastPayload? ?? {});
      }
    }

    void setupStateStream(CastSession session) {
      final subscription = session.stateStream.listen((state) {
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

    _messageStream = setupMessageStream(_session!);
    _receiverStatusStream = setupReceiverStatusStream(_session!);
    setupStateStream(_session!);
    _log("Connected");
  }

  Future<void> _launch() async {
    _log("Launching app $_appId");
    sendControlMessage("LAUNCH", {"appId": _appId});

    await for (GoogleCastPayload payload in _session!.messageStream) {
      switch (payload["type"]) {
        case "LAUNCH_ERROR":
          final reason = payload["reason"] as String;
          _logger.warning("Failed to launch application: $reason");
          throw reason;
        case "RECEIVER_STATUS":
          final apps = payload["status"]?["applications"] as List<dynamic>? ?? [];
          for (final app in apps) {
            if (app["appId"] == _appId) {
              _log("Launched app $_appId");
              return;
            }
          }
      }
    }
  }

  Future<void> disconnect() async {
    if (_session == null) return;
    final sessionId = _session!.sessionId;
    _log("Disconnecting");
    await _sessionManager.endSession(sessionId);
    _disconnected();
  }

  void _disconnected() {
    _receiverStatusStream = null;
    _messageStream = null;
    _session = null;
    _device = null;
    _log("Disconnected");
  }

  Stream<GoogleCastPayload> subscribeTo(String type) {
    if (_messageStream == null) throw "NOT_READY";

    return _messageStream!
        .where((payload) => payload["type"] == type)
        .map((payload) => payload["data"] as GoogleCastPayload? ?? const {});
  }

  // null-safety: the volume in this stream will always have all fields set
  Stream<GoogleCastReceiverVolume> subscribeVolume() {
    if (_receiverStatusStream == null) throw "NOT_READY";
    return _receiverStatusStream!.map((payload) => payload.volume);
  }

  bool isReadyOn(CastDevice device) {
    return ready && _device == device;
  }

  // https://github.com/jellyfin/jellyfin-web/blob/948d792677b62ac5afe28813fed827c5e24b7090/src/plugins/chromecastPlayer/plugin.js#L323
  void sendMessage(String command, [GoogleCastPayload options = const {}]) {
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

    GoogleCastPayload payload = {
      "command": command,
      "options": options,
      "userId": user.id,
      "deviceId": _senderDeviceId,
      "accessToken": user.accessToken,
      "serverAddress": user.publicAddress,
      "serverId": user.serverId,
      "serverVersion": _serverInfo!.version,
      "receiverName": _device!.extras["fn"] ?? _device!.name,
    };

    _sendMessage(messageNamespace, payload);
  }

  void sendControlMessage(String type, [GoogleCastPayload options = const {}]) {
    _sendMessage(CastSession.kNamespaceReceiver, {"type": type, ...options});
  }

  void _sendMessage(String namespace, GoogleCastPayload payload) {
    _logger.finest("--> [$namespace]: $payload");
    _session!.sendMessage(namespace, payload);
  }

  // 0 = muted
  void mute() {
    return _setVolume(GoogleCastReceiverVolume(muted: true));
  }

  void unmute([double? volumeLevel]) {
    return _setVolume(GoogleCastReceiverVolume(muted: false, level: volumeLevel));
  }

  void setVolume(double level) {
    return _setVolume(GoogleCastReceiverVolume(level: level));
  }

  void _setVolume(GoogleCastReceiverVolume volume) {
    final payload = volume.toJson();
    if (payload.isEmpty) return;

    return sendControlMessage("SET_VOLUME", {"volume": payload});
  }

  /* command impl, full list here:
     https://github.com/jellyfin/jellyfin-chromecast/blob/f8e263eaf02b57e495330f5022b0e6b58918928b/src/components/commandHandler.ts#L27
     [ ] DisplayContent
     [x] Identify
     [x] InstantMix
     [!] Mute
     [x] NextTrack
     [x] Pause
     [x] PlayLast
     [x] PlayNext
     [x] PlayNow
     [x] PlayPause
     [x] PreviousTrack
     [x] Seek
     [ ] SetAudioStreamIndex
     [ ] SetRepeatMode
     [ ] SetSubtitleStreamIndex
     [!] SetVolume
     [x] Shuffle
     [x] Stop
     [!] ToggleMute
     [!] Unmute
     [x] Unpause
     [!] VolumeUp
     [!] VolumeDown

     ! volume is special and handled by google cast, not the receiver app,
       so the impl for those is above
   */

  void identify() {
    return sendMessage("Identify");
  }

  void playNow(List<GoogleCastMediaItem> items) {
    return _loadMedia("PlayNow", items);
  }

  void playNext(List<GoogleCastMediaItem> items) {
    return _loadMedia("PlayNext", items);
  }

  void playLast(List<GoogleCastMediaItem> items) {
    return _loadMedia("PlayLast", items);
  }

  void shuffle(GoogleCastMediaItem item) {
    return _loadMedia("Shuffle", [item]);
  }

  void instantMix(GoogleCastMediaItem item) {
    return _loadMedia("InstantMix", [item]);
  }

  void _loadMedia(String command, List<GoogleCastMediaItem> items) {
    return sendMessage(command, {"items": items.map((item) => item.toJson())});
  }

  void seek(double seconds) {
    /* this might be wrong? the ticks per second thing is weird
       https://github.com/jellyfin/jellyfin-chromecast/blob/f8e263eaf02b57e495330f5022b0e6b58918928b/src/components/commandHandler.ts#L155 */
    return sendMessage("Seek", {"position": seconds});
  }

  void pause() {
    return sendMessage("Pause");
  }

  void unpause() {
    return sendMessage("Unpause");
  }

  void playPause() {
    return sendMessage("PlayPause");
  }

  void stop() {
    return sendMessage("Stop");
  }

  void nextTrack() {
    return sendMessage("NextTrack");
  }

  void previousTrack() {
    return sendMessage("PreviousTrack");
  }

  void setRepeatMode(RepeatMode repeatMode) {
    return sendMessage("SetRepeatMode", {"RepeatMode": repeatMode.jellyfinName});
  }

  void _log(String message) {
    _logger.fine('[${_session?.sessionId} on "${_device?.name}"]: $message');
  }
}
