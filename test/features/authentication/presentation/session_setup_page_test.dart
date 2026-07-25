import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/features/authentication/application/session_setup_service.dart';
import 'package:leb2_watch/src/features/authentication/presentation/session_setup_page.dart';

const _secretCookie = '<SECRET_COOKIE_VALUE>';
const _secretPassword = '<SECRET_PASSWORD_VALUE>';

void main() {
  testWidgets('renders cookie-first privacy flow and redacted saved summary', (
    tester,
  ) async {
    final service = _FakeSessionSetupService(
      summary: const SavedSessionSummary(
        state: SavedSessionState.ready,
        automaticReauthenticationEnabled: true,
      ),
    );
    await _pumpPage(tester, service: service);

    expect(find.text('Connect LEB2'), findsOneWidget);
    expect(find.textContaining('independent third-party'), findsOneWidget);
    expect(
      find.text(
        'LEB2 Watch is an independent third-party application. Your '
        'username and password are sent only when you sign in and, if you '
        'opt in, for automatic reauthentication.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Your saved session cookie is kept at rest in operating-system secure '
        'storage. Protected backend requests temporarily send that cookie and '
        'your numeric LEB2 user ID. The ID stays in local SQLite between '
        'requests.',
      ),
      findsOneWidget,
    );
    expect(find.text('Session cookie'), findsOneWidget);
    expect(find.byKey(const Key('cookie-method-fields')), findsOneWidget);
    expect(find.byKey(const Key('credential-method-fields')), findsNothing);
    expect(find.text('Saved session ready to verify'), findsOneWidget);
    expect(
      find.textContaining('Automatic reauthentication is enabled'),
      findsOneWidget,
    );
    expect(find.textContaining(_secretCookie), findsNothing);
    expect(find.textContaining(_secretPassword), findsNothing);
  });

  testWidgets('secret fields are hardened, obscure, reveal, and re-hide', (
    tester,
  ) async {
    await _pumpPage(tester);

    var cookie = tester.widget<TextField>(
      find.byKey(const Key('session-cookie-field')),
    );
    expect(cookie.obscureText, isTrue);
    _expectSecretInputHardening(cookie);

    await _tapVisible(tester, find.byTooltip('Show secret'));
    await tester.pump();
    cookie = tester.widget(find.byKey(const Key('session-cookie-field')));
    expect(cookie.obscureText, isFalse);
    expect(find.byTooltip('Hide secret'), findsOneWidget);

    await _tapVisible(tester, find.byTooltip('Hide secret'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('session-cookie-field')))
          .obscureText,
      isTrue,
    );

    await tester.tap(find.text('Username / password'));
    await tester.pump();
    var password = tester.widget<TextField>(
      find.byKey(const Key('session-password-field')),
    );
    expect(password.obscureText, isTrue);
    _expectSecretInputHardening(password);
    expect(
      find.textContaining('operating-system secure storage'),
      findsWidgets,
    );

    await _tapVisible(tester, find.byTooltip('Show secret'));
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

    final cookie = tester.widget<TextField>(
      find.byKey(const Key('session-cookie-field')),
    );
    expect(cookie.focusNode?.hasFocus, isTrue);
    expect(
      find.text('Enter your current LEB2 session cookie.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('session-cookie-field')),
      _secretCookie,
    );
    await _tapVisible(tester, find.byKey(const Key('session-submit')));
    await tester.pump();

    final userId = tester.widget<TextField>(
      find.byKey(const Key('session-user-id-field')),
    );
    expect(userId.focusNode?.hasFocus, isTrue);
    expect(find.text('Enter a positive numeric LEB2 user ID.'), findsOneWidget);
  });

  testWidgets(
    'rapid tap and keyboard submission dispatch only once while busy',
    (tester) async {
      final gate = Completer<SessionSetupResult>();
      final service = _FakeSessionSetupService(cookieGate: gate);
      await _pumpPage(tester, service: service);
      await tester.enterText(
        find.byKey(const Key('session-cookie-field')),
        _secretCookie,
      );
      await tester.enterText(
        find.byKey(const Key('session-user-id-field')),
        '2001',
      );

      await _tapVisible(tester, find.byKey(const Key('session-submit')));
      await tester.tap(find.byKey(const Key('session-submit')));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(service.cookieCalls, 1);
      expect(
        tester
            .widget<SegmentedButton<SessionSetupMethod>>(
              find.byKey(const Key('session-method-control')),
            )
            .onSelectionChanged,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('session-cookie-field')))
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
    final service = _FakeSessionSetupService(cookieGate: gate);
    await _pumpPage(tester, service: service);
    await tester.enterText(
      find.byKey(const Key('session-cookie-field')),
      _secretCookie,
    );
    await tester.enterText(
      find.byKey(const Key('session-user-id-field')),
      '2001',
    );
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
      cookieResult: const SessionSetupSuccess(),
    );
    await _pumpPage(
      tester,
      service: service,
      onCompleted: () => completions += 1,
    );
    await tester.enterText(
      find.byKey(const Key('session-cookie-field')),
      _secretCookie,
    );
    await tester.enterText(
      find.byKey(const Key('session-user-id-field')),
      '2001',
    );
    await _tapVisible(tester, find.byKey(const Key('session-submit')));
    await tester.pump();

    expect(service.cookieCalls, 1);
    expect(completions, 1);
  });

  testWidgets('navigation failure retries locally without repeating setup', (
    tester,
  ) async {
    var navigationCalls = 0;
    final service = _FakeSessionSetupService(
      cookieResult: const SessionSetupSuccess(),
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
    await tester.enterText(
      find.byKey(const Key('session-cookie-field')),
      _secretCookie,
    );
    await tester.enterText(
      find.byKey(const Key('session-user-id-field')),
      '2001',
    );
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

    expect(service.cookieCalls, 1);
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
          .widget<TextField>(find.byKey(const Key('session-cookie-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      find.text('This session is expired or invalid. Enter a current session.'),
      findsOneWidget,
    );
  });

  testWidgets('credential mode forwards explicit auto-reauth choice', (
    tester,
  ) async {
    final service = _FakeSessionSetupService();
    await _pumpPage(tester, service: service);
    await tester.tap(find.text('Username / password'));
    await tester.pump();
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
        'The saved setup is incomplete.',
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
        'The backend returned an unexpected response.',
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
        service: _FakeSessionSetupService(cookieResult: failure),
      );
      await tester.enterText(
        find.byKey(const Key('session-cookie-field')),
        _secretCookie,
      );
      await tester.enterText(
        find.byKey(const Key('session-user-id-field')),
        '2001',
      );
      await _tapVisible(tester, find.byKey(const Key('session-submit')));
      await tester.pump();
      expect(find.textContaining(expected), findsOneWidget);
      final semanticsHandle = tester.ensureSemantics();
      try {
        final cookieField = tester.getSemantics(
          find.byKey(const Key('session-cookie-field')),
        );
        expect(cookieField.value, isNot(contains(_secretCookie)));
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
    this.cookieResult = const SessionSetupFailure(
      SessionSetupFailureKind.networkUnavailable,
    ),
    this.savedResult = const SessionSetupFailure(
      SessionSetupFailureKind.networkUnavailable,
    ),
    this.cookieGate,
  });

  final SavedSessionSummary summary;
  final SessionSetupResult cookieResult;
  final SessionSetupResult savedResult;
  final Completer<SessionSetupResult>? cookieGate;
  int cookieCalls = 0;
  int savedCalls = 0;
  int credentialCalls = 0;
  bool? lastAutomaticReauthentication;
  SessionSetupCancellation? lastCancellation;

  @override
  Future<SessionSetupResult> connectWithCookie({
    required String sessionCookie,
    required int userId,
    SessionSetupCancellation? cancellation,
  }) async {
    cookieCalls += 1;
    lastCancellation = cancellation;
    return cookieGate?.future ?? cookieResult;
  }

  @override
  Future<SessionSetupResult> connectWithCredentials({
    required String username,
    required String password,
    required bool enableAutomaticReauthentication,
    SessionSetupCancellation? cancellation,
  }) async {
    credentialCalls += 1;
    lastAutomaticReauthentication = enableAutomaticReauthentication;
    lastCancellation = cancellation;
    return const SessionSetupFailure(
      SessionSetupFailureKind.networkUnavailable,
    );
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
