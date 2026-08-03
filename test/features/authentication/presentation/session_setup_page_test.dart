import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/authentication/application/session_setup_service.dart';
import 'package:leb2_watch/src/features/authentication/presentation/session_setup_page.dart';

const _secretPassword = '<SECRET_PASSWORD_VALUE>';
const _secretAccessKey = '00000000-0000-4000-8000-000000000001';

void main() {
  testWidgets(
    'renders credential-first privacy flow and redacted saved summary',
    (tester) async {
      final service = _FakeSessionSetupService(
        summary: const SavedSessionSummary(
          state: SavedSessionState.ready,
          automaticReauthenticationEnabled: true,
        ),
      );
      await _pumpPage(tester, service: service);

      expect(find.text('Connect LEB2'), findsOneWidget);
      expect(find.textContaining('not affiliated with KMUTT'), findsOneWidget);
      expect(
        find.text(
          'LEB2 Watch is not affiliated with KMUTT or LEB2. Username and '
          'password are sent only during sign-in or optional reauthentication.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Access key and session cookie stay in OS secure storage. Protected '
          'requests send them with your LEB2 user ID. The ID stays in local '
          'SQLite.',
        ),
        findsOneWidget,
      );
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.byKey(const Key('session-access-key-field')), findsOneWidget);
      expect(find.byKey(const Key('credential-method-fields')), findsOneWidget);
      expect(find.text('Session cookie'), findsNothing);
      expect(find.byKey(const Key('session-cookie-field')), findsNothing);
      expect(find.byKey(const Key('session-user-id-field')), findsNothing);
      expect(find.text('Saved session ready'), findsOneWidget);
      expect(
        find.textContaining('Automatic reauthentication is enabled'),
        findsOneWidget,
      );
      expect(find.textContaining(_secretPassword), findsNothing);
    },
  );

  testWidgets('secret fields are hardened, obscure, reveal, and re-hide', (
    tester,
  ) async {
    await _pumpPage(tester);

    var accessKey = tester.widget<TextField>(
      find.byKey(const Key('session-access-key-field')),
    );
    expect(accessKey.obscureText, isTrue);
    _expectSecretInputHardening(accessKey);

    await _tapSecretVisibility(tester, const Key('session-access-key-field'));
    await tester.pump();
    accessKey = tester.widget(
      find.byKey(const Key('session-access-key-field')),
    );
    expect(accessKey.obscureText, isFalse);

    await _tapSecretVisibility(tester, const Key('session-access-key-field'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('session-access-key-field')))
          .obscureText,
      isTrue,
    );

    var password = tester.widget<TextField>(
      find.byKey(const Key('session-password-field')),
    );
    expect(password.obscureText, isTrue);
    _expectSecretInputHardening(password);
    expect(find.textContaining('OS secure storage'), findsWidgets);

    await _tapSecretVisibility(tester, const Key('session-password-field'));
    await tester.pump();
    password = tester.widget(find.byKey(const Key('session-password-field')));
    expect(password.obscureText, isFalse);
  });

  testWidgets('local validation focuses the first invalid field', (
    tester,
  ) async {
    await _pumpPage(tester);

    await _tapVisible(tester, find.byKey(const Key('session-submit')));
    await tester.pump();

    final accessKey = tester.widget<TextField>(
      find.byKey(const Key('session-access-key-field')),
    );
    expect(accessKey.focusNode?.hasFocus, isTrue);
    expect(
      find.text('Enter the UUID access key from your backend operator.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('session-access-key-field')),
      _secretAccessKey,
    );
    await _tapVisible(tester, find.byKey(const Key('session-submit')));
    await tester.pump();

    final username = tester.widget<TextField>(
      find.byKey(const Key('session-username-field')),
    );
    expect(username.focusNode?.hasFocus, isTrue);
    expect(find.text('Enter your LEB2 username.'), findsOneWidget);
  });

  testWidgets('rejects blank, malformed, all-zero, and multiple access keys', (
    tester,
  ) async {
    for (final value in [
      '',
      'not-a-uuid',
      '00000000-0000-0000-0000-000000000000',
      '$_secretAccessKey $_secretAccessKey',
    ]) {
      final service = _FakeSessionSetupService();
      await _pumpPage(tester, service: service);
      await tester.enterText(
        find.byKey(const Key('session-access-key-field')),
        value,
      );
      await _tapVisible(tester, find.byKey(const Key('session-submit')));
      await tester.pump();
      expect(
        find.text('Enter the UUID access key from your backend operator.'),
        findsOneWidget,
      );
      expect(service.credentialCalls, 0);
      final errorText = tester
          .widget<TextField>(find.byKey(const Key('session-access-key-field')))
          .decoration
          ?.errorText;
      if (value.isNotEmpty) {
        expect(errorText, isNot(contains(value)));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('trims valid access key before forwarding and never echoes it', (
    tester,
  ) async {
    final service = _FakeSessionSetupService();
    await _pumpPage(tester, service: service);
    await tester.enterText(
      find.byKey(const Key('session-access-key-field')),
      '  $_secretAccessKey  ',
    );
    await tester.enterText(
      find.byKey(const Key('session-username-field')),
      '<USERNAME>',
    );
    await tester.enterText(
      find.byKey(const Key('session-password-field')),
      _secretPassword,
    );
    await _tapVisible(tester, find.byKey(const Key('session-submit')));
    await tester.pump();

    expect(service.lastAccessKey, _secretAccessKey);
    final errorText = tester
        .widget<TextField>(find.byKey(const Key('session-access-key-field')))
        .decoration
        ?.errorText;
    expect(errorText, isNot(contains(_secretAccessKey)));
    expect(service.credentialCalls, 1);
  });

  testWidgets(
    'rapid tap and keyboard submission dispatch only once while busy',
    (tester) async {
      final gate = Completer<SessionSetupResult>();
      final service = _FakeSessionSetupService(credentialGate: gate);
      await _pumpPage(tester, service: service);
      await _enterAccessKey(tester);
      await _enterCredentials(tester);

      await _tapVisible(tester, find.byKey(const Key('session-submit')));
      await tester.tap(find.byKey(const Key('session-submit')));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(service.credentialCalls, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('session-password-field')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('session-submit')))
            .onPressed,
        isNull,
      );
      final semantics = tester.widget<Semantics>(
        find.byKey(const Key('session-status-live-region')),
      );
      expect(semantics.properties.liveRegion, isTrue);

      gate.complete(
        const SessionSetupFailure(SessionSetupFailureKind.networkUnavailable),
      );
      await tester.pump();
      expect(
        find.text('No network connection. Your saved session was not changed.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('disposing the page cancels work without a post-dispose update', (
    tester,
  ) async {
    final gate = Completer<SessionSetupResult>();
    final service = _FakeSessionSetupService(credentialGate: gate);
    await _pumpPage(tester, service: service);
    await _enterAccessKey(tester);
    await _enterCredentials(tester);
    await _tapVisible(tester, find.byKey(const Key('session-submit')));
    await tester.pump();
    final cancellation = service.lastCancellation;

    await tester.pumpWidget(const SizedBox.shrink());
    expect(cancellation?.isCancelled, isTrue);
    gate.complete(const SessionSetupFailure(SessionSetupFailureKind.cancelled));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful setup completes once', (tester) async {
    var completions = 0;
    final service = _FakeSessionSetupService(
      credentialResult: const SessionSetupSuccess(),
    );
    await _pumpPage(
      tester,
      service: service,
      onCompleted: () => completions += 1,
    );
    await _enterAccessKey(tester);
    await _enterCredentials(tester);
    await _tapVisible(tester, find.byKey(const Key('session-submit')));
    await tester.pump();

    expect(service.credentialCalls, 1);
    expect(completions, 1);
  });

  testWidgets('navigation failure retries locally without repeating setup', (
    tester,
  ) async {
    var navigationCalls = 0;
    final service = _FakeSessionSetupService(
      credentialResult: const SessionSetupSuccess(),
    );
    await _pumpPage(
      tester,
      service: service,
      onCompleted: () {
        navigationCalls += 1;
        if (navigationCalls == 1) {
          throw StateError('synthetic navigation failure');
        }
      },
    );
    await _enterAccessKey(tester);
    await _enterCredentials(tester);
    await _tapVisible(tester, find.byKey(const Key('session-submit')));
    await tester.pump();

    expect(find.byKey(const Key('session-navigation-retry')), findsOneWidget);
    expect(
      find.textContaining('semester selection could not open'),
      findsOneWidget,
    );
    await _tapVisible(
      tester,
      find.byKey(const Key('session-navigation-retry')),
    );
    await tester.pump();

    expect(service.credentialCalls, 1);
    expect(navigationCalls, 2);
  });

  testWidgets('saved-session action verifies without populating inputs', (
    tester,
  ) async {
    final service = _FakeSessionSetupService(
      summary: const SavedSessionSummary(
        state: SavedSessionState.ready,
        automaticReauthenticationEnabled: false,
      ),
      savedResult: const SessionSetupFailure(
        SessionSetupFailureKind.invalidOrExpiredSession,
      ),
    );
    await _pumpPage(tester, service: service);

    await _tapVisible(tester, find.byKey(const Key('verify-saved-session')));
    await tester.pump();

    expect(service.savedCalls, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('session-access-key-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      find.text('This session is expired or invalid. Sign in again.'),
      findsOneWidget,
    );
  });

  testWidgets('shows concise incomplete saved-session guidance', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      service: _FakeSessionSetupService(
        summary: const SavedSessionSummary(
          state: SavedSessionState.incomplete,
          automaticReauthenticationEnabled: false,
        ),
      ),
    );

    expect(find.text('Setup incomplete'), findsOneWidget);
    expect(find.text('Sign in above to finish setup.'), findsOneWidget);
    expect(find.byKey(const Key('session-submit')), findsOneWidget);
    expect(find.byKey(const Key('verify-saved-session')), findsNothing);
  });

  testWidgets('credential flow forwards explicit auto-reauth choice', (
    tester,
  ) async {
    final service = _FakeSessionSetupService();
    await _pumpPage(tester, service: service);
    await _enterAccessKey(tester);
    await tester.enterText(
      find.byKey(const Key('session-username-field')),
      '<USERNAME>',
    );
    await tester.enterText(
      find.byKey(const Key('session-password-field')),
      _secretPassword,
    );
    await _tapVisible(
      tester,
      find.byKey(const Key('automatic-reauthentication-toggle')),
    );
    await tester.pump();
    await _tapVisible(tester, find.byKey(const Key('session-submit')));
    await tester.pump();

    expect(service.credentialCalls, 1);
    expect(service.lastAutomaticReauthentication, isTrue);
  });

  testWidgets('every failure category uses fixed safe copy', (tester) async {
    final cases = <(SessionSetupFailure, String)>[
      (
        const SessionSetupFailure(SessionSetupFailureKind.invalidInput),
        'Check the highlighted fields and try again.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.incompleteSavedSession,
        ),
        'Setup incomplete.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.invalidOrExpiredSession,
        ),
        'This session is expired or invalid.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.invalidCredentials),
        'The username or password was not accepted.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.networkUnavailable),
        'No network connection.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.requestTimeout),
        'The connection check took too long.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.backendUnavailable),
        'LEB2 could not be reached.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.rateLimited,
          retryAfter: Duration(seconds: 90),
        ),
        'Try again in 2 minutes.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.invalidResponse),
        'Backend returned an unexpected response.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.secureStorageUnavailable,
        ),
        'Secure credential storage is unavailable.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.localStorageUnavailable,
        ),
        'Local session settings could not be saved.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.differentAccountData),
        'Delete local data before connecting a different account.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.accessKeyMissing),
        'This access key is missing or no longer valid.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.accessKeyInvalid),
        'This access key is missing or no longer valid.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.accessKeyNotActivated,
        ),
        'This access key has not been activated.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.accessKeyAccountMismatch,
        ),
        'This access key cannot be used with this LEB2 account.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.accessKeyReauthenticationRequired,
        ),
        'Sign in with Username / password to finish initializing this access key.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.accessKeyStoreUnavailable,
        ),
        'Access-key verification is temporarily unavailable.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.deviceIdentityMissing,
        ),
        'This device could not provide a valid device identifier.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.deviceIdentityInvalid,
        ),
        'This device could not provide a valid device identifier.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.deviceNotBound),
        'This access key needs to be connected to this device again.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.deviceMismatch),
        'This access key is currently connected to another device.',
      ),
      (
        const SessionSetupFailure(
          SessionSetupFailureKind.clientVersionRequired,
        ),
        'This app could not provide a valid client version.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.clientVersionInvalid),
        'This app could not provide a valid client version.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.clientUpdateRequired),
        'This version of LEB2 Watch is no longer compatible with the backend.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.persistenceUncertain),
        'Saving could not be completed or safely restored.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.cancelled),
        'Connection check cancelled.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.busy),
        'A connection check is already running.',
      ),
      (
        const SessionSetupFailure(SessionSetupFailureKind.unexpected),
        'The connection could not be completed.',
      ),
    ];
    expect(
      cases.map((entry) => entry.$1.kind).toSet(),
      SessionSetupFailureKind.values.toSet(),
    );

    for (final (failure, expected) in cases) {
      await _pumpPage(
        tester,
        service: _FakeSessionSetupService(credentialResult: failure),
      );
      await _enterAccessKey(tester);
      await _enterCredentials(tester);
      await _tapVisible(tester, find.byKey(const Key('session-submit')));
      await tester.pump();
      expect(find.textContaining(expected), findsOneWidget);
      final semanticsHandle = tester.ensureSemantics();
      try {
        final passwordField = tester.getSemantics(
          find.byKey(const Key('session-password-field')),
        );
        expect(passwordField.value, isNot(contains(_secretPassword)));
      } finally {
        semanticsHandle.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('six widths at 200 percent text have no layout overflow', (
    tester,
  ) async {
    for (final width in [320.0, 375.0, 414.0, 600.0, 768.0, 1200.0]) {
      await _pumpPage(tester, width: width, height: 1000, textScale: 2);
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(
        find.byKey(const Key('session-setup-scroll-view')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('dark theme and reduced motion preserve the complete form', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      brightness: Brightness.dark,
      disableAnimations: true,
      width: 1200,
    );

    expect(find.text('Connect LEB2'), findsOneWidget);
    expect(find.byKey(const Key('session-submit')), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Connect LEB2'))).brightness,
      Brightness.dark,
    );
    expect(
      MediaQuery.disableAnimationsOf(tester.element(find.text('Connect LEB2'))),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _enterAccessKey(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('session-access-key-field')),
    _secretAccessKey,
  );
}

Future<void> _enterCredentials(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('session-username-field')),
    '<USERNAME>',
  );
  await tester.enterText(
    find.byKey(const Key('session-password-field')),
    _secretPassword,
  );
}

Future<void> _tapSecretVisibility(WidgetTester tester, Key fieldKey) async {
  await _tapVisible(
    tester,
    find.descendant(
      of: find.byKey(fieldKey),
      matching: find.byType(IconButton),
    ),
  );
}

void _expectSecretInputHardening(TextField field) {
  expect(field.autocorrect, isFalse);
  expect(field.enableSuggestions, isFalse);
  expect(field.smartDashesType, SmartDashesType.disabled);
  expect(field.smartQuotesType, SmartQuotesType.disabled);
  expect(field.enableIMEPersonalizedLearning, isFalse);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

Future<void> _pumpPage(
  WidgetTester tester, {
  SessionSetupService? service,
  FutureOr<void> Function()? onCompleted,
  double width = 375,
  double height = 900,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        );
      },
      home: SessionSetupPage(
        service: service ?? _FakeSessionSetupService(),
        onCompleted: onCompleted ?? () {},
      ),
    ),
  );
  await tester.pump();
}

final class _FakeSessionSetupService implements SessionSetupService {
  _FakeSessionSetupService({
    this.summary = const SavedSessionSummary(
      state: SavedSessionState.none,
      automaticReauthenticationEnabled: false,
    ),
    this.credentialResult = const SessionSetupFailure(
      SessionSetupFailureKind.networkUnavailable,
    ),
    this.savedResult = const SessionSetupFailure(
      SessionSetupFailureKind.networkUnavailable,
    ),
    this.credentialGate,
  });

  final SavedSessionSummary summary;
  final SessionSetupResult credentialResult;
  final SessionSetupResult savedResult;
  final Completer<SessionSetupResult>? credentialGate;
  int savedCalls = 0;
  int credentialCalls = 0;
  bool? lastAutomaticReauthentication;
  SessionSetupCancellation? lastCancellation;
  String? lastAccessKey;
  String? lastUsername;

  @override
  Future<SessionSetupResult> connectWithCookie({
    String? accessKey,
    required String sessionCookie,
    required int userId,
    SessionSetupCancellation? cancellation,
  }) async {
    return const SessionSetupFailure(SessionSetupFailureKind.unexpected);
  }

  @override
  Future<SessionSetupResult> connectWithCredentials({
    String? accessKey,
    required String username,
    required String password,
    required bool enableAutomaticReauthentication,
    SessionSetupCancellation? cancellation,
  }) async {
    credentialCalls += 1;
    lastAccessKey = accessKey;
    lastUsername = username;
    lastAutomaticReauthentication = enableAutomaticReauthentication;
    lastCancellation = cancellation;
    return credentialGate?.future ?? credentialResult;
  }

  @override
  Future<SavedSessionSummary> readSavedSessionSummary() async => summary;

  @override
  Future<SessionSetupResult> verifySavedSession({
    SessionSetupCancellation? cancellation,
  }) async {
    savedCalls += 1;
    lastCancellation = cancellation;
    return savedResult;
  }
}
