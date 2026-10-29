/// Целевые числовые токены варианта 10.
///
/// Источник: `docs/design/variant-10/tokens.json`. Это инженерная калибровка
/// под эталон; значения сверены с работающим приложением.
library;

import 'package:flutter/material.dart';

/// Шаг вертикального и горизонтального ритма, логические пиксели.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

/// Радиусы скруглений. Панель крупнее контрола, карточка компактна.
abstract final class AppRadius {
  static const double card = 8;
  static const double control = 10;
  static const double chip = 8;
  static const double panel = 16;
}

/// Толщина обводок.
abstract final class AppStroke {
  static const double normal = 1;
  static const double selection = 2;
  static const double focus = 2;
}

/// Размеры зон и контролов.
abstract final class AppSizes {
  static const double appBar = 64;
  static const double scopeBar = 60;
  static const double pagePadding = 16;
  static const double gridGap = 12;
  static const double preferredCardMinWidth = 240;
  static const double cardImageAspectRatio = 1.8;
  static const double cardFooterMinHeight = 56;
  static const double editorDefaultHeight = 248;
  static const double editorMinHeight = 224;
  static const double editorMaxHeightFraction = 0.45;
  static const double editorCollapsedHeight = 52;
  static const double controlHeight = 36;
  static const double iconHitArea = 36;
  static const double chipMinHeight = 28;
  static const double chipRemoveHitArea = 24;

  /// Ширина, начиная с которой workspace получает две верхние строки.
  static const double wideMinWidth = 1440;

  /// Минимальная ширина, на которой верхняя панель ещё остаётся одной строкой.
  static const double compactMinWidth = 1100;

  /// Минимальная видимая высота сетки, которую не должен выдавливать редактор.
  static const double gridMinVisibleHeight = 220;
}

/// Длительности и кривая анимаций интерфейса.
abstract final class AppMotion {
  static const Duration hover = Duration(milliseconds: 120);
  static const Duration disclosure = Duration(milliseconds: 180);
  static const Duration stateChange = Duration(milliseconds: 150);
  static const Curve easing = Curves.easeOut;
}
