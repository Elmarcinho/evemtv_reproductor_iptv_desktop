import 'dart:async';
import 'dart:collection';

/// La tarea se descartó antes de ejecutarse (ya nadie la necesitaba).
class TaskCancelledException implements Exception {
  const TaskCancelledException();

  @override
  String toString() => 'TaskCancelledException';
}

/// Limita cuántas tareas asíncronas corren a la vez. Se usa para la EPG
/// corta: una lista con cientos de canales visibles no debe disparar cientos
/// de peticiones simultáneas al panel.
///
/// Limitar la concurrencia no alcanza: al recorrer miles de canales, la cola
/// crece. Por eso cada tarea puede indicar [run.isCancelled] (se comprueba
/// al llegarle el turno) y [cancelAll] descarta toda la cola pendiente.
class TaskPool {
  TaskPool(this.maxConcurrent) : assert(maxConcurrent > 0);

  final int maxConcurrent;
  int _running = 0;
  bool _closed = false;

  /// `true` = la tarea puede correr; `false` = se canceló en espera.
  final Queue<Completer<bool>> _waiting = Queue();

  int get pending => _waiting.length;

  Future<T> run<T>(
    Future<T> Function() task, {
    bool Function()? isCancelled,
  }) async {
    if (_closed) throw const TaskCancelledException();
    if (_running >= maxConcurrent) {
      final slot = Completer<bool>();
      _waiting.add(slot);
      if (!await slot.future) throw const TaskCancelledException();
    } else {
      _running++;
    }
    // Aquí la tarea tiene su lugar (_running ya la cuenta).
    try {
      if (isCancelled?.call() ?? false) throw const TaskCancelledException();
      return await task();
    } finally {
      _release();
    }
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // El lugar pasa directo a la siguiente: _running no cambia.
      _waiting.removeFirst().complete(true);
    } else {
      _running--;
    }
  }

  /// Descarta todas las tareas en espera y las que se pidan después.
  void cancelAll() {
    _closed = true;
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete(false);
    }
  }
}
