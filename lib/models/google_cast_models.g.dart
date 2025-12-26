// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: deprecated_member_use_from_same_package, strict_raw_type

// dart format off


part of 'google_cast_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GoogleCastPlaybackProgress _$GoogleCastPlaybackProgressFromJson(
  Map<String, dynamic> json,
) => GoogleCastPlaybackProgress(
  itemId: json['ItemId'] as String,
  playState: PlaybackProgressInfo.fromJson(
    json['PlayState'] as Map<String, dynamic>,
  ),
  nextMediaType: $enumDecodeNullable(_$MediaTypeEnumMap, json['NextMediaType']),
);

Map<String, dynamic> _$GoogleCastPlaybackProgressToJson(
  GoogleCastPlaybackProgress instance,
) => <String, dynamic>{
  'ItemId': instance.itemId,
  'PlayState': instance.playState.toJson(),
  'NextMediaType': _$MediaTypeEnumMap[instance.nextMediaType],
};

const _$MediaTypeEnumMap = {
  MediaType.unknown: 'Unknown',
  MediaType.audio: 'Audio',
  MediaType.book: 'Book',
  MediaType.photo: 'Photo',
  MediaType.video: 'Video',
};

GoogleCastMediaItem _$GoogleCastMediaItemFromJson(Map<String, dynamic> json) =>
    GoogleCastMediaItem(
      id: json['Id'] as String,
      serverId: json['ServerId'] as String,
      name: json['Name'] as String,
      type: $enumDecode(_$BaseItemKindEnumMap, json['Type']),
      mediaType: $enumDecode(_$MediaTypeEnumMap, json['MediaType']),
      isFolder: json['IsFolder'] as bool,
    );

Map<String, dynamic> _$GoogleCastMediaItemToJson(
  GoogleCastMediaItem instance,
) => <String, dynamic>{
  'Id': instance.id,
  'ServerId': instance.serverId,
  'Name': instance.name,
  'Type': _$BaseItemKindEnumMap[instance.type]!,
  'MediaType': _$MediaTypeEnumMap[instance.mediaType]!,
  'IsFolder': instance.isFolder,
};

const _$BaseItemKindEnumMap = {
  BaseItemKind.aggregateFolder: 'AggregateFolder',
  BaseItemKind.audio: 'Audio',
  BaseItemKind.audioBook: 'AudioBook',
  BaseItemKind.basePluginFolder: 'BasePluginFolder',
  BaseItemKind.book: 'Book',
  BaseItemKind.boxSet: 'BoxSet',
  BaseItemKind.channel: 'Channel',
  BaseItemKind.channelFolderItem: 'ChannelFolderItem',
  BaseItemKind.collectionFolder: 'CollectionFolder',
  BaseItemKind.episode: 'Episode',
  BaseItemKind.folder: 'Folder',
  BaseItemKind.genre: 'Genre',
  BaseItemKind.liveTvChannel: 'LiveTvChannel',
  BaseItemKind.liveTvProgram: 'LiveTvProgram',
  BaseItemKind.manualPlaylistsFolder: 'ManualPlaylistsFolder',
  BaseItemKind.movie: 'Movie',
  BaseItemKind.musicAlbum: 'MusicAlbum',
  BaseItemKind.musicArtist: 'MusicArtist',
  BaseItemKind.musicGenre: 'MusicGenre',
  BaseItemKind.musicVideo: 'MusicVideo',
  BaseItemKind.person: 'Person',
  BaseItemKind.photo: 'Photo',
  BaseItemKind.photoAlbum: 'PhotoAlbum',
  BaseItemKind.playlist: 'Playlist',
  BaseItemKind.playlistsFolder: 'PlaylistsFolder',
  BaseItemKind.program: 'Program',
  BaseItemKind.recording: 'Recording',
  BaseItemKind.season: 'Season',
  BaseItemKind.series: 'Series',
  BaseItemKind.studio: 'Studio',
  BaseItemKind.trailer: 'Trailer',
  BaseItemKind.tvChannel: 'TvChannel',
  BaseItemKind.tvProgram: 'TvProgram',
  BaseItemKind.userRootFolder: 'UserRootFolder',
  BaseItemKind.userView: 'UserView',
  BaseItemKind.video: 'Video',
  BaseItemKind.year: 'Year',
};

GoogleCastReceiverVolume _$GoogleCastReceiverVolumeFromJson(
  Map<String, dynamic> json,
) => GoogleCastReceiverVolume(
  level: (json['level'] as num?)?.toDouble(),
  muted: json['muted'] as bool?,
);

Map<String, dynamic> _$GoogleCastReceiverVolumeToJson(
  GoogleCastReceiverVolume instance,
) => <String, dynamic>{
  if (instance.level case final value?) 'level': value,
  if (instance.muted case final value?) 'muted': value,
};

GoogleCastReceiverStatus _$GoogleCastReceiverStatusFromJson(
  Map<String, dynamic> json,
) => GoogleCastReceiverStatus(
  volume: GoogleCastReceiverVolume.fromJson(
    json['volume'] as Map<String, dynamic>,
  ),
);

Map<String, dynamic> _$GoogleCastReceiverStatusToJson(
  GoogleCastReceiverStatus instance,
) => <String, dynamic>{'volume': instance.volume.toJson()};
