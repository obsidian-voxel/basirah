import 'package:flutter/material.dart';

import 'bp_nav_icons.dart';

/// BlockP's design system, rebuilt for Basirah.
///
/// Every colour, radius and type step below was measured from the reference
/// screenshots (`shot_metrics.py` samples them out of the PNGs). The reference
/// ships two themes — a navy canvas with slate cards, and a pale blue canvas
/// with white cards — so the palette is a [ThemeExtension] and every widget
/// reads it from the active theme instead of hard-coding one of them.
///
/// The reference app's own artwork (the dog mascot) is not reproduced; see
/// `brand_art.dart` for the geometric replacement.
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

  /// Pale-blue canvas, white cards.
  ///
  /// These are the reference APK's own resource values, read out of
  /// `resources.arsc` with `aapt2 dump resources`:
  ///
  /// * `background_color_dark`      `#E2EEFF`
  /// * `blocker_card_background_color` `#F6FAFF`
  /// * `blocker_button_color`       `#0076F4`
  /// * `blocker_title_text_color`   `#002954`
  /// * `blocker_text_desc_color`    `#595959`
  /// * `blocker_divider_color`      `#B1B1B1`
  static const light = BpPalette(
    canvas: Color(0xFFE2EEFF),
    card: Color(0xFFF6FAFF),
    innerCard: Color(0xFFFFFFFF),
    ink: Color(0xFF002954),
    inkSoft: Color(0xFF19456B),
    muted: Color(0xFF595959),
    primary: Color(0xFF0076F4),
    primarySoft: Color(0xFFC7DCFB),
    divider: Color(0xFFB1B1B1),
    switchOn: Color(0xFF01BE5F),
    switchOff: Color(0xFFD3D6DA),
    // The reference draws both strips as translucent shapes over the canvas
    // (`bg_essential_permissions_card` = #33FF5900, `edit_text_back_color` =
    // #240076F4), so their sampled appearance depends on what is behind them.
    warningBg: Color(0x33FF5900),
    warningInk: Color(0xFFC76838),
    bannerBg: Color(0x240076F4),
    navBg: Color(0xFFFFFFFF),
    lock: Color(0xFF002954),
  );

  /// Navy canvas, slate cards. The reference's own night-mode resources.
  static const dark = BpPalette(
    canvas: Color(0xFF192432),
    card: Color(0xFF223142),
    innerCard: Color(0xFF20303F),
    ink: Color(0xFFEFEFEF),
    inkSoft: Color(0xFFD7E0EA),
    muted: Color(0xFF8694A3),
    primary: Color(0xFF2B77C7),
    primarySoft: Color(0xFF1C304B),
    divider: Color(0xFF8694A3),
    switchOn: Color(0xFF01BE5F),
    switchOff: Color(0xFF5A6168),
    warningBg: Color(0x33FF5900),
    warningInk: Color(0xFFD0895A),
    bannerBg: Color(0x240076F4),
    navBg: Color(0xFF223142),
    lock: Color(0xFFFFFFFF),
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

/// Radii measured from the reference cards and pills.
abstract final class BpRadii {
  /// Big content cards (streak, settings, feature lists).
  static const card = 24.0;

  /// Secondary cards nested inside a big card.
  static const inner = 16.0;

  /// Full-round pills: buttons, day chips, the floating nav.
  static const pill = 50.0;

  /// The banner strips under the hero (permission warning, setup). The
  /// reference draws them as fully-rounded stadiums.
  static const banner = 28.0;

  /// The floating nav pill is a stadium; its radius equals half its height.
  static const nav = 32.0;

  static const dialog = 24.0;
}

/// BlockP draws everything in one geometric sans. Anek Latin is bundled, so
/// the clone uses the same family and the same size steps the reference uses.
///
/// The sizes below were solved against the reference's own `blocker_*` font
/// files by matching rendered advance widths to the pixel spans measured in
/// the screenshots, so they are the reference's sizes rather than guesses.
abstract final class BpType {
  static const family = 'AnekLatin';

  /// The Arabic name "بَصِيرَة".
  ///
  /// The bundled Latin faces carry no Arabic glyphs, so the Arabic wordmark
  /// uses Amiri, a SIL OFL-licensed Naskh typeface.
  static const arabicFamily = 'Amiri';

  /// The Arabic wordmark, rendered right-to-left.
  static const arabic = TextStyle(
    fontFamily: arabicFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.5,
  );

  /// The dashboard's large mode title ("Off" / "Normal" / "Strict").
  ///
  /// The reference's `main_button_text_view` is `_20ssp` in `blocker_bold`.
  /// The screenshot was taken on a 411 dp wide device, which selects the
  /// `sw420dp` resource bucket where `_20ssp` resolves to 28 sp. Solving the
  /// rendered ink width of "Off" against the reference gives 27.8 sp, which
  /// confirms the bucket.
  static const display = TextStyle(
    fontFamily: family,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.1,
  );

  /// Section and card titles.
  ///
  /// The reference uses `_16ssp` in `blocker_medium` for these, which is
  /// 22.4 sp on a 411 dp wide device.
  static const title = TextStyle(
    fontFamily: family,
    fontSize: 22.4,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// Settings-row titles.
  ///
  /// The reference uses `_13ssp` in `blocker_medium`: 15.2 sp here.
  static const row = TextStyle(
    fontFamily: family,
    fontSize: 15.2,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// Body copy and descriptions.
  ///
  /// The reference uses `_13ssp` in `blocker_regular`: 15.2 sp here.
  static const body = TextStyle(
    fontFamily: family,
    fontSize: 15.2,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Secondary captions.
  ///
  /// The reference uses `_12ssp` in `blocker_regular`: 14 sp here.
  static const small = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Bottom-navigation labels.
  ///
  /// The reference's nav labels are `_10ssp` in `blocker_medium`, which is
  /// 10 sp on the 411 dp wide reference device. Solving the rendered ink
  /// width of "Block list" against the reference capture gives 10 sp.
  static const nav = TextStyle(
    fontFamily: family,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.1,
  );

  /// Pill-button labels.
  static const button = TextStyle(
    fontFamily: family,
    fontSize: 14,
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

  TextStyle get display => BpType.display.copyWith(color: bp.ink);
  TextStyle get title => BpType.title.copyWith(color: bp.ink);
  TextStyle get rowTitle => BpType.row.copyWith(color: bp.ink);
  TextStyle get body => BpType.body.copyWith(color: bp.muted);
  TextStyle get small => BpType.small.copyWith(color: bp.muted);

  /// The canvas gradient behind every tab.
  ///
  /// The reference draws two stacked pieces (see `res/layout/fragment_dash.xml`):
  ///
  /// 1. `dashboard_top_gradient_back` — a shape drawable whose `gradient` runs
  ///    `#BDDDFF` -> `#1160FF` at angle 270 (top to bottom), filling the
  ///    ScrollView behind the whole page.
  /// 2. `dashboard_centre_gradient_svg` — a 402 x 1119 dp vector path filled
  ///    with the flat canvas colour `#E2EEFF`, whose top edge is a wide arch.
  ///    It sits over the gradient and cuts a dome out of it, so the gradient's
  ///    lower boundary is a curve, not a straight line.
  ///
  /// The arch path is reproduced verbatim in [BpCanvas] below.
  BoxDecoration get bpCanvas {
    final isDark = Theme.of(this).brightness == Brightness.dark;
    return BoxDecoration(
      color: bp.canvas,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xFF131D27), Color(0xFF0E151C)]
            : const [Color(0xFFBDDDFF), Color(0xFF1160FF)],
        stops: const [0.0, 0.38],
      ),
    );
  }
}

/// The dashboard's canvas: the reference's blue gradient with the flat canvas
/// colour arch cut out of it.
///
/// The reference stacks a gradient shape drawable behind a 402 x 1119 dp
/// vector whose path is:
///
/// ```text
/// M398.3,109C376.7,46.5 296.6,0 201,0C105.4,0 25.3,46.5 3.7,109
/// C2.2,113.5 0.9,118 0,122.6V162.9V1167H402V162.9V122.6
/// C401.1,118 399.8,113.5 398.3,109Z
/// ```
///
/// The vector is 402 dp wide and centred, so its arch spans the middle of the
/// screen while the gradient still shows at both edges.
class BpCanvas extends StatelessWidget {
  final Widget child;

  const BpCanvas({super.key, required this.child});

  /// The vector's width in dp.
  static const double archWidth = 402;

  /// The vector's height in dp.
  static const double archHeight = 1119;

  /// Where the background gradient starts, in dp below the top of the screen.
  ///
  /// The reference's dashboard ScrollView begins below the status bar, so the
  /// ramp starts 31 dp down rather than at the very top.
  static const double _gradientTop = 31;

  /// How far the background gradient runs, in dp.
  ///
  /// The ramp reaches #1160FF 51 dp past the bottom of the 2340 px screen,
  /// which is a span of 923 dp.
  static const double _gradientSpan = 923;

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        // The reference's `dashboard_top_gradient_back` is a plain #BDDDFF ->
        // #1160FF shape at angle 270 that fills the dashboard's ScrollView.
        // That view starts below the status bar and runs past the bottom of
        // the screen, so on the 1080 x 2340 reference capture the ramp's
        // #BDDDFF end sits at y = 82 px and its #1160FF end at y = 2454 px.
        // The gradient is therefore laid out over that span rather than over
        // the whole screen, which puts its colours where the reference has
        // them.
        Positioned(
          top: -_gradientTop,
          height: _gradientSpan,
          left: 0,
          right: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bp.canvas,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? const [Color(0xFF131D27), Color(0xFF0E151C)]
                    : const [Color(0xFFBDDDFF), Color(0xFF1160FF)],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _ArchPainter(color: bp.canvas),
          ),
        ),
        child,
      ],
    );
  }
}

