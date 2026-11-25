import 'package:flutter/material.dart';

import 'bp_nav_icons.dart';

/// Basirah's design system.
///
/// BlockP was the starting point: the same five tabs, the same settings rows,
/// the same blue. The measurements copied out of its screenshots (an arch cut
/// out of a saturated gradient, fractional type sizes, a 294 dp mascot slot)
/// were removed — they only made sense around artwork this app does not have.
/// What is left is one palette, one type scale, one card, one row and one nav
/// bar, so every screen is built from the same four pieces.
@immutable
class BpPalette extends ThemeExtension<BpPalette> {
  final Color canvas;
  final Color card;
  final Color innerCard;
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color primary;
  final Color primarySoft;
  final Color divider;
  final Color switchOn;
  final Color switchOff;
  final Color warningBg;
  final Color warningInk;
  final Color bannerBg;
  final Color navBg;
  final Color lock;

  const BpPalette({
    required this.canvas,
    required this.card,
    required this.innerCard,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.primary,
    required this.primarySoft,
    required this.divider,
    required this.switchOn,
    required this.switchOff,
    required this.warningBg,
    required this.warningInk,
    required this.bannerBg,
    required this.navBg,
    required this.lock,
  });

  /// Cool off-white canvas, white cards, one confident blue.
  ///
  /// Every text colour below clears 4.5:1 against the surface it is drawn on,
  /// so the palette is readable before it is pretty.
  static const light = BpPalette(
    canvas: Color(0xFFF3F6FC),
    card: Color(0xFFFFFFFF),
    innerCard: Color(0xFFF4F7FD),
    ink: Color(0xFF0C2340),
    inkSoft: Color(0xFF27405F),
    muted: Color(0xFF5A6B80),
    primary: Color(0xFF1A5CE5),
    primarySoft: Color(0xFFE4EDFF),
    divider: Color(0xFFE6EDF8),
    switchOn: Color(0xFF12A85C),
    switchOff: Color(0xFFD7DEE9),
    warningBg: Color(0xFFFFF3E4),
    warningInk: Color(0xFF8F5210),
    bannerBg: Color(0xFFE7EFFF),
    navBg: Color(0xFFFFFFFF),
    lock: Color(0xFF0C2340),
  );

  /// Deep navy canvas, raised cards. The same hierarchy, not the same colours.
  static const dark = BpPalette(
    canvas: Color(0xFF0C1521),
    card: Color(0xFF16202D),
    innerCard: Color(0xFF1C2735),
    ink: Color(0xFFF2F6FB),
    inkSoft: Color(0xFFCFDBE9),
    muted: Color(0xFF93A2B5),
    primary: Color(0xFF6FA0FF),
    primarySoft: Color(0xFF1B2C47),
    divider: Color(0xFF243040),
    switchOn: Color(0xFF2FBF71),
    switchOff: Color(0xFF394655),
    warningBg: Color(0xFF33240F),
    warningInk: Color(0xFFF0B26B),
    bannerBg: Color(0xFF1A2B45),
    navBg: Color(0xFF16202D),
    lock: Color(0xFFF2F6FB),
  );

  @override
  BpPalette copyWith({
    Color? canvas,
    Color? card,
    Color? innerCard,
    Color? ink,
    Color? inkSoft,
    Color? muted,
    Color? primary,
    Color? primarySoft,
    Color? divider,
    Color? switchOn,
    Color? switchOff,
    Color? warningBg,
    Color? warningInk,
    Color? bannerBg,
    Color? navBg,
    Color? lock,
  }) {
    return BpPalette(
      canvas: canvas ?? this.canvas,
      card: card ?? this.card,
      innerCard: innerCard ?? this.innerCard,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      muted: muted ?? this.muted,
      primary: primary ?? this.primary,
      primarySoft: primarySoft ?? this.primarySoft,
      divider: divider ?? this.divider,
      switchOn: switchOn ?? this.switchOn,
      switchOff: switchOff ?? this.switchOff,
      warningBg: warningBg ?? this.warningBg,
      warningInk: warningInk ?? this.warningInk,
      bannerBg: bannerBg ?? this.bannerBg,
      navBg: navBg ?? this.navBg,
      lock: lock ?? this.lock,
    );
  }

