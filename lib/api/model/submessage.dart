import 'package:json_annotation/json_annotation.dart';

part 'submessage.g.dart';

/// Data used for Zulip "widgets" within messages, like polls and todo lists.
///
/// For docs, see:
///   https://zulip.com/api/get-messages#response (search for "submessage")
///   https://zulip.readthedocs.io/en/latest/subsystems/widgets.html
///
/// This is an underdocumented part of the Zulip Server API.
/// So in addition to docs, see other clients:
///   https://github.com/zulip/zulip-mobile/blob/2217c858e/src/api/modelTypes.js#L800-L861
///   https://github.com/zulip/zulip-mobile/blob/2217c858e/src/webview/html/message.js#L118-L192
///   https://github.com/zulip/zulip/blob/40f59a05c/web/src/submessage.ts
///   https://github.com/zulip/zulip/blob/40f59a05c/web/shared/src/poll_data.ts
@JsonSerializable(fieldRename: FieldRename.snake)
class Submessage {
  const Submessage({
    required this.senderId,
    required this.msgType,
    required this.content,
  });

  // TODO(server): should we be sorting a message's submessages by ID?  Web seems to:
  //   https://github.com/zulip/zulip/blob/40f59a05c55e0e4f26ca87d2bca646770e94bff0/web/src/submessage.ts#L88
  // final int id;  // ignored because we don't use it

  /// The sender of this submessage (not necessarily of the [Message] it's on).
  final int senderId;

  // final int messageId;  // ignored; redundant with [Message.id]

  @JsonKey(unknownEnumValue: SubmessageType.unknown)
  final SubmessageType msgType;

  /// A JSON encoding of a [SubmessageData].
  // We cannot parse the String into one of the [SubmessageData] classes because
  // information from other submessages are required. Specifically, we need:
  //   * the index of this submessage in [Message.submessages];
  //   * the [WidgetType] of the first [Message.submessages].
  final String content;

  factory Submessage.fromJson(Map<String, Object?> json) =>
    _$SubmessageFromJson(json);

  Map<String, Object?> toJson() => _$SubmessageToJson(this);
}

/// As in [Submessage.msgType].
///
/// The only type of submessage that actually exists in Zulip (as of 2024,
/// and since this "submessages" subsystem was created in 2017–2018)
/// is [SubmessageType.widget].
enum SubmessageType {
  widget,
  unknown,
}

sealed class SubmessageData {}

/// The data encoded in a submessage to make the message a Zulip widget.
///
/// Expected from the first [Submessage.content] in the "submessages" field on
/// the message when there is an widget.
///
/// See https://zulip.readthedocs.io/en/latest/subsystems/widgets.html
sealed class WidgetData extends SubmessageData {
  WidgetType get widgetType;

  WidgetData();

  factory WidgetData.fromJson(Object? json) {
    final map = json as Map<String, Object?>;
    final rawWidgetType = map['widget_type'] as String;
    return switch (WidgetType.fromRawString(rawWidgetType)) {
      WidgetType.poll => PollWidgetData.fromJson(map),
      WidgetType.unknown => UnsupportedWidgetData.fromJson(map),
    };
  }

  Object? toJson();
}

/// As in [WidgetData.widgetType].
@JsonEnum(alwaysCreate: true)
enum WidgetType {
  poll,
  unknown;

  static WidgetType fromRawString(String raw) => _byRawString[raw] ?? unknown;

  static final _byRawString = _$WidgetTypeEnumMap
    .map((key, value) => MapEntry(value, key));
}

/// The data encoded in a submessage to make the message a poll widget.
@JsonSerializable(fieldRename: FieldRename.snake)
class PollWidgetData extends WidgetData {
  @override
  @JsonKey(includeToJson: true)
  WidgetType get widgetType => WidgetType.poll;

  /// The initial question and options on the poll.
  final PollWidgetExtraData extraData;

  PollWidgetData({required this.extraData});

  factory PollWidgetData.fromJson(Map<String, Object?> json) =>
    _$PollWidgetDataFromJson(json);

  @override
  Map<String, Object?> toJson() => _$PollWidgetDataToJson(this);
}

/// As in [PollWidgetData.extraData].
@JsonSerializable(fieldRename: FieldRename.snake)
class PollWidgetExtraData {
  // The [question] and [options] fields seem to be always present.
  // But both web and zulip-mobile accept them as optional, with default values:
  //   https://github.com/zulip/zulip-flutter/pull/823#discussion_r1697656896
  //   https://github.com/zulip/zulip/blob/40f59a05c55e0e4f26ca87d2bca646770e94bff0/web/src/poll_widget.ts#L29
  // And the server doesn't really enforce any structure on submessage data.
  // So match the web and zulip-mobile behavior.
  @JsonKey(defaultValue: "")
  final String question;
  @JsonKey(defaultValue: [])
  final List<String> options;

  const PollWidgetExtraData({required this.question, required this.options});

  factory PollWidgetExtraData.fromJson(Map<String, Object?> json) =>
    _$PollWidgetExtraDataFromJson(json);

  Map<String, Object?> toJson() => _$PollWidgetExtraDataToJson(this);
}

