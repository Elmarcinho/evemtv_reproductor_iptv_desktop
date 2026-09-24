import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'media_engine.dart';

/// Motor de video compartido. El reproductor (Fase 2) llama a
/// `ensureReady()` antes de crear un `Player`.
final mediaEngineProvider = Provider<MediaEngine>((ref) => MediaEngine());