  @override
  BpPalette lerp(ThemeExtension<BpPalette>? other, double t) {
    if (other is! BpPalette) return this;
    return BpPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      innerCard: Color.lerp(innerCard, other.innerCard, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      switchOn: Color.lerp(switchOn, other.switchOn, t)!,
      switchOff: Color.lerp(switchOff, other.switchOff, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      warningInk: Color.lerp(warningInk, other.warningInk, t)!,
      bannerBg: Color.lerp(bannerBg, other.bannerBg, t)!,
      navBg: Color.lerp(navBg, other.navBg, t)!,
      lock: Color.lerp(lock, other.lock, t)!,
    );
  }
}

/// One corner scale: cards, nested panels, controls and the nav bar.
abstract final class BpRadii {
  /// Panels that hold a screen's content.
  static const card = 22.0;

  /// Panels nested inside a card.
  static const inner = 14.0;

  /// Buttons, chips and segmented controls.
  static const pill = 16.0;

  /// Banner strips.
  static const banner = 16.0;

  /// The bottom bar.
  static const nav = 20.0;

  static const dialog = 24.0;
}

/// One type scale.
///
/// Anek Latin is bundled with the app; Amiri is the fallback that carries
/// Arabic. Sizes step 12.5 / 14 / 15 / 20 / 26 / 32 — no fractional sizes
/// copied from another device's density bucket.
abstract final class BpType {
  static const family = 'AnekLatin';

  /// The Arabic wordmark "بَصِيرَة".
  static const arabicFamily = 'Amiri';

  /// The Arabic wordmark, rendered right-to-left.
  static const arabic = TextStyle(
    fontFamily: arabicFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.5,
  );

  /// Page titles.
  static const display = TextStyle(
    fontFamily: family,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.6,
  );

  /// Card and section titles.
  static const title = TextStyle(
    fontFamily: family,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.2,
  );

  /// Row titles.
  static const row = TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Body copy and descriptions.
  static const body = TextStyle(
    fontFamily: family,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Captions and metadata.
  static const small = TextStyle(
    fontFamily: family,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// Small caps section eyebrow.
  static const eyebrow = TextStyle(
    fontFamily: family,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.9,
  );

  /// Bottom-navigation labels.
  static const nav = TextStyle(
    fontFamily: family,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );

  /// Button labels.
  static const button = TextStyle(
    fontFamily: family,
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}

/// Palette, canvas and text helpers for the current theme.
extension BpTheme on BuildContext {
  BpPalette get bp =>
      Theme.of(this).extension<BpPalette>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? BpPalette.dark
          : BpPalette.light);

  bool get bpIsDark => Theme.of(this).brightness == Brightness.dark;

  TextStyle get display => BpType.display.copyWith(color: bp.ink);
  TextStyle get title => BpType.title.copyWith(color: bp.ink);
  TextStyle get rowTitle => BpType.row.copyWith(color: bp.ink);
  TextStyle get body => BpType.body.copyWith(color: bp.muted);
  TextStyle get small => BpType.small.copyWith(color: bp.muted);

  /// The flat canvas used behind pushed screens.
  ///
  /// A very soft light source at the top instead of the old saturated blue
  /// ramp: content is the subject, not the background.
  BoxDecoration get bpCanvas => BoxDecoration(
    color: bp.canvas,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: bpIsDark
          ? const [Color(0xFF121C29), Color(0xFF0C1521)]
          : const [Color(0xFFEAF1FE), Color(0xFFF3F6FC)],
      stops: const [0.0, 0.42],
    ),
  );
}

/// The canvas every tab sits on.
class BpCanvas extends StatelessWidget {
  final Widget child;

