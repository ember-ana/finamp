import 'package:finamp/models/jellyfin_models.dart';
import 'package:json_annotation/json_annotation.dart';

part 'google_cast_models.g.dart';

typedef GoogleCastPayload = Map<String, dynamic>;

@JsonSerializable(fieldRename: FieldRename.pascal, explicitToJson: true)
class GoogleCastPlaybackProgress {
  GoogleCastPlaybackProgress({required this.itemId, required this.playState, this.nextMediaType});

  final String itemId;
  final PlaybackProgressInfo playState;
  final MediaType? nextMediaType;
  /* missing NowPlayingItem because it feels a bit pointless
     https://github.com/jellyfin/jellyfin-chromecast/blob/f8e263eaf02b57e495330f5022b0e6b58918928b/src/helpers.ts#L112 */

  factory GoogleCastPlaybackProgress.fromJson(GoogleCastPayload json) => _$GoogleCastPlaybackProgressFromJson(json);
  GoogleCastPayload toJson() => _$GoogleCastPlaybackProgressToJson(this);
}

// https://github.com/jellyfin/jellyfin-web/blob/ed4417b7de88bce02992f0ab91cde230c05d9fed/src/plugins/chromecastPlayer/plugin.js#L306
// https://typescript-sdk.jellyfin.org/interfaces/generated-client.BaseItemDto.html
@JsonSerializable(fieldRename: FieldRename.pascal, explicitToJson: true)
class GoogleCastMediaItem {
  const GoogleCastMediaItem({
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
  final BaseItemKind type;
  final MediaType mediaType;
  final bool isFolder;

  factory GoogleCastMediaItem.fromJson(GoogleCastPayload json) => _$GoogleCastMediaItemFromJson(json);
  GoogleCastPayload toJson() => _$GoogleCastMediaItemToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class GoogleCastReceiverVolume {
  const GoogleCastReceiverVolume({this.level, this.muted});
  final double? level;
  final bool? muted;
  // ignored: stepInterval, controlType

  factory GoogleCastReceiverVolume.fromJson(GoogleCastPayload json) => _$GoogleCastReceiverVolumeFromJson(json);
  GoogleCastPayload toJson() => _$GoogleCastReceiverVolumeToJson(this);
}

@JsonSerializable(explicitToJson: true)
class GoogleCastReceiverStatus {
  const GoogleCastReceiverStatus({required this.volume});
  final GoogleCastReceiverVolume volume;

  /* null-safety: volume is always present
     src: https://docs.rs/crate/gcast/0.1.5/source/PROTOCOL.md#256 */
  factory GoogleCastReceiverStatus.fromJson(GoogleCastPayload json) => _$GoogleCastReceiverStatusFromJson(json);
  GoogleCastPayload toJson() => _$GoogleCastReceiverStatusToJson(this);
}
