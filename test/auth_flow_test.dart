import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:typeflux_app/auth/auth_flow.dart';
import 'package:typeflux_app/auth/apple_identity_provider.dart';
import 'package:typeflux_app/core/api.dart';

import 'support/fakes.dart';

http.Response ok([Object data = const {}]) =>
    http.Response(jsonEncode({'code': 'OK', 'data': data}), 200);

class TrackingClient extends MockClient {
  TrackingClient(super.handler);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

class FixtureAppleProvider implements AppleIdentityProvider {
  FixtureAppleProvider(this.result);
  final Future<String> Function() result;
  @override
  Future<String> authenticate() => result();
}

void main() {
  test('Apple identity token uses the backend exchange and transfers a real session', () async {
    final vault = MemoryVault();
    TypefluxApi? signedIn;
    final requests = <http.Request>[];
    final flow = AuthFlow(
      vault: vault,
      origin: 'https://example.com',
      apiFactory: (origin, vault) => TypefluxApi(
        origin: origin,
        vault: vault,
        client: MockClient((request) async {
          requests.add(request);
          expect(request.url.path, '/api/v1/auth/oauth/apple');
          expect(jsonDecode(request.body), {
            'id_token': 'fixture-identity-token',
          });
          expect(request.headers.containsKey('Authorization'), false);
          return ok({
            'access_token': 'fixture-access',
            'refresh_token': 'fixture-refresh',
            'expires_at': 9999999999,
          });
        }),
      ),
      onSignedIn: (api) async => signedIn = api,
    );
    addTearDown(() {
      flow.dispose();
      signedIn?.close();
    });
    await flow.signInWithApple(
      FixtureAppleProvider(() async => 'fixture-identity-token'),
    );
    expect(requests, hasLength(1));
    expect(signedIn?.signedIn, true);
    expect(await vault.read('session:https://example.com'), isNotNull);
    expect(flow.error, isNull);
  });

  test(
    'Apple cancellation and absent configuration never create a session',
    () async {
      var apiCalls = 0;
      final flow = AuthFlow(
        vault: MemoryVault(),
        origin: 'https://example.com',
        apiFactory: (origin, vault) {
          apiCalls++;
          return TypefluxApi(origin: origin, vault: vault);
        },
        onSignedIn: (_) async =>
            fail('Unavailable authorization must not sign in'),
      );
      addTearDown(flow.dispose);
      await flow.signInWithApple(
        FixtureAppleProvider(() async {
          throw const AppleAuthorizationFailure('cancelled', cancelled: true);
        }),
      );
      expect(flow.error, isNull);
      expect(flow.working, false);
      await flow.signInWithApple(const UnconfiguredAppleIdentityProvider());
      expect(flow.error, 'authApplePlatformUnavailable');
      expect(apiCalls, 0);
    },
  );

  test(
    'disposing during Apple authorization drops the late identity token',
    () async {
      final token = Completer<String>();
      var apiCalls = 0;
      final flow = AuthFlow(
        vault: MemoryVault(),
        origin: 'https://example.com',
        apiFactory: (origin, vault) {
          apiCalls++;
          return TypefluxApi(origin: origin, vault: vault);
        },
        onSignedIn: (_) async => fail('A disposed flow must not sign in'),
      );
      final pending = flow.signInWithApple(
        FixtureAppleProvider(() => token.future),
      );
      flow.dispose();
      token.complete('fixture-late-identity-token');
      await pending;
      expect(apiCalls, 0);
    },
  );

  test(
    'Apple session handoff failure removes only its stored credentials',
    () async {
      final vault = MemoryVault();
      final flow = AuthFlow(
        vault: vault,
        origin: 'https://example.com',
        apiFactory: (origin, vault) => TypefluxApi(
          origin: origin,
          vault: vault,
          client: MockClient(
            (_) async => ok({
              'access_token': 'fixture-access',
              'refresh_token': 'fixture-refresh',
              'expires_at': 9999999999,
            }),
          ),
        ),
        onSignedIn: (_) async =>
            throw StateError('fixture persistence failure'),
      );
      addTearDown(flow.dispose);
      await flow.signInWithApple(
        FixtureAppleProvider(() async => 'fixture-identity-token'),
      );
      expect(await vault.read('session:https://example.com'), isNull);
      expect(flow.working, false);
      expect(flow.error, 'NETWORK_ERROR');
    },
  );

  test(
    'validation matches email, Unicode password and six-digit contracts',
    () {
      expect(AuthFlow.validateEmail(''), 'authEmailRequired');
      expect(AuthFlow.validateEmail('demo@'), 'authEmailInvalid');
      expect(AuthFlow.validateEmail(' demo@example.com '), isNull);
      expect(AuthFlow.validatePassword('password1'), 'authPasswordRules');
      expect(AuthFlow.validatePassword('Password'), 'authPasswordRules');
      expect(AuthFlow.validatePassword('Aa12345'), 'authPasswordRules');
      expect(AuthFlow.validatePassword('Éé密码测试１２'), isNull);
      expect(AuthFlow.validatePassword('Strong123'), isNull);
      expect(AuthFlow.validateCode('12345'), 'authCodeInvalid');
      expect(AuthFlow.validateCode('12x456'), 'authCodeInvalid');
      expect(AuthFlow.validateCode('123456'), isNull);
    },
  );

  test('invalid form never calls an account endpoint', () async {
    var calls = 0;
    final flow = AuthFlow(
      vault: MemoryVault(),
      origin: 'https://example.com',
      apiFactory: (origin, vault) {
        calls++;
        return TypefluxApi(origin: origin, vault: vault);
      },
      onSignedIn: (_) async {},
    );
    addTearDown(flow.dispose);
    await flow.submit();
    expect(flow.fieldErrors.keys, containsAll(['email', 'password']));
    expect(calls, 0);
    flow.navigate(AuthStep.register);
    flow.email = 'demo@example.com';
    flow.password = 'weak';
    await flow.submit();
    expect(flow.fieldErrors['password'], 'authPasswordRules');
    expect(calls, 0);
  });

  test(
    'register, resend cooldown and activation use the real request bodies',
    () async {
      final requests = <http.Request>[];
      var now = DateTime.utc(2026, 10, 4, 12);
      TypefluxApi? signedIn;
      final flow = AuthFlow(
        vault: MemoryVault(),
        origin: 'https://example.com',
        now: () => now,
        apiFactory: (origin, vault) => TypefluxApi(
          origin: origin,
          vault: vault,
          client: MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/login')) {
              return ok({
                'access_token': 'fixture-access',
                'refresh_token': 'fixture-refresh',
                'expires_at': 9999999999,
              });
            }
            return ok({'sent': true});
          }),
        ),
        onSignedIn: (api) async => signedIn = api,
      );
      addTearDown(() {
        flow.dispose();
        signedIn?.close();
      });
      flow.navigate(AuthStep.register);
      flow.email = ' demo@example.com ';
      flow.password = 'Strong123';
      await flow.submit();
      expect(flow.step, AuthStep.activate);
      expect(flow.resendSeconds, 60);
      expect(requests.single.url.path, '/api/v1/auth/register');
      expect(jsonDecode(requests.single.body), {
        'email': 'demo@example.com',
        'password': 'Strong123',
      });
      await flow.resend();
      expect(requests, hasLength(1));
      now = now.add(const Duration(seconds: 61));
      flow.refreshClock();
      await flow.resend();
      expect(requests.last.url.path, '/api/v1/auth/resend-activation');
      expect(jsonDecode(requests.last.body)['password'], 'Strong123');
      expect(flow.resendSeconds, 60);
      flow.code = '12345';
      await flow.submit();
      expect(requests, hasLength(2));
      flow.code = '123456';
      await flow.submit();
      expect(requests[2].url.path, '/api/v1/auth/activate');
      expect(jsonDecode(requests[2].body), {
        'email': 'demo@example.com',
        'code': '123456',
      });
      expect(requests[3].url.path, '/api/v1/auth/login');
      expect(signedIn?.signedIn, isTrue);
      expect(flow.password, isEmpty);
    },
  );

  test(
    'forgot/reset stays neutral and returns to sign-in without auto login',
    () async {
      final requests = <http.Request>[];
      final flow = AuthFlow(
        vault: MemoryVault(),
        origin: 'https://example.com',
        apiFactory: (origin, vault) => TypefluxApi(
          origin: origin,
          vault: vault,
          client: MockClient((request) async {
            requests.add(request);
            return ok({'sent': true});
          }),
        ),
        onSignedIn: (_) async => fail('Reset must not sign in automatically'),
      );
      addTearDown(flow.dispose);
      flow.navigate(AuthStep.forgotPassword);
      flow.email = 'unknown@example.com';
      await flow.submit();
      expect(flow.step, AuthStep.resetPassword);
      expect(flow.notice, 'authResetSent');
      expect(jsonDecode(requests.single.body), {
        'email': 'unknown@example.com',
      });
      flow.code = '123456';
      flow.newPassword = 'Changed123';
      await flow.submit();
      expect(requests.last.url.path, '/api/v1/auth/reset-password');
      expect(jsonDecode(requests.last.body), {
        'email': 'unknown@example.com',
        'code': '123456',
        'new_password': 'Changed123',
      });
      expect(flow.step, AuthStep.signIn);
      expect(flow.notice, 'authPasswordReset');
      expect(flow.newPassword, isEmpty);
      expect(requests, hasLength(2));
    },
  );

  test('busy state blocks duplicate submit and navigation', () async {
    final response = Completer<http.Response>();
    var calls = 0;
    final flow = AuthFlow(
      vault: MemoryVault(),
      origin: 'https://example.com',
      apiFactory: (origin, vault) => TypefluxApi(
        origin: origin,
        vault: vault,
        client: MockClient((_) {
          calls++;
          return response.future;
        }),
      ),
      onSignedIn: (_) async {},
    );
    addTearDown(flow.dispose);
    flow.navigate(AuthStep.register);
    flow.email = 'demo@example.com';
    flow.password = 'Strong123';
    final pending = flow.submit();
    await Future<void>.delayed(Duration.zero);
    await flow.submit();
    flow.navigate(AuthStep.forgotPassword);
    expect(flow.step, AuthStep.register);
    expect(flow.busy, isTrue);
    expect(calls, 1);
    response.complete(ok());
    await pending;
    expect(flow.step, AuthStep.activate);
    expect(flow.busy, isFalse);
  });

  test('real auth errors preserve recoverable fields', () async {
    final flow = AuthFlow(
      vault: MemoryVault(),
      origin: 'https://example.com',
      apiFactory: (origin, vault) => TypefluxApi(
        origin: origin,
        vault: vault,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'code': 'AUTH_INVALID_CREDENTIALS'}),
            401,
          ),
        ),
      ),
      onSignedIn: (_) async {},
    );
    addTearDown(flow.dispose);
    flow.email = 'demo@example.com';
    flow.password = 'Entered123';
    await flow.submit();
    expect(flow.error, 'AUTH_INVALID_CREDENTIALS');
    expect(flow.email, 'demo@example.com');
    expect(flow.password, 'Entered123');
    expect(flow.busy, isFalse);
  });

  test('an unverified login can resume activation and resend', () async {
    final requests = <http.Request>[];
    final flow = AuthFlow(
      vault: MemoryVault(),
      origin: 'https://example.com',
      apiFactory: (origin, vault) => TypefluxApi(
        origin: origin,
        vault: vault,
        client: MockClient((request) async {
          requests.add(request);
          return request.url.path.endsWith('/login')
              ? http.Response(jsonEncode({'code': 'AUTH_USER_NOT_ACTIVE'}), 403)
              : ok();
        }),
      ),
      onSignedIn: (_) async {},
    );
    addTearDown(flow.dispose);
    flow.email = 'demo@example.com';
    flow.password = 'Strong123';
    await flow.submit();
    expect(flow.step, AuthStep.activate);
    expect(flow.error, 'AUTH_USER_NOT_ACTIVE');
    await flow.resend();
    expect(requests.last.url.path, '/api/v1/auth/resend-activation');
    expect(jsonDecode(requests.last.body)['password'], 'Strong123');
  });

  test('dispose cannot close an API already transferred to the app', () async {
    late AuthFlow flow;
    late TrackingClient client;
    TypefluxApi? transferred;
    flow = AuthFlow(
      vault: MemoryVault(),
      origin: 'https://example.com',
      apiFactory: (origin, vault) {
        client = TrackingClient(
          (_) async => ok({
            'access_token': 'fixture-access',
            'refresh_token': 'fixture-refresh',
            'expires_at': 9999999999,
          }),
        );
        return TypefluxApi(origin: origin, vault: vault, client: client);
      },
      onSignedIn: (api) async {
        transferred = api;
        flow.dispose();
        await Future<void>.delayed(Duration.zero);
      },
    );
    flow.email = 'demo@example.com';
    flow.password = 'Strong123';
    await flow.submit();
    expect(transferred, isNotNull);
    expect(client.closed, isFalse);
    transferred!.close();
  });

  test('late login after disposal does not retain a new session', () async {
    final response = Completer<http.Response>();
    final vault = MemoryVault();
    final flow = AuthFlow(
      vault: vault,
      origin: 'https://example.com',
      apiFactory: (origin, vault) => TypefluxApi(
        origin: origin,
        vault: vault,
        client: MockClient((_) => response.future),
      ),
      onSignedIn: (_) async => fail('Disposed flow cannot sign in'),
    );
    flow.email = 'demo@example.com';
    flow.password = 'Strong123';
    final pending = flow.submit();
    await Future<void>.delayed(Duration.zero);
    flow.dispose();
    response.complete(
      ok({
        'access_token': 'fixture-access',
        'refresh_token': 'fixture-refresh',
        'expires_at': 9999999999,
      }),
    );
    await pending;
    expect(await vault.read('session:https://example.com'), isNull);
  });

  test(
    'successful activation remains successful if sign-in then fails',
    () async {
      final flow = AuthFlow(
        vault: MemoryVault(),
        origin: 'https://example.com',
        apiFactory: (origin, vault) => TypefluxApi(
          origin: origin,
          vault: vault,
          client: MockClient(
            (request) async => request.url.path.endsWith('/login')
                ? http.Response(jsonEncode({'code': 'INTERNAL'}), 500)
                : ok(),
          ),
        ),
        onSignedIn: (_) async {},
      );
      addTearDown(flow.dispose);
      flow.navigate(AuthStep.activate);
      flow.email = 'demo@example.com';
      flow.password = 'Strong123';
      flow.code = '123456';
      await flow.submit();
      expect(flow.step, AuthStep.signIn);
      expect(flow.notice, 'authActivated');
      expect(flow.error, 'authServiceUnavailable');
    },
  );

  test(
    'a failed app handoff rolls back the session and closes its client',
    () async {
      final vault = MemoryVault();
      late TrackingClient client;
      final flow = AuthFlow(
        vault: vault,
        origin: 'https://example.com',
        apiFactory: (origin, vault) {
          client = TrackingClient(
            (_) async => ok({
              'access_token': 'fixture-access',
              'refresh_token': 'fixture-refresh',
              'expires_at': 9999999999,
            }),
          );
          return TypefluxApi(origin: origin, vault: vault, client: client);
        },
        onSignedIn: (_) async =>
            throw StateError('fixture storage unavailable'),
      );
      addTearDown(flow.dispose);
      flow.email = 'demo@example.com';
      flow.password = 'Strong123';
      await flow.submit();
      expect(flow.busy, isFalse);
      expect(flow.error, isNotNull);
      expect(flow.password, 'Strong123');
      expect(client.closed, isTrue);
      expect(await vault.read('session:https://example.com'), isNull);
    },
  );

  test('origin changes clear secret inputs and reset the current flow', () {
    final flow = AuthFlow(
      vault: MemoryVault(),
      origin: 'https://one.example.com',
      onSignedIn: (_) async {},
    );
    addTearDown(flow.dispose);
    flow.navigate(AuthStep.resetPassword);
    flow.password = 'Old12345';
    flow.newPassword = 'New12345';
    flow.code = '123456';
    flow.changeOrigin('https://two.example.com');
    expect(flow.step, AuthStep.signIn);
    expect(flow.password, isEmpty);
    expect(flow.newPassword, isEmpty);
    expect(flow.code, isEmpty);
  });
}