  const BpCanvas({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: context.bpCanvas,
      child: child,
    );
  }
}

/// A screen: canvas, safe area, a consistent gutter and bottom room.
class BpPage extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final bool scrollable;

  const BpPage({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    return BpCanvas(
      child: SafeArea(
        bottom: false,
        child: scrollable ? SingleChildScrollView(child: content) : content,
      ),
    );
  }
}

/// A tab's title block: the page name, an optional one-line explanation, and
/// an optional trailing action. Every tab starts with one so the screens read
/// as siblings rather than as five different layouts.
class BpHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;

  const BpHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.title.copyWith(fontSize: 26)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: context.body),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// Small caps label above a group of cards.
class BpSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const BpSectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: BpType.eyebrow.copyWith(
                color: context.bp.muted.withValues(alpha: 0.9),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The one card: surface, hairline border, soft lift, optional tap.
class BpCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final Color? borderColor;

  const BpCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final radius = BorderRadius.circular(BpRadii.card);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? bp.card,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? bp.divider),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C2340).withValues(
              alpha: context.bpIsDark ? 0.28 : 0.05,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A card with a header (icon, title, optional trailing) and a divided body.
class BpSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Color? iconColor;
  final Widget? trailing;

  const BpSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.iconColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return BpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              children: [
                _IconChip(
                  child: Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? bp.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: context.title)),
                ?trailing,
              ],
            ),
          ),
          Divider(height: 1, color: bp.divider),
          ...children,
        ],
      ),
    );
  }
}

/// The tinted rounded square behind a row's leading glyph.
class _IconChip extends StatelessWidget {
  final Widget child;

  const _IconChip({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.bp.primarySoft.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(11),
      ),
      child: child,
    );
  }
}

/// A Material icon drawn the way a row expects it.
class _LeadIcon extends StatelessWidget {
  const _LeadIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 20, color: context.bp.primary);
  }
}

/// One settings row: leading glyph, title, one-line description, and a
/// trailing switch / chevron / value. Rows are the app's main unit of
/// information, so the padding and the divider are fixed here once.
class BpRow extends StatelessWidget {
  final Widget icon;
  final String title;
  final String? description;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;
  final Color? iconColor;
  final IconData? trailingIcon;
  final Color? trailingIconColor;
  final bool tintIcon;

  const BpRow({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.iconColor,
    this.trailingIcon,
    this.trailingIconColor,
    this.tintIcon = true,
  });

  /// A row whose leading glyph is a Material icon.
  BpRow.withIcon(
    IconData iconData, {
    super.key,
    required this.title,
    this.description,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.iconColor,
    this.trailingIcon,
    this.trailingIconColor,
  }) : icon = _LeadIcon(iconData),
       tintIcon = true;

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (tintIcon)
                  _IconChip(
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: bp.primary),
                      child: IconTheme.merge(
                        data: IconThemeData(color: bp.primary),
                        child: icon,
                      ),
                    ),
                  )
                else
                  icon,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.rowTitle),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(description!, style: context.body),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ] else if (trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    trailingIcon,
                    size: 22,
                    color: trailingIconColor ?? bp.ink,
                  ),
                ] else if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, size: 22, color: bp.muted),
                ],
              ],
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, indent: 66, color: bp.divider),
      ],
    );
  }
}

