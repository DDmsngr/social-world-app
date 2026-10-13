import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/stickers.dart';

/// Фирменные стикеры: вшиты в приложение, работают без сети.
final stickerCatalogProvider = FutureProvider<StickerCatalog>((ref) async {
  final raw = await rootBundle.loadString('assets/stickers/manifest.json');
  return StickerCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
});
