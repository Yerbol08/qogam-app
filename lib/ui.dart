import 'package:flutter/material.dart';
import 'strings.dart';

const teal = Color(0xff087f75);
const ink = Color(0xff172c29);
const muted = Color(0xff5c706a);
const soft = Color(0xffe0f2eb);
const line = Color(0xffdce6e1);

ThemeData qogamTheme() {
  final base = ThemeData(useMaterial3: true, fontFamily: 'NotoSans');
  return base.copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: teal,
      primary: teal,
      surface: Colors.white,
      onSurface: ink,
    ),
    scaffoldBackgroundColor: const Color(0xfff5f8f7),
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineMedium: const TextStyle(
            color: ink,
            fontFamily: 'NotoSans',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.25,
            letterSpacing: -.7,
          ),
          headlineSmall: const TextStyle(
            color: ink,
            fontFamily: 'NotoSans',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.3,
            letterSpacing: -.5,
          ),
          titleLarge: const TextStyle(
            color: ink,
            fontFamily: 'NotoSans',
            fontSize: 19,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
          bodyLarge: const TextStyle(
            color: ink,
            fontFamily: 'NotoSans',
            fontSize: 16,
            height: 1.5,
          ),
          bodyMedium: const TextStyle(
            color: ink,
            fontFamily: 'NotoSans',
            fontSize: 14,
            height: 1.5,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xfff5f8f7),
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSans',
        color: ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: soft,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'NotoSans',
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? teal : muted,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: line),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: teal,
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      labelStyle: const TextStyle(
        fontFamily: 'NotoSans',
        color: muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: 'NotoSans',
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(16),
      labelStyle: const TextStyle(color: muted),
      hintStyle: const TextStyle(color: muted, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: teal, width: 1.5),
      ),
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        textStyle: const TextStyle(
          fontFamily: 'NotoSans',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(
          fontFamily: 'NotoSans',
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 28),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  const Panel({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
}

class PageHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  const PageHeading(this.title, {super.key, this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: const TextStyle(color: muted)),
        ],
      ],
    ),
  );
}

class DemoNotice extends StatelessWidget {
  final Strings s;
  const DemoNotice(this.s, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: soft.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 18, color: teal),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            s.t('note'),
            style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  @override
  Widget build(BuildContext context) => Panel(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: soft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: teal, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted),
          ),
        ],
      ),
    ),
  );
}

class StatusBadge extends StatelessWidget {
  final String status;
  final Strings s;
  const StatusBadge(this.status, this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final colors = switch (status) {
      'progress' => [const Color(0xffe8f2ff), const Color(0xff1263ab)],
      'resolved' => [const Color(0xffe1f3e9), const Color(0xff167653)],
      'published' => [soft, teal],
      _ => [const Color(0xfffff0d2), const Color(0xff875a13)],
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors[0],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        s.t(status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colors[1],
        ),
      ),
    );
  }
}

class BottomAction extends StatelessWidget {
  final String label;
  final String? hint;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  const BottomAction({
    super.key,
    required this.label,
    this.hint,
    this.icon,
    this.onPressed,
    this.busy = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: busy ? null : onPressed,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (icon != null)
                    Icon(icon, size: 20),
                  if (busy || icon != null) const SizedBox(width: 9),
                  Flexible(child: Text(label, textAlign: TextAlign.center)),
                ],
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const InfoRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: teal),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