/// A switch with a 48 dp touch target and a 44 x 26 track.
class BpSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const BpSwitch({super.key, required this.value, this.onChanged});

  static const double _width = 44;
  static const double _height = 26;

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: SizedBox(
          height: 48,
          width: _width + 4,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: _width,
              height: _height,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: !enabled
                    ? bp.switchOff.withValues(alpha: 0.5)
                    : (value ? bp.switchOn : bp.switchOff),
                borderRadius: BorderRadius.circular(_height / 2),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: _height - 6,
                  height: _height - 6,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The permission warning strip. Amber, not shouting: an icon, one line of
/// text and a chevron.
class BpWarningBanner extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onTap;

  const BpWarningBanner({
    super.key,
    required this.title,
    required this.message,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Material(
      color: bp.warningBg,
      borderRadius: BorderRadius.circular(BpRadii.banner),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 20,
                color: bp.warningInk,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message.isEmpty ? title : '$title $message',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BpType.body.copyWith(
                    color: bp.warningInk,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 20, color: bp.warningInk),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filled primary button.
class BpButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  const BpButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final enabled = onPressed != null;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: enabled ? Colors.white : bp.muted),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BpType.button.copyWith(
              color: enabled ? Colors.white : bp.muted,
            ),
          ),
        ),
      ],
    );
    return SizedBox(
      width: expand ? double.infinity : null,
      child: Material(
        color: enabled
            ? bp.primary
            : bp.switchOff.withValues(alpha: context.bpIsDark ? 0.5 : 0.7),
        borderRadius: BorderRadius.circular(BpRadii.pill),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(BpRadii.pill),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Outlined button for secondary choices and dialogs.
class BpOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const BpOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Material(
      color: bp.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BpRadii.pill),
        side: BorderSide(color: bp.divider, width: 1.2),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(BpRadii.pill),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: bp.ink),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: BpType.button.copyWith(color: bp.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two or three mutually exclusive options in one track. The selected option
/// is a raised card, which reads at a glance without a second accent colour.
class BpSegmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  const BpSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bp.innerCard,
        borderRadius: BorderRadius.circular(BpRadii.inner),
        border: Border.all(color: bp.divider),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? bp.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(BpRadii.inner - 4),
                    boxShadow: i == index
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF0C2340,
                              ).withValues(alpha: 0.09),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BpType.button.copyWith(
                      color: i == index ? bp.ink : bp.muted,
                      fontWeight: i == index
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The bottom bar: five destinations, a tinted active chip, and a height that
/// leaves the screen's content visible.
///
/// The old bar was a floating stadium with a 62.5 dp circle that overflowed
/// its own top edge and covered the last card on every tab. It is docked now,
/// and the scaffold reserves its height instead of overlaying content.
class BpBottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelected;

  const BpBottomBar({
    super.key,
    required this.index,
    required this.onSelected,
  });

  static const double barHeight = 62;

  static const tabs = <(BpNavIcon, String)>[
    (BpNavIcon.dashboard, 'Dashboard'),
    (BpNavIcon.blockList, 'Block list'),
    (BpNavIcon.premium, 'Premium'),
    (BpNavIcon.calm, 'Calm'),
    (BpNavIcon.support, 'Support'),
  ];

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Container(
      decoration: BoxDecoration(
        color: bp.navBg,
        border: Border(top: BorderSide(color: bp.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _NavItem(
                    glyph: tabs[i].$1,
                    label: tabs[i].$2,
                    selected: i == index,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final BpNavIcon glyph;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.glyph,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final color = selected ? bp.primary : bp.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? bp.primarySoft : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BpNavGlyph(glyph: glyph, color: color, size: 22),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BpType.nav.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog shell: a card, a title, the content, and one full-width action.
Future<T?> showBpDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  String confirmLabel = 'Confirm',
  bool showActions = true,
  T? result,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) {
      final bp = context.bp;
      return Dialog(
        backgroundColor: bp.card,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BpRadii.dialog),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: context.title),
              const SizedBox(height: 16),
              Flexible(child: SingleChildScrollView(child: content)),
              if (showActions) ...[
                const SizedBox(height: 20),
                BpButton(
                  label: confirmLabel,
                  onPressed: () => Navigator.of(context).pop(result),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Shared empty state: tinted glyph, title, explanation and an optional action.
class BpEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const BpEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bp.primarySoft.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: bp.primary),
          ),
          const SizedBox(height: 14),
          Text(title, style: context.title, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: context.body),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            BpOutlineButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}
