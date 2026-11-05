import 'package:cauce_stream/services/url_load_gate.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pageFinished confirma (true) una sola vez y cancela el timeout', () {
    fakeAsync((async) {
      final results = <(bool, String?)>[];
      final gate = UrlLoadGate(
        timeout: const Duration(seconds: 30),
        onResult: (displayed, error) => results.add((displayed, error)),
      );

      gate.pageFinished();
      async.elapse(const Duration(seconds: 31));

      expect(results, [(true, null)]);
      expect(gate.isSettled, isTrue);
    });
  });

  test('error del frame principal falla con la descripción y corta el timeout',
      () {
    fakeAsync((async) {
      final results = <(bool, String?)>[];
      final gate = UrlLoadGate(
        timeout: const Duration(seconds: 30),
        onResult: (displayed, error) => results.add((displayed, error)),
      );

      gate.mainFrameError('ERR_CONNECTION_REFUSED');
      async.elapse(const Duration(seconds: 31));

      expect(results, [(false, 'ERR_CONNECTION_REFUSED')]);
    });
  });

  test('timeout: si nada confirma antes, el resultado es false', () {
    fakeAsync((async) {
      final results = <(bool, String?)>[];
      UrlLoadGate(
        timeout: const Duration(seconds: 30),
        onResult: (displayed, error) => results.add((displayed, error)),
      );

      async.elapse(const Duration(seconds: 31));

      expect(results, hasLength(1));
      expect(results.single.$1, isFalse);
      expect(results.single.$2, contains('tiempo de carga agotado'));
    });
  });

  test('dispose antes de resolver reporta false (el showUrl no queda colgado)',
      () {
    fakeAsync((async) {
      final results = <(bool, String?)>[];
      final gate = UrlLoadGate(
        timeout: const Duration(seconds: 30),
        onResult: (displayed, error) => results.add((displayed, error)),
      );

      gate.dispose();
      async.elapse(const Duration(seconds: 31));

      expect(results, [(false, 'WebView desmontado antes de cargar')]);
    });
  });

  test('solo el primer evento cuenta', () {
    fakeAsync((async) {
      final results = <(bool, String?)>[];
      final gate = UrlLoadGate(
        timeout: const Duration(seconds: 30),
        onResult: (displayed, error) => results.add((displayed, error)),
      );

      gate.pageFinished();
      gate.mainFrameError('evento tardío');
      gate.dispose();

      expect(results, [(true, null)]);
    });
  });
}
