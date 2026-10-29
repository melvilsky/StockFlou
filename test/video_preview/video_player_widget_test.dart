import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/generation/presentation/video_player_widget.dart';
import 'package:video_player/video_player.dart';

/// Controller with a controlled initialization, value and disposal.
class FakeVideoPlayerController extends VideoPlayerController {
  FakeVideoPlayerController(String path) : super.file(File(path));

  final Completer<void> _initializeCompleter = Completer<void>();

  int initializeCalls = 0;
  int disposeCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Future<void> initialize() {
    initializeCalls++;
    final Future<void> future = _initializeCompleter.future;
    // The error is delivered to the caller. This listener only prevents the
    // "unhandled error" report when the attempt was already superseded.
    unawaited(future.catchError((Object _) {}));
    return future;
  }

  @override
  Future<void> play() async {
    playCalls++;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (disposeCalls > 1) {
      return;
    }
    await super.dispose();
  }

  /// Simulates a successful initialization.
  void completeInitialization() {
    if (disposeCalls == 0) {
      value = value.copyWith(
        duration: const Duration(seconds: 2),
        size: const Size(320, 240),
        isInitialized: true,
      );
    }
    if (!_initializeCompleter.isCompleted) {
      _initializeCompleter.complete();
    }
  }

  /// Simulates a failed initialization.
  void failInitialization() {
    if (!_initializeCompleter.isCompleted) {
      _initializeCompleter.completeError(Exception('cannot open file'));
    }
  }

  /// Simulates an error announced by the controller itself.
  void reportError() {
    value = value.copyWith(errorDescription: 'decode error');
  }
}

Widget _host(
  Widget child, {
  ThemeData? theme,
  Size size = const Size(320, 240),
}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}

void main() {
  late List<FakeVideoPlayerController> controllers;
  late VideoControllerFactory factory;

  setUp(() {
    controllers = <FakeVideoPlayerController>[];
    factory = (String path) {
      final FakeVideoPlayerController controller = FakeVideoPlayerController(
        path,
      );
      controllers.add(controller);
      return controller;
    };
  });

  Widget widget(String path) =>
      VideoPlayerWidget(videoPath: path, controllerFactory: factory);

  testWidgets('начало инициализации показывает загрузку', (tester) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Не удалось открыть видео'), findsNothing);
    expect(controllers, hasLength(1));
    expect(controllers.single.initializeCalls, 1);
  });

  testWidgets('ошибка инициализации показывает сообщение и повтор', (
    tester,
  ) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    controllers.single.failInitialization();
    await tester.pump();

    expect(find.text('Не удалось открыть видео'), findsOneWidget);
    expect(
      find.text('Файл может быть недоступен или его формат не поддерживается'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Повторить'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The technical details stay out of the visible message.
    expect(find.textContaining('/tmp/a.mp4'), findsNothing);
    expect(find.textContaining('cannot open file'), findsNothing);
  });

  testWidgets('повтор создаёт новую попытку и очищает прежнюю ошибку', (
    tester,
  ) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    controllers.single.failInitialization();
    await tester.pump();
    expect(find.text('Не удалось открыть видео'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Повторить'));
    await tester.pump();

    expect(controllers, hasLength(2));
    expect(controllers.last.initializeCalls, 1);
    expect(find.text('Не удалось открыть видео'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // While loading there is no retry button, so no duplicate attempt.
    expect(find.widgetWithText(OutlinedButton, 'Повторить'), findsNothing);
  });

  testWidgets('повтор после ошибки снова открывает видео', (tester) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    controllers.single.failInitialization();
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Повторить'));
    await tester.pump();
    controllers.last.completeInitialization();
    await tester.pump();

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.text('Не удалось открыть видео'), findsNothing);
  });

  testWidgets('инициализация без ответа заканчивается ошибкой', (tester) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));

    await tester.pump(const Duration(seconds: 29));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Не удалось открыть видео'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Повторить'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('поздняя ошибка предыдущего файла не меняет текущий', (
    tester,
  ) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    await tester.pumpWidget(_host(widget('/tmp/b.mp4')));
    expect(controllers, hasLength(2));

    controllers.first.failInitialization();
    await tester.pump();

    expect(find.text('Не удалось открыть видео'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('устаревший ответ первой попытки не побеждает новую', (
    tester,
  ) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    await tester.pumpWidget(_host(widget('/tmp/b.mp4')));
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    expect(controllers, hasLength(3));

    // The first attempt for the same path answers late.
    controllers.first.completeInitialization();
    await tester.pump();

    expect(find.text('Не удалось открыть видео'), findsNothing);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controllers.last.completeInitialization();
    await tester.pump();

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('закрытие во время загрузки не вызывает исключений', (
    tester,
  ) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    await tester.pumpWidget(_host(const SizedBox.shrink()));

    // The late answer of the closed preview must not touch the interface.
    controllers.single.completeInitialization();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controllers.single.disposeCalls, 1);
  });

  testWidgets('старые контроллеры освобождаются ровно один раз', (
    tester,
  ) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    await tester.pumpWidget(_host(widget('/tmp/b.mp4')));

    expect(controllers.first.disposeCalls, 1);
    // The old video does not keep playing after the switch.
    expect(controllers.first.pauseCalls, 1);
    expect(controllers.last.disposeCalls, 0);

    await tester.pumpWidget(_host(const SizedBox.shrink()));

    expect(controllers.last.disposeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ошибка от контроллера показывает сообщение и повтор', (
    tester,
  ) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    controllers.single.completeInitialization();
    await tester.pump();
    expect(find.byType(VideoPlayer), findsOneWidget);

    controllers.single.reportError();
    await tester.pump();

    expect(find.text('Не удалось открыть видео'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Повторить'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('после успешного открытия работает управление воспроизведением', (
    tester,
  ) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    controllers.single.completeInitialization();
    await tester.pump();

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_circle_fill));
    await tester.pump();

    expect(controllers.single.playCalls, 1);
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    await tester.pump();

    expect(controllers.single.pauseCalls, greaterThanOrEqualTo(1));
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });

  testWidgets('сообщение об ошибке видно в светлой и тёмной теме', (
    tester,
  ) async {
    for (final ThemeData theme in <ThemeData>[
      ThemeData.light(),
      ThemeData.dark(),
    ]) {
      await tester.pumpWidget(_host(widget('/tmp/theme.mp4'), theme: theme));
      controllers.last.failInitialization();
      await tester.pump();

      expect(find.text('Не удалось открыть видео'), findsOneWidget);
      final OutlinedButton button = tester.widget(
        find.widgetWithText(OutlinedButton, 'Повторить'),
      );
      expect(button.onPressed, isNotNull);
    }
  });

  testWidgets('повтор доступен с клавиатуры', (tester) async {
    await tester.pumpWidget(_host(widget('/tmp/a.mp4')));
    controllers.single.failInitialization();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controllers, hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('недоступный файл обычным контроллером показывает ошибку', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const VideoPlayerWidget(videoPath: '/tmp/not-existing.mp4')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Не удалось открыть видео'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Повторить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ошибка помещается в узкую панель', (tester) async {
    await tester.pumpWidget(
      _host(widget('/tmp/a.mp4'), size: const Size(140, 100)),
    );
    controllers.single.failInitialization();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Не удалось открыть видео'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Повторить'), findsOneWidget);
  });
}
