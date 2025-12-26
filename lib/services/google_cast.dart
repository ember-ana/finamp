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
const ticksPerSecond =
    10000000; // ref: https://github.com/jellyfin/jellyfin-chromecast/blob/f8e263eaf02b57e495330f5022b0e6b58918928b/src/helpers.ts#L43

final _jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
final _finampUserHelper = GetIt.instance<FinampUserHelper>();

typedef CastMessagePayload = Map<String, dynamic>;

enum JellyfinRepeatMode { all, one, none }

// https://typescript-sdk.jellyfin.org/enums/generated-client.MediaType.html
enum CastMediaType { audio, book, photo, video, unknown }

// https://typescript-sdk.jellyfin.org/enums/generated-client.BaseItemKind.html
// incomplete
enum CastItemType {
  audio,
  folder,
  manualPlaylistsFolder,
  musicAlbum,
  musicArtist,
  musicGenre,
  musicVideo,
  playlist,
  recording,
}

// https://github.com/jellyfin/jellyfin-web/blob/ed4417b7de88bce02992f0ab91cde230c05d9fed/src/plugins/chromecastPlayer/plugin.js#L306
// https://typescript-sdk.jellyfin.org/interfaces/generated-client.BaseItemDto.html
class CastMediaItem {
  const CastMediaItem({
    required this.id,
    required this.serverId,
    required this.name,
    required this.type,
    required this.mediaType,
    required this.isFolder,
  });

  final String id;
  final String serverId;
  final String name;
  final CastItemType type;
  final CastMediaType mediaType;
  final bool isFolder;

  static String stringifyMediaType(CastMediaType castMediaType) {
    switch (castMediaType) {
      case CastMediaType.audio:
        return "Audio";
      case CastMediaType.book:
        return "Book";
      case CastMediaType.photo:
        return "Photo";
      case CastMediaType.video:
        return "Video";
      case CastMediaType.unknown:
        return "Unknown";
    }
  }

  static String stringifyType(CastItemType castItemType) {
    switch (castItemType) {
      case CastItemType.audio:
        return "Audio";
      case CastItemType.folder:
        return "Folder";
      case CastItemType.manualPlaylistsFolder:
        return "ManualPlaylistsFolder";
      case CastItemType.musicAlbum:
        return "MusicAlbum";
      case CastItemType.musicArtist:
        return "MusicArtist";
      case CastItemType.musicGenre:
        return "MusicGenre";
      case CastItemType.musicVideo:
        return "MusicVideo";
      case CastItemType.playlist:
        return "Playlist";
      case CastItemType.recording:
        return "Recording";
    }
  }

  CastMessagePayload toPayload() {
    return {
      "Id": id,
      "ServerId": serverId,
      "Name": name,
      "Type": CastMediaItem.stringifyType(type),
      "MediaType": CastMediaItem.stringifyMediaType(mediaType),
      "IsFolder": isFolder,
    };
  }
}

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

    /* not sure why this is necessary
       see: https://github.com/jellyfin/jellyfin-web/blob/ed4417b7de88bce02992f0ab91cde230c05d9fed/src/plugins/chromecastPlayer/plugin.js#L248 */
    identify();
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
    sendControlMessage("LAUNCH", {"appId": appId});

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

  void sendControlMessage(String type, [CastMessagePayload options = const {}]) {
    _sendMessage(CastSession.kNamespaceReceiver, {"type": type, ...options});
  }

  void _sendMessage(String namespace, CastMessagePayload payload) {
    _logger.finest("--> [$namespace]: $payload");
    session!.sendMessage(namespace, payload);
  }

  // 0 = muted
  void mute() {
    return _setVolume(muted: true);
  }

  void unmute([double? volumeLevel]) {
    return _setVolume(muted: false, level: volumeLevel);
  }

  void setVolume(double level) {
    return _setVolume(level: level);
  }

  void _setVolume({bool? muted, double? level}) {
    CastMessagePayload payload = {};

    if (muted != null) {
      payload["muted"] = muted;
    }
    if (level != null) {
      payload["level"] = level;
    }
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

  void playNow(List<CastMediaItem> items) {
    return _loadMedia("PlayNow", items);
  }

  void playNext(List<CastMediaItem> items) {
    return _loadMedia("PlayNext", items);
  }

  void playLast(List<CastMediaItem> items) {
    return _loadMedia("PlayLast", items);
  }

  void shuffle(CastMediaItem item) {
    return _loadMedia("Shuffle", [item]);
  }

  void instantMix(CastMediaItem item) {
    return _loadMedia("InstantMix", [item]);
  }

  void _loadMedia(String command, List<CastMediaItem> items) {
    return sendMessage(command, {"items": items.map((item) => item.toPayload())});
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

  void setRepeatMode(JellyfinRepeatMode repeatMode) {
    late String payload;
    // ref: https://typescript-sdk.jellyfin.org/enums/generated-client.RepeatMode.html
    switch (repeatMode) {
      case JellyfinRepeatMode.all:
        payload = "RepeatAll";
      case JellyfinRepeatMode.one:
        payload = "RepeatOne";
      case JellyfinRepeatMode.none:
        payload = "RepeatNone";
    }
    return sendMessage("SetRepeatMode", {"RepeatMode": payload});
  }

  void _log(String message) {
    _logger.fine('[${session?.sessionId} on "${device?.name}"]: $message');
  }
}
