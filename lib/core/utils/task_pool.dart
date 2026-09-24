import 'dart:async';
import 'dart:collection';

/// Limita cuántas tareas asíncronas corren a la vez. Se usa para la EPG
/// corta: una lista con cientos de canales visibles no debe disparar cientos
/// de peticiones simultáneas al panel.
class TaskPool {
  TaskPool(this.maxConcurrent) : assert(maxConcurrent > 0);

  final int maxConcurrent;
  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue();

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= maxConcurrent) {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }
}