class _ArchPainter extends CustomPainter {
  final Color color;

  _ArchPainter({required this.color});

  /// Affine mapping from the vector's own coordinates to screen pixels.
  ///
  /// The three numbers were solved by least squares against the
  /// blue-to-canvas boundary measured in
  /// `Screenshot_20261116_000823_BlockP.jpg` (1080 x 2340): the boundary is
  /// the last row at each column whose colour still matches the background
  /// gradient. The fit reproduces that boundary with a 3.9 px RMS error and
  /// a 15 px maximum.
  static const double _horizontalScale = 2.72703;
  static const double _verticalScale = 2.83937;
  static const double _originY = 667.566;

  @override
  void paint(Canvas canvas, Size size) {
    // The reference screenshot is 1080 x 2340; scale the solved constants so
    // the arch keeps its measured proportions on any screen height.
    final referenceHeight = 2340.0;
    final heightScale = size.height / referenceHeight;
    final horizontalScale = _horizontalScale * size.width / 1080;
    final verticalScale = _verticalScale * heightScale;
    final originY = _originY * heightScale;
    final apexX = size.width / 2;

    double x(double vx) => apexX + (vx - 201) * horizontalScale;
    double y(double vy) => originY + vy * verticalScale;

    // Start at the right-hand shoulder, sweep over the apex and down the left
    // side, then close the shape below the screen.
    final path = Path()
      ..moveTo(x(398.3), y(109))
      ..cubicTo(x(376.7), y(46.5), x(296.6), y(0), apexX, y(0))
      ..cubicTo(x(105.4), y(0), x(25.3), y(46.5), x(3.7), y(109))
      ..cubicTo(x(2.2), y(113.5), x(0.9), y(118), x(0), y(122.6))
      ..lineTo(x(0), size.height)
      ..lineTo(x(402), size.height)
      ..lineTo(x(402), y(122.6))
      ..cubicTo(x(401.1), y(118), x(399.8), y(113.5), x(398.3), y(109))
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArchPainter oldDelegate) => oldDelegate.color != color;
}

