library localchain;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

import 'src/block/block_model.dart';
import 'src/block/block_repository.dart';
import 'src/block/block_service.dart';
import 'src/block/contents/block_contents.dart';
import 'src/cache/cache_model.dart';
import 'src/cache/cache_model_response.dart';
import 'src/cache/cache_repository.dart';
import 'src/cache/cache_service.dart';
import 'src/crypto/crypto.dart' as crypto;
import 'src/db/db_config.dart';
import 'src/db/db_page.dart';
import 'src/key_store/key_store_exception.dart';
import 'src/key_store/key_store_service.dart';

export 'src/block/block_model.dart';
export 'src/block/contents/block_contents.dart';
export 'src/block/contents/block_contents_bytea.dart';
export 'src/block/contents/block_contents_json.dart';
export 'src/block/contents/block_contents_start.dart';
export 'src/cache/cache_model.dart';
export 'src/cache/cache_model_response.dart';
export 'src/key_store/key_store_model.dart';

class Localchain {
  static const int _pageSize = 100;
  final log = Logger('Localchain');
  final DbConfig _dbConfig = DbConfig();
  final KeyStoreService keystore;
  late final CacheService _cacheService;
  late final BlockService _blockService;

  Localchain({FlutterSecureStorage? secureStorage})
      : this.keystore = KeyStoreService(secureStorage: secureStorage);

  Future<void> open(
      {Function(bool isOpen)? onComplete, bool overwrite = true}) async {
    await _dbConfig.init(keystore);
    this._cacheService = CacheService(_dbConfig.database);
    this._blockService = BlockService(_dbConfig.database, keystore);
    verify().then((bool isVerified) async {
      bool isOpen = true;
      if (!isVerified && overwrite) {
        await _dbConfig.database.delete(BlockRepository.table);
        await _dbConfig.database.delete(CacheRepository.table);
        await _dbConfig.firstBlock(keystore, _dbConfig.database);
      } else if (!isVerified) {
        await _dbConfig.database.close();
        isOpen = false;
      }
      if (onComplete != null) await onComplete(isOpen);
    });
  }

  Future<BlockModel> add(BlockContents blockContents) async {
    _keyGuard();
    BlockModel block = await _blockService.add(blockContents);
    await _cacheService.insert(CacheModel(
        contents: blockContents.toBytes(),
        cached: DateTime.now(),
        block: block));
    return block;
  }

  Future<CacheModelResponse?> get(int id) => _cacheService.get(id);

  Future<bool> verify() async {
    _keyGuard();
    try {
      BlockModel last = await _blockService.last();
      DbPage<BlockModel> page = await _blockService.page(0, _pageSize);
      while (page.pageNumber! < page.totalPages!) {
        for (BlockModel block in page.elements) {
          if (!_blockService.verifySignature(block)) return false;
          if (!_blockService.verifyContents(block)) return false;
          if (block.id != last.id && !await _blockService.verifyHash(block))
            return false;
          log.finest("Block #" + block.id.toString() + " passed verification");
        }
        page = await _blockService.page(page.pageNumber! + 1, _pageSize);
      }
      log.info("Chain passed verification");
      return true;
    } catch (e) {
      log.info("Chain failed verification", e);
      return false;
    }
  }

  Future<bool> refresh() async {
    _keyGuard();
    try {
      await _cacheService.drop();
      BlockModel last = await _blockService.last();
      DbPage<BlockModel> page = await _blockService.page(0, _pageSize);
      while (page.pageNumber! < page.totalPages!) {
        for (BlockModel block in page.elements) {
          if (!_blockService.verifySignature(block)) return false;
          if (last.id != block.id && !await _blockService.verifyHash(block))
            return false;
          try {
            await _cacheService.insert(CacheModel(
                contents: crypto.rsaDecrypt(
                    keystore.dataKey!.privateKey, block.contents!),
                cached: DateTime.now(),
                block: block));
          } catch (_) {
            log.info("Failed to cache Block #" + block.id.toString());
            return false;
          }
          log.finest("Block #" + block.id.toString() + " cached");
        }
        page = await _blockService.page(page.pageNumber! + 1, _pageSize);
      }
      log.info("Cache refresh success");
      return true;
    } catch (e) {
      log.info("Cache refresh failed", e);
      return false;
    }
  }

  void _keyGuard() {
    if (keystore.signKey == null || keystore.dataKey == null)
      throw KeyStoreException("Missing required keys",
          address: keystore.active?.address);
  }
}
