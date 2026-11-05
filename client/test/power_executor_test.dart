import 'package:cauce_stream/models/playback_message.dart';
import 'package:cauce_stream/services/power_executor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cauce.power/power');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mockHandler(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  test('wakeScreen pasa por el canal y devuelve el resultado nativo',
      () async {
    final methods = <String>[];
    mockHandler((call) {
      methods.add(call.method);
      return true;
    });

    expect(await const MethodChannelPowerExecutor().wakeScreen(), isTrue);
    expect(methods, ['wakeScreen']);
  });

  test('enterStandby false nativo (Android) se propaga tal cual', () async {
    mockHandler((call) => false);

    expect(await const MethodChannelPowerExecutor().enterStandby(), isFalse);
  });

  test('respuestas nulas del canal: false, nunca un éxito falso', () async {
    mockHandler((call) => null);

    expect(await const MethodChannelPowerExecutor().wakeScreen(), isFalse);
  });

  test('MissingPluginException → PowerExecutorException platform_unsupported',
      () async {
    // Sin handler mockeado el binding lanza MissingPluginException: es el
    // caso de una plataforma sin implementación nativa.
    await expectLater(
      const MethodChannelPowerExecutor().enterStandby(),
      throwsA(
        isA<PowerExecutorException>()
            .having((e) => e.code, 'code', PowerErrorCodes.platformUnsupported),
      ),
    );
  });

  test('PlatformException nativa → PowerExecutorException con su código',
      () async {
    mockHandler((call) => throw PlatformException(
          code: 'security',
          message: 'wakelock denegado',
        ));

    await expectLater(
      const MethodChannelPowerExecutor().wakeScreen(),
      throwsA(
        isA<PowerExecutorException>()
            .having((e) => e.code, 'code', 'security')
            .having((e) => e.message, 'message', 'wakelock denegado'),
      ),
    );
  });

  test('getPowerCapabilities parsea el mapa nativo', () async {
    mockHandler((call) {
      expect(call.method, 'getPowerCapabilities');
      return {
        'can_wake': true,
        'can_standby': true,
        'device_owner': true,
        'admin_active': true,
      };
    });

    final caps = await const MethodChannelPowerExecutor().capabilities();
    expect(caps.canWake, isTrue);
    expect(caps.canStandby, isTrue);
    expect(caps.deviceOwner, isTrue);
    expect(caps.adminActive, isTrue);
  });

  test('getPowerCapabilities sin aprovisionamiento: can_standby false',
      () async {
    mockHandler((call) => {
          'can_wake': true,
          'can_standby': false,
          'device_owner': false,
          'admin_active': false,
        });

    final caps = await const MethodChannelPowerExecutor().capabilities();
    expect(caps.canWake, isTrue);
    expect(caps.canStandby, isFalse);
    expect(caps.deviceOwner, isFalse);
  });

  test('getPowerCapabilities con respuesta no-mapa → platform_unsupported',
      () async {
    mockHandler((call) => true);

    await expectLater(
      const MethodChannelPowerExecutor().capabilities(),
      throwsA(
        isA<PowerExecutorException>()
            .having((e) => e.code, 'code', PowerErrorCodes.platformUnsupported),
      ),
    );
  });

  test('requestDeviceAdmin pasa por el canal y devuelve el resultado nativo',
      () async {
    final methods = <String>[];
    mockHandler((call) {
      methods.add(call.method);
      return true;
    });

    expect(await const MethodChannelPowerExecutor().requestDeviceAdmin(),
        isTrue);
    expect(methods, ['requestDeviceAdmin']);
  });
}
