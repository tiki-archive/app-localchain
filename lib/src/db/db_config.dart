/*
 * Copyright (c) TIKI Inc.
 * MIT license. See LICENSE file in root directory.
 */

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

import '../block/block_model.dart';
import '../block/contents/block_contents_start.dart';
import '../crypto/crypto.dart' as crypto;
import '../key_store/key_store_service.dart';

//todo move this into utils
class DbConfig {
  static const int _version = 1;
  static const String _startContents = "START";
  final _log = Logger('DbConfig');
  late Database database;

  Future<void> init(KeyStoreService keyStoreService) async {
    database = await openDatabase(await getDatabasesPath() + '/blockchain.db',
        version: _version,
        onConfigure: onConfigure,
        onCreate: (Database db, int version) =>
            onCreate(db, version, keyStoreService),
        onUpgrade: onUpgrade,
        onDowngrade: onDowngrade,
        onOpen: onOpen,
        singleInstance: true);
  }

  Future<void> onConfigure(Database db) async {
    _log.finest('configure');
  }

  Future<void> onCreate(
      Database db, int version, KeyStoreService keyStoreService) async {
    _log.info('create');
    String createSqlScript = await rootBundle
        .loadString('packages/localchain/src/db/db_create_tables.sql');
    List<String> createSqls = createSqlScript.split(";");
    for (String createSql in createSqls) {
      String sql = createSql.trim();
      if (sql.isNotEmpty) await db.execute(sql);
    }
    await firstBlock(keyStoreService, db);
  }

  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    _log.finest('upgrade');
  }

  Future<void> onDowngrade(Database db, int oldVersion, int newVersion) async {
    _log.finest('downgrade');
  }

  Future<void> onOpen(Database db) async {
    _log.finest('open');
  }

  Future<void> firstBlock(KeyStoreService keyStoreService, Database db) async {
    Uint8List cipherText = crypto.rsaEncrypt(keyStoreService.dataKey!.publicKey,
        BlockContentsStart(start: _startContents).toBytes());
    Uint8List signature =
        crypto.ecdsaSign(keyStoreService.signKey!.privateKey, cipherText);

    await db.insert(
        "block",
        BlockModel(
                contents: cipherText,
                signature: signature,
                previousHash: Uint8List.fromList(List.empty()),
                created: DateTime.now())
            .toMap());
  }
}
