import 'package:age_range_signals/age_range_signals.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/services/age_signals_source.dart';

/// Stands in for the plugin singleton; unused methods fall to noSuchMethod.
class _FakePlugin implements AgeRangeSignals {
  _FakePlugin({
    this.access = AgeSignalsAccessStatus.shared,
    this.result,
    this.error,
    this.checkError,
    this.initError,
  });

  AgeSignalsAccessStatus access;
  AgeSignalsResult? result;
  Object? error;

  /// Thrown by [checkAgeSignals], where iOS reports `notAvailable`.
  Object? checkError;
  Object? initError;
  final List<List<int>?> initCalls = [];
  int checkCalls = 0;
  int requestCalls = 0;

  @override
  Future<void> initialize({
    List<int>? ageGates,
    bool useMockData = false,
    AgeSignalsMockData? mockData,
  }) async {
    initCalls.add(ageGates);
    final e = initError;
    if (e != null) {
      initError = null;
      throw e;
    }
  }

  @override
  Future<AgeSignalsAccessStatus> requestAgeSignalsAccess() async {
    requestCalls++;
    final e = error;
    if (e != null) throw e;
    return access;
  }

  @override
  Future<AgeSignalsResult> checkAgeSignals() async {
    checkCalls++;
    final e = checkError;
    if (e != null) throw e;
    return result!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AgeSignal map(
  AgeSignalsStatus status, {
  int? ageLower,
  int? ageUpper,
  AgeRangeSource? ageRangeSource,
  AgeSignalsAccessStatus access = AgeSignalsAccessStatus.shared,
}) {
  return PluginAgeSignalsSource.mapSignal(
    access,
    AgeSignalsResult(
      status: status,
      ageLower: ageLower,
      ageUpper: ageUpper,
      ageRangeSource: ageRangeSource,
    ),
  );
}

void main() {
  group('mapSignal: access is not shared -> unavailable', () {
    for (final access in [
      AgeSignalsAccessStatus.notShared,
      AgeSignalsAccessStatus.verificationRequired,
      AgeSignalsAccessStatus.unknown,
    ]) {
      test(access.name, () {
        expect(PluginAgeSignalsSource.mapSignal(access, null),
            AgeSignal.unavailable);
        // Even a result that would say adult is ignored without access.
        expect(
          map(AgeSignalsStatus.verified, ageLower: 18, access: access),
          AgeSignal.unavailable,
        );
      });
    }
  });

  group('mapSignal: verified, ageLower >= 18, not tierB -> adult', () {
    test('Android open-ended 18+ band', () {
      expect(
        map(AgeSignalsStatus.verified,
            ageLower: 18, ageRangeSource: AgeRangeSource.tierC),
        AgeSignal.adult,
      );
    });
    test('self-declared tierA counts', () {
      expect(
        map(AgeSignalsStatus.verified,
            ageLower: 18, ageRangeSource: AgeRangeSource.tierA),
        AgeSignal.adult,
      );
    });
    test('iOS (no ageRangeSource)', () {
      expect(map(AgeSignalsStatus.verified, ageLower: 21), AgeSignal.adult);
    });
  });

  group('mapSignal: minor', () {
    for (final status in [
      AgeSignalsStatus.supervised,
      AgeSignalsStatus.supervisedApprovalPending,
      AgeSignalsStatus.supervisedApprovalDenied,
    ]) {
      test('${status.name} -> minor, whatever the range', () {
        expect(map(status, ageLower: 13, ageUpper: 15), AgeSignal.minor);
        expect(map(status, ageLower: 18), AgeSignal.minor);
        expect(map(status), AgeSignal.minor);
      });
    }

    test('tierB (parent-managed) -> minor even when verified 18+', () {
      expect(
        map(AgeSignalsStatus.verified,
            ageLower: 18, ageRangeSource: AgeRangeSource.tierB),
        AgeSignal.minor,
      );
    });

    test('ageLower < 18 -> minor even when verified', () {
      expect(
        map(AgeSignalsStatus.verified, ageLower: 16, ageUpper: 17),
        AgeSignal.minor,
      );
    });
  });

  group('mapSignal: unavailable', () {
    test('declined', () {
      expect(map(AgeSignalsStatus.declined), AgeSignal.unavailable);
    });
    test('unknown', () {
      expect(map(AgeSignalsStatus.unknown), AgeSignal.unavailable);
    });
    test('null result', () {
      expect(
        PluginAgeSignalsSource.mapSignal(AgeSignalsAccessStatus.shared, null),
        AgeSignal.unavailable,
      );
    });
    test('verified without a lower bound is not trusted', () {
      expect(map(AgeSignalsStatus.verified), AgeSignal.unavailable);
    });
  });

  group('PluginAgeSignalsSource.check', () {
    test('unsupported platform never touches the plugin', () async {
      final plugin = _FakePlugin();
      final source =
          PluginAgeSignalsSource(plugin: plugin, isSupportedPlatform: false);

      expect(await source.check(), AgeSignal.unavailable);
      expect(plugin.initCalls, isEmpty);
    });

    test('initializes once with the 18 gate and maps the result', () async {
      final plugin = _FakePlugin(
        result: const AgeSignalsResult(
          status: AgeSignalsStatus.verified,
          ageLower: 18,
        ),
      );
      final source =
          PluginAgeSignalsSource(plugin: plugin, isSupportedPlatform: true);

      expect(await source.check(), AgeSignal.adult);
      expect(await source.check(), AgeSignal.adult);
      expect(plugin.initCalls, [
        [18]
      ]);
    });

    test('does not read signals when access is not shared', () async {
      final plugin = _FakePlugin(access: AgeSignalsAccessStatus.notShared);
      final source =
          PluginAgeSignalsSource(plugin: plugin, isSupportedPlatform: true);

      expect(await source.check(), AgeSignal.unavailable);
      expect(plugin.checkCalls, 0);
    });

    for (final error in <Object>[
      const UnsupportedPlatformException('old iOS'),
      const ApiNotAvailableException('no api'),
      const MissingEntitlementException('no entitlement'),
      const UserCancelledException('cancelled'),
      const NetworkErrorException('offline'),
      const PlayServicesException('play'),
      const ApiErrorException('api'),
      StateError('anything else'),
    ]) {
      test('${error.runtimeType} -> unavailable', () async {
        final plugin = _FakePlugin(error: error);
        final source =
            PluginAgeSignalsSource(plugin: plugin, isSupportedPlatform: true);

        expect(await source.check(), AgeSignal.unavailable);
      });
    }

    for (final error in <Object>[
      const ApiNotAvailableException('not in this region'),
      const UnsupportedPlatformException('old iOS'),
      const MissingEntitlementException('no entitlement'),
    ]) {
      test('${error.runtimeType} stops asking the platform for the session',
          () async {
        final plugin = _FakePlugin(checkError: error);
        final source =
            PluginAgeSignalsSource(plugin: plugin, isSupportedPlatform: true);

        expect(await source.check(), AgeSignal.unavailable);
        expect(await source.check(), AgeSignal.unavailable);
        expect(plugin.requestCalls, 1);
        expect(plugin.checkCalls, 1);
      });
    }

    for (final error in <Object>[
      const NetworkErrorException('offline'),
      const UserCancelledException('cancelled'),
      const ApiErrorException('api'),
    ]) {
      test('${error.runtimeType} is retried on the next check', () async {
        final plugin = _FakePlugin(checkError: error);
        final source =
            PluginAgeSignalsSource(plugin: plugin, isSupportedPlatform: true);

        expect(await source.check(), AgeSignal.unavailable);
        plugin
          ..checkError = null
          ..result = const AgeSignalsResult(
            status: AgeSignalsStatus.verified,
            ageLower: 18,
          );
        expect(await source.check(), AgeSignal.adult);
      });
    }

    test('a failed initialization is retried on the next check', () async {
      final plugin = _FakePlugin(
        initError: const ApiErrorException('init failed'),
        result: const AgeSignalsResult(
          status: AgeSignalsStatus.supervised,
          ageLower: 13,
          ageUpper: 15,
        ),
      );
      final source =
          PluginAgeSignalsSource(plugin: plugin, isSupportedPlatform: true);

      expect(await source.check(), AgeSignal.unavailable);
      expect(await source.check(), AgeSignal.minor);
      expect(plugin.initCalls, hasLength(2));
    });
  });
}
