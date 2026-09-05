import '../core/adb/adb_client.dart';
import '../core/config/app_config.dart';
import '../core/log/log_service.dart';
import '../core/thumbnails/thumbnail_service.dart';
import '../core/transfer/transfer_service.dart';

/// Composition root. Single place where singletons are fetched from, so
/// widgets and controllers never reach across layers ad hoc.
class Services {
  Services._();

  static final AdbClient adb = AdbClient.instance;
  static final AppConfig config = AppConfig.instance;
  static final LogService log = LogService.instance;
  static final TransferService transfers = TransferService.instance;
  static final ThumbnailService thumbnails = ThumbnailService.instance;

  static Future<void> init() => config.load();
}