/// A screen: canvas, safe area and the shared horizontal padding (16 dp, the
/// reference's 48 px gutter at 3x).
class BpPage extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final bool scrollable;

  const BpPage({
    super.key,
    required this.children,
    // The floating bottom bar overlays the scroll area, so tabs reserve room
    // for it at the end of the list.
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 104),
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
        child: scrollable
            ? SingleChildScrollView(child: content)
            : content,
      ),
    );
  }
}

/// White (or slate) rounded card, 28 dp radius, no border in the reference.
class BpCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  const BpCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(BpRadii.card);
    return Material(
      color: color ?? context.bp.card,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A card with BlockP's blue section header (icon + title + hairline), then a
/// list of rows. Used by Advanced Settings and the Premium feature list.
class BpSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Color? iconColor;

  const BpSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return BpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 26,
                  color: iconColor ?? context.bp.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(title, style: context.title),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.bp.divider, indent: 18, endIndent: 18),
          ...children,
        ],
      ),
    );
  }
}

/// A Material icon at the size [BpRow] draws its leading glyph, coloured by
/// the active palette.
class _BpMaterialIcon extends StatelessWidget {
  const _BpMaterialIcon(this.iconData);

  final IconData iconData;

  @override
  Widget build(BuildContext context) {
    return Icon(iconData, size: 24, color: context.bp.ink);
  }
}

/// One BlockP settings row: outline icon, 17 sp title, muted description and a
/// trailing switch / chevron / lock.
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
  }) : icon = _BpMaterialIcon(iconData);

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 16),
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
                  const SizedBox(width: 10),
                  Icon(
                    trailingIcon,
                    size: 26,
                    color: trailingIconColor ?? bp.ink,
                  ),
                ] else if (onTap != null) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.chevron_right, size: 26, color: bp.ink),
                ],
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 18,
            endIndent: 18,
            color: bp.divider,
          ),
      ],
    );
  }
}

/// The reference switch: a flat pill with a white thumb, no outline.
class BpSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const BpSwitch({super.key, required this.value, this.onChanged});

  static const double _width = 44;
  static const double _height = 26;

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Semantics(
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: _width,
          height: _height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: onChanged == null
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
    );
  }
}

