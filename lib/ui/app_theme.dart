import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sistema de design do app: uma estetica escura sobria, de baixo contraste
/// cromatico e alto contraste de leitura.
///
/// Todas as cores e medidas vivem aqui. Os widgets consultam o tema em vez de
/// declarar cor propria — sem isso, cada tela vira uma ilha e a aparencia
/// deriva a cada mudanca.
abstract final class AppTheme {
  // Superficies em camadas. A diferenca entre elas e pequena de proposito:
  // profundidade se sugere, nao se grita.
  static const _bg = Color(0xFF0E1013);
  static const _surface = Color(0xFF14171C);
  static const _surfaceHigh = Color(0xFF1A1E25);
  static const _surfaceHighest = Color(0xFF222831);
  static const _outline = Color(0xFF272C35);

  /// Indigo dessaturado: destaca sem competir com o texto.
  static const _accent = Color(0xFF8AA2FF);
  static const _accentSoft = Color(0xFF2A3350);

  /// Azul dos titulos e do negrito no Markdown renderizado.
  ///
  /// Separado do [_accent] de proposito. Os dois dividiam a mesma cor e um
  /// titulo passava por link — que e clicavel, enquanto titulo nao e. Este
  /// puxa para o azul-ceu: quase trinta graus de matiz de distancia do indigo,
  /// e mais saturado, o bastante para os dois nao se confundirem lado a lado.
  ///
  /// A divisao de papeis fica assim: o indigo e do **app** (link, botao,
  /// seleçao) e este e do **seu texto** (estrutura e enfase).
  static const realce = Color(0xFF57BDF0);

  /// Rosa das tags. Vale em todo o app: e a mesma cor dos nos de tag no grafo
  /// e das etiquetas no cabeçalho da nota, entao reconhecer uma tag numa tela
  /// ensina a reconhece-la na outra.
  static const tag = Color(0xFFE07A9B);

  static const _text = Color(0xFFE4E7EC);
  static const _textMuted = Color(0xFF8B93A1);
  static const _danger = Color(0xFFFF8A8A);

  /// Espacamentos: uma escala curta evita o "cada tela com seu padding".
  static const gapXs = 4.0;
  static const gapSm = 8.0;
  static const gapMd = 12.0;
  static const gapLg = 16.0;
  static const gapXl = 24.0;

  static const radiusSm = 6.0;
  static const radiusMd = 10.0;
  static const radiusLg = 14.0;

  /// Barra de titulo do Windows acompanhando o fundo do app.
  static const systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  );

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: _accent,
      onPrimary: Color(0xFF0E1013),
      primaryContainer: _accentSoft,
      onPrimaryContainer: _text,
      secondary: _accent,
      onSecondary: Color(0xFF0E1013),
      surface: _surface,
      onSurface: _text,
      surfaceContainerLowest: _bg,
      surfaceContainerLow: _surface,
      surfaceContainer: _surfaceHigh,
      surfaceContainerHigh: _surfaceHigh,
      surfaceContainerHighest: _surfaceHighest,
      onSurfaceVariant: _textMuted,
      outline: _outline,
      outlineVariant: _outline,
      error: _danger,
      onError: Color(0xFF0E1013),
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: _bg,
      canvasColor: _bg,
      dividerColor: _outline,
      dividerTheme: const DividerThemeData(
        color: _outline,
        thickness: 1,
        space: 1,
      ),
      textTheme: _textTheme(base.textTheme),

      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        iconTheme: IconThemeData(color: _textMuted, size: 19),
      ),

      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: _bg,
        indicatorColor: _accentSoft,
        selectedIconTheme: IconThemeData(color: _accent, size: 21),
        unselectedIconTheme: IconThemeData(color: _textMuted, size: 21),
        selectedLabelTextStyle: TextStyle(
          color: _text,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: _textMuted, fontSize: 11),
      ),

      iconTheme: const IconThemeData(color: _textMuted, size: 19),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: _textMuted,
          hoverColor: _surfaceHigh,
          highlightColor: _surfaceHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: const Color(0xFF0E1013),
          disabledBackgroundColor: _surfaceHighest,
          disabledForegroundColor: _textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _accent,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? _accentSoft : _bg,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? _accent : _textMuted,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: _outline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm),
            ),
          ),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: _textMuted,
        textColor: _text,
        selectedColor: _accent,
        selectedTileColor: _accentSoft,
        horizontalTitleGap: 10,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: _bg,
        side: const BorderSide(color: _outline),
        labelStyle: const TextStyle(color: _textMuted, fontSize: 11.5),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: _surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          side: const BorderSide(color: _outline),
        ),
        textStyle: const TextStyle(color: _text, fontSize: 13.5),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: _outline),
        ),
        titleTextStyle: const TextStyle(
          color: _text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _bg,
        hintStyle: const TextStyle(color: _textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: _outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: _outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: _accent, width: 1.4),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surfaceHighest,
        contentTextStyle: const TextStyle(color: _text, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),

      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered)
              ? _textMuted.withValues(alpha: 0.5)
              : _outline,
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _surfaceHighest,
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: _outline),
        ),
        textStyle: const TextStyle(color: _text, fontSize: 12),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _accent,
        linearTrackColor: _surfaceHighest,
      ),
    );
  }

  /// Hierarquia tipografica enxuta: titulos com espacamento negativo para
  /// parecerem mais firmes, corpo com altura de linha generosa para leitura.
  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      titleLarge: base.titleLarge?.copyWith(
        color: _text,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: _text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: base.titleSmall?.copyWith(
        color: _text,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(color: _text, height: 1.55),
      bodyMedium: base.bodyMedium?.copyWith(
        color: _text,
        fontSize: 13.5,
        height: 1.5,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: _textMuted,
        fontSize: 12.5,
        height: 1.5,
      ),
      labelMedium: base.labelMedium?.copyWith(color: _text, fontSize: 12),
      labelSmall: base.labelSmall?.copyWith(
        color: _textMuted,
        fontSize: 11,
        letterSpacing: 0.2,
      ),
    );
  }
}
