import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format.dart';
import 'theme.dart';

enum BtnKind { primary, soft, outline, danger }

class TkButton extends StatelessWidget {
  const TkButton(this.label,
      {super.key,
      this.onPressed,
      this.kind = BtnKind.primary,
      this.icon,
      this.trailing,
      this.small = false});
  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final IconData? icon;
  final IconData? trailing;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (TK.g, Colors.white, TK.g),
      BtnKind.soft => (TK.g50, TK.gd, TK.g50),
      BtnKind.outline => (Colors.white, TK.ink, TK.line),
      BtnKind.danger => (Colors.white, TK.bad, const Color(0xFFE6B5AF)),
    };
    final disabled = onPressed == null;
    return SizedBox(
      height: small ? 40 : 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: disabled ? TK.neutralBg : bg,
          foregroundColor: disabled ? TK.mut : fg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(small ? 10 : 14),
            side: BorderSide(color: disabled ? TK.neutralBg : border),
          ),
          textStyle: TextStyle(
              fontSize: small ? 13 : 15, fontWeight: FontWeight.w600),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            if (trailing != null) ...[const SizedBox(width: 8), Icon(trailing, size: 18)],
          ],
        ),
      ),
    );
  }
}

class TkCard extends StatelessWidget {
  const TkCard({super.key, required this.child, this.padding, this.onTap, this.color});
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: TK.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ),
    );
  }
}

enum Tone { ok, warn, bad, neutral }

(Color, Color) _tone(Tone t) => switch (t) {
      Tone.ok => (TK.g50, TK.gd),
      Tone.warn => (TK.warnBg, TK.warn),
      Tone.bad => (TK.badBg, TK.bad),
      Tone.neutral => (TK.neutralBg, TK.mut),
    };

class TkBadge extends StatelessWidget {
  const TkBadge(this.text, {super.key, this.tone = Tone.ok, this.icon});
  final String text;
  final Tone tone;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tone(tone);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Text(text,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class TkBanner extends StatelessWidget {
  const TkBanner(this.title,
      {super.key, this.body, this.tone = Tone.warn, this.icon, this.onTap});
  final String title;
  final String? body;
  final Tone tone;
  final IconData? icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tone(tone);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: fg, fontSize: 14, fontWeight: FontWeight.w700)),
                if (body != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(body!, style: TextStyle(color: fg, fontSize: 13)),
                  ),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: fg),
        ],
      ),
    )));
  }
}

class QtyStepper extends StatelessWidget {
  const QtyStepper(
      {super.key, required this.qty, required this.onMinus, required this.onPlus});
  final int qty;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  @override
  Widget build(BuildContext context) {
    Widget b(IconData i, VoidCallback? f, String label) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: f,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(i, size: 20, color: f == null ? TK.line : TK.gd),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TK.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        b(Icons.remove, onMinus, 'Kurangi'),
        SizedBox(
          width: 28,
          child: Text('$qty',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        b(Icons.add, onPlus, 'Tambah'),
      ]),
    );
  }
}

class TkField extends StatelessWidget {
  const TkField(
      {super.key,
      required this.label,
      this.controller,
      this.hint,
      this.obscure = false,
      this.prefix,
      this.suffix,
      this.keyboard,
      this.digitsOnly = false,
      this.onChanged,
      this.maxLines = 1});
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final bool obscure;
  final String? prefix;
  final Widget? suffix;
  final TextInputType? keyboard;
  final bool digitsOnly;
  final ValueChanged<String>? onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: TK.line),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: TK.mut)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          maxLines: maxLines,
          onChanged: onChanged,
          inputFormatters:
              digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            suffixIcon: suffix,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            enabledBorder: border,
            border: border,
            focusedBorder: border.copyWith(
                borderSide: const BorderSide(color: TK.g, width: 1.6)),
          ),
        ),
      ],
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value,
      {super.key, this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final s = TextStyle(
        fontSize: bold ? 15 : 14,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: color ?? (bold ? TK.ink : TK.mut));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: s)),
          const SizedBox(width: 12),
          Text(value,
              style: s.copyWith(
                  color: color ?? TK.ink,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class Cap extends StatelessWidget {
  const Cap(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .7,
                color: TK.mut)),
      );
}

class Price extends StatelessWidget {
  const Price(this.value, {super.key, this.size = 15, this.color});
  final int value;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(rupiah(value),
      style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: color ?? TK.ink,
          fontFeatures: const [FontFeature.tabularFigures()]));
}

/// Kerangka layar standar: app bar + isi scroll + bar aksi bawah.
class Screen extends StatelessWidget {
  const Screen(
      {super.key,
      required this.title,
      required this.child,
      this.bottom,
      this.actions,
      this.showBack = true,
      this.padding = const EdgeInsets.all(16)});
  final String title;
  final Widget child;
  final Widget? bottom;
  final List<Widget>? actions;
  final bool showBack;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: showBack,
        actions: actions,
        backgroundColor: TK.bg,
      ),
      body: SafeArea(
        child: SingleChildScrollView(padding: padding, child: child),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: TK.line)),
              ),
              child: SafeArea(top: false, child: bottom!),
            ),
    );
  }
}

void toast(BuildContext c, String msg) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: TK.ink,
    ));
}

const gap8 = SizedBox(height: 8);
const gap12 = SizedBox(height: 12);
const gap16 = SizedBox(height: 16);
const gap24 = SizedBox(height: 24);


/// Kontrol segmen abu-abu dengan pil putih untuk pilihan aktif (desain titik).
class TkSegmented<T> extends StatelessWidget {
  const TkSegmented(
      {super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: TK.neutralBg, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        for (final (v, label) in options)
          Expanded(
            child: Semantics(
              button: true,
              selected: v == value,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: v == value
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: .08),
                                blurRadius: 6,
                                offset: const Offset(0, 1))
                          ]
                        : null,
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: v == value ? TK.ink : TK.mut)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Kotak ikon bulat-sudut (leading pada baris dan kartu).
class IconTile extends StatelessWidget {
  const IconTile(this.icon,
      {super.key, this.size = 44, this.bg = TK.g50, this.fg = TK.g});
  final IconData icon;
  final double size;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .28)),
        child: Icon(icon, size: size * .5, color: fg),
      );
}

/// Tombol ikon tonal (bar atas katalog).
class TonalIconButton extends StatelessWidget {
  const TonalIconButton(this.icon, this.tooltip, this.onPressed, {super.key});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: TK.g50,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: SizedBox(
                width: 48, height: 48, child: Icon(icon, color: TK.gd, size: 22)),
          ),
        ),
      );
}