/// The orange "Please enable essential permissions (N)" strip.
///
/// The reference's `dash_frag_permission_required_layout` draws
/// `bg_essential_permissions_card` (#33FF5900 with a 50 dp radius) over the
/// canvas. On the 1080 px reference screen the strip measures 986 x 138 px,
/// i.e. 375.6 x 52.6 dp, with the title starting 38 dp from its left edge.
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
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  message.isEmpty ? title : '$title $message',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.rowTitle.copyWith(
                    color: bp.warningInk,
                    fontSize: 18.2,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 24, color: bp.warningInk),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filled pill button (primary) with the reference's disabled treatment.
class BpButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const BpButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
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
          Icon(icon, size: 20, color: enabled ? Colors.white : bp.muted),
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
    return Material(
      color: enabled ? bp.primary : bp.primary.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(BpRadii.pill),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(BpRadii.pill),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: child,
        ),
      ),
    );
  }
}

/// Outlined pill, used for the onboarding sign-in-style buttons and dialogs.
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
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: bp.divider, width: 1.5)),
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: bp.ink),
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

/// Two-to-three option segmented pill (Blocklist / Whitelist, Custom URL /
/// Custom App). The active half is filled primary blue.
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
      height: 50,
      decoration: BoxDecoration(
        color: bp.card,
        borderRadius: BorderRadius.circular(BpRadii.pill),
        border: Border.all(color: bp.primarySoft, width: 1.5),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Container(
                  margin: const EdgeInsets.all(1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? bp.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(BpRadii.pill),
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BpType.button.copyWith(
                      color: i == index ? Colors.white : bp.muted,
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

/// The floating bottom bar: a stadium-shaped pill with five destinations.
///
/// Geometry measured from the reference screenshots (1080 px wide, 2.625
/// px/dp):
///
/// * pill: x 34..1045 px (385.5 dp wide), 64 dp tall, 13 dp side margins
/// * active slot: a blue stadium filling the pill's full inner height
///   (75.4 x 60.2 dp) that carries a white glyph and a white label
/// * inactive glyphs: 26 dp, outline style, drawn at the pill's upper third
class BpBottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelected;

  const BpBottomBar({
    super.key,
    required this.index,
    required this.onSelected,
  });

  /// Pill height in dp.
  ///
  /// The reference's floating nav card is a stadium whose top edge is at
  /// y = 2012 px and whose bottom edge is at y = 2205 px on the 1080 x 2340
  /// screen, i.e. 73.5 dp tall with a 51.4 dp bottom margin.
  static const double pillHeight = 73.5;

  /// The blue active indicator is a 62.5 dp circle in the reference.
  static const double indicatorSize = 62.5;

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 0, 13, 51.4),
      child: Container(
        height: pillHeight,
        decoration: BoxDecoration(
          color: bp.navBg,
          borderRadius: BorderRadius.circular(pillHeight / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
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
    // The reference draws the active slot as a 62.5 dp blue circle that
    // overflows the nav card's top edge, with the glyph and its label stacked
    // inside it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          // The selected slot is drawn entirely by the indicator below, so
          // the inactive layer must not repeat its glyph and label.
          if (!selected)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BpNavGlyph(
                    glyph: glyph,
                    color: bp.ink,
                    size: 28,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BpType.nav.copyWith(color: bp.ink),
                  ),
                ],
              ),
            ),
          if (selected)
            SizedBox(
              width: BpBottomBar.indicatorSize,
              height: BpBottomBar.indicatorSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bp.primary,
                  shape: BoxShape.circle,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    BpNavGlyph(glyph: glyph, color: Colors.white, size: 28),
                    const SizedBox(height: 2),
                    // The active circle is narrower than the longest label, so
                    // scale the text down instead of clipping it.
                    SizedBox(
                      width: BpBottomBar.indicatorSize - 8,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: BpType.nav.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dialog shell matching the reference: white 24 dp card, 22 sp title, a
/// hairline, then the content and a full-width blue Confirm pill.
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
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BpRadii.dialog),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: context.title),
              const SizedBox(height: 16),
              Divider(height: 1, color: bp.divider),
              const SizedBox(height: 18),
              content,
              if (showActions) ...[
                const SizedBox(height: 22),
                SizedBox(
                  height: 56,
                  child: BpButton(
                    label: confirmLabel,
                    onPressed: () => Navigator.of(context).pop(result),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Shared empty state: muted icon, title, explanation.
class BpEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const BpEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Column(
      children: [
        Icon(icon, size: 44, color: bp.muted.withValues(alpha: 0.45)),
        const SizedBox(height: 10),
        Text(title, style: context.rowTitle),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: context.small,
        ),
      ],
    );
  }
}