class UnsupportedWidgetData extends WidgetData {
  @override
  @JsonKey(includeToJson: true)
  WidgetType get widgetType => WidgetType.unknown;

  final Object? json;

  UnsupportedWidgetData.fromJson(this.json);

  @override
  Object? toJson() => json;
}

/// The data encoded in a submessage that acts on a poll.
sealed class PollEventSubmessage extends SubmessageData {
  PollEventSubmessageType get type;

  PollEventSubmessage();

  /// The key for identifying the [idx]'th option added by user
  /// [senderId] to a poll.
  ///
  /// For options that are a part of the initial [PollWidgetData], the
  /// [senderId] should be `null`.
  static String optionKey({required int? senderId, required int idx}) =>
    // "canned" is a canonical constant coined by the web client.
    '${senderId ?? 'canned'},$idx';

  factory PollEventSubmessage.fromJson(Map<String, Object?> json) {
    final rawPollEventType = json['type'] as String;
    switch (PollEventSubmessageType.fromRawString(rawPollEventType)) {
      case PollEventSubmessageType.newOption: return PollNewOptionEventSubmessage.fromJson(json);
      case PollEventSubmessageType.question: return PollQuestionEventSubmessage.fromJson(json);
      case PollEventSubmessageType.vote: return PollVoteEventSubmessage.fromJson(json);
      case PollEventSubmessageType.unknown: return UnknownPollEventSubmessage.fromJson(json);
    }
  }

  Map<String, Object?> toJson();
}

/// As in [PollEventSubmessage.type].
@JsonEnum(fieldRename: FieldRename.snake)
enum PollEventSubmessageType {
  newOption,
  question,
  vote,
  unknown;

  static PollEventSubmessageType fromRawString(String raw) => _byRawString[raw]!;

  static final _byRawString = _$PollEventSubmessageTypeEnumMap
    .map((key, value) => MapEntry(value, key));
}

/// A poll event when an option is added.
@JsonSerializable(fieldRename: FieldRename.snake)
class PollNewOptionEventSubmessage extends PollEventSubmessage {
  @override
  @JsonKey(includeToJson: true)
  PollEventSubmessageType get type => PollEventSubmessageType.newOption;

  final String option;
  /// A sequence number for this option, among options added to this poll
  /// by this [Submessage.senderId].
  ///
  /// See [PollEventSubmessage.optionKey].
  final int idx;

  PollNewOptionEventSubmessage({required this.option, required this.idx});

  @override
  factory PollNewOptionEventSubmessage.fromJson(Map<String, Object?> json) =>
    _$PollNewOptionEventSubmessageFromJson(json);

  @override
  Map<String, Object?> toJson() => _$PollNewOptionEventSubmessageToJson(this);
}

/// A poll event when the question has been edited.
@JsonSerializable(fieldRename: FieldRename.snake)
class PollQuestionEventSubmessage extends PollEventSubmessage {
  @override
  @JsonKey(includeToJson: true)
  PollEventSubmessageType get type => PollEventSubmessageType.question;

  final String question;

  PollQuestionEventSubmessage({required this.question});

  @override
  factory PollQuestionEventSubmessage.fromJson(Map<String, Object?> json) =>
    _$PollQuestionEventSubmessageFromJson(json);

  @override
  Map<String, Object?> toJson() => _$PollQuestionEventSubmessageToJson(this);
}

/// A poll event when a vote has been cast or removed.
@JsonSerializable(fieldRename: FieldRename.snake)
class PollVoteEventSubmessage extends PollEventSubmessage {
  @override
  @JsonKey(includeToJson: true)
  PollEventSubmessageType get type => PollEventSubmessageType.vote;

  /// The key of the affected option.
  ///
  /// See [PollEventSubmessage.optionKey].
  final String key;
  @JsonKey(name: 'vote', unknownEnumValue: PollVoteOp.unknown)
  final PollVoteOp op;

  PollVoteEventSubmessage({required this.key, required this.op});

  @override
  factory PollVoteEventSubmessage.fromJson(Map<String, Object?> json) {
    final result = _$PollVoteEventSubmessageFromJson(json);
    // Crunchy-shell validation
    final segments = result.key.split(',');
    final [senderId, idx] = segments;
    if (senderId != 'canned') {
      int.parse(senderId, radix: 10);
    }
    int.parse(idx, radix: 10);
    return result;
  }

  @override
  Map<String, Object?> toJson() => _$PollVoteEventSubmessageToJson(this);
}

/// As in [PollVoteEventSubmessage.op].
@JsonEnum(valueField: 'apiValue')
enum PollVoteOp {
  add(apiValue: 1),
  remove(apiValue: -1),
  unknown(apiValue: null);

  const PollVoteOp({required this.apiValue});

  final int? apiValue;

  int? toJson() => apiValue;
}

class UnknownPollEventSubmessage extends PollEventSubmessage {
  @override
  @JsonKey(includeToJson: true)
  PollEventSubmessageType get type => PollEventSubmessageType.unknown;

  final Map<String, Object?> json;

  UnknownPollEventSubmessage.fromJson(this.json);

  @override
  Map<String, Object?> toJson() => json;
}