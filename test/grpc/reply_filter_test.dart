import 'dart:io';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

ReplyInfo _reply({
  int mid = 1,
  String name = '普通用户',
  String message = '普通评论',
  int? level,
}) {
  return ReplyInfo(
    mid: Int64(mid),
    member: Member(name: name, level: level == null ? null : Int64(level)),
    content: Content(message: message),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-reply-filter-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
  });

  setUp(() async {
    await GStorage.setting.clear();
    ReplyGrpc.replyRegExp = RegExp('');
    ReplyGrpc.enableFilter = false;
    ReplyGrpc.replyNameRegExp = RegExp('');
    ReplyGrpc.blockReplyLevel = 0;
    ReplyGrpc.blockReplyAtCount = null;
    ReplyGrpc.blockAtOnlyReply = false;
    ReplyGrpc.antiGoodsReply = false;
    GlobalData().blackMids = {};
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('等级门槛严格小于，默认禁用，缺失 level 不误滤', () {
    final cases = <(ReplyInfo, int, bool)>[
      (_reply(level: 2), 0, false),
      (_reply(level: 2), 3, true),
      (_reply(level: 3), 3, false),
      (_reply(level: 6), 6, false),
      (_reply(level: 1), 6, true),
      (_reply(), 3, false),
      (ReplyInfo(), 3, false),
    ];
    for (final (i, (reply, level, removed)) in cases.indexed) {
      ReplyGrpc.blockReplyLevel = level;
      expect(
        ReplyGrpc.needRemoveGrpc(reply),
        removed,
        reason: 'case $i, blockLevel=$level',
      );
    }
  });

  test('昵称关键词只匹配昵称，不匹配正文', () {
    ReplyGrpc.replyNameRegExp = RegExp('测试|bot', caseSensitive: false);
    expect(
      ReplyGrpc.needRemoveGrpc(_reply(name: '测试账号', message: '正常评论')),
      isTrue,
    );
    expect(ReplyGrpc.needRemoveGrpc(_reply(name: 'BOT小助手')), isTrue);
    expect(
      ReplyGrpc.needRemoveGrpc(_reply(name: '普通用户', message: '测试正文')),
      isFalse,
    );
  });

  test('空昵称不会被空正则命中', () {
    ReplyGrpc.replyNameRegExp = RegExp(r'^$');
    expect(ReplyGrpc.needRemoveGrpc(_reply(name: '')), isFalse);
  });

  test('旧正文关键词过滤与黑名单保持有效', () {
    ReplyGrpc.replyRegExp = RegExp('广告');
    ReplyGrpc.enableFilter = true;
    expect(ReplyGrpc.needRemoveGrpc(_reply(message: '这里有广告')), isTrue);

    GlobalData().blackMids = {123};
    expect(ReplyGrpc.needRemoveGrpc(_reply(mid: 123)), isTrue);
  });
}
