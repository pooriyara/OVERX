import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/l10n/strings.dart';

/// رشته‌های ترجمه‌شده با توجه به زبانِ فعلی در تنظیمات.
final stringsProvider = Provider<Strings>((ref) {
  return Strings(ref.watch(settingsProvider).lang);
});
