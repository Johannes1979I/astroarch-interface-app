import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'responsive.dart';

/// Card standard con titolo, valore grande, sottotitolo e badge stato.
class StatusCard extends StatelessWidget {
  final String header;
  final String value;
  final String? subtitle;
  final Color? badgeColor;
  final String? badgeText;
  final IconData? leading;
  final VoidCallback? onTap;

  const StatusCard({
    super.key,
    required this.header,
    required this.value,
    this.subtitle,
    this.badgeColor,
    this.badgeText,
    this.leading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: T.panel(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.line(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (leading != null) ...[
                  Icon(leading, size: 13, color: T.muted(context)),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    header.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 1.3,
                      color: T.muted(context),
                    ),
                  ),
                ),
                if (badgeText != null) StatusBadge(text: badgeText!, color: badgeColor ?? T.ok(context)),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!, style: TextStyle(fontSize: 11, color: T.muted(context))),
            ],
          ],
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  const StatusBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: T.muted(context),
                letterSpacing: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  const FieldRow({super.key, required this.label, required this.value, this.valueColor, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: T.panel(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.line(context)),
        ),
        child: Row(
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(fontSize: 10.5, color: T.muted(context), letterSpacing: 1.1),
            ),
            const SizedBox(width: 12),
            // Expanded + ellipsis: su un telefono stretto, con il testo grande,
            // un valore lungo (coordinate, nomi di filtri) usciva dalla riga.
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: valueColor ?? T.text(context),
                      fontWeight: FontWeight.w500)),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
      ),
    );
  }
}

class ChipToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const ChipToggle({super.key, required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = T.accent(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : T.panel(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent.withValues(alpha: 0.5) : T.line(context)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? accent : T.muted(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  final bool small;
  const PrimaryButton({super.key, required this.label, this.icon, this.onPressed, this.color, this.small = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: small ? 38 : 46,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? T.accent(context),
          foregroundColor: Colors.black,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
            Text(label, style: TextStyle(fontSize: small ? 11.5 : 13, fontWeight: FontWeight.w700, letterSpacing: .4)),
          ],
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool small;
  final bool danger;
  const GhostButton({super.key, required this.label, this.icon, this.onPressed, this.small = false, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? T.err(context) : T.text(context);
    return SizedBox(
      height: small ? 38 : 46,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(foregroundColor: color),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 8)],
            Text(label, style: TextStyle(fontSize: small ? 11.5 : 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class TargetCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<MapEntry<String, String>> rows;
  const TargetCard({super.key, required this.title, required this.subtitle, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF16202E), const Color(0xFF0E1620)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: T.muted(context), fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Prima: 2 colonne fisse con proporzione 4:1, che con il testo grande
          // tagliava i valori. Ora 2 colonne su telefono, fino a 4 su schermo
          // largo, e l'altezza la decide il testo.
          AdaptiveGrid(
            minTileWidth: 150,
            maxColumns: 4,
            spacing: 8,
            equalHeight: false,
            children: [
              for (final r in rows)
                Row(
                  children: [
                    Text('${r.key}  ', style: TextStyle(color: T.muted(context), fontSize: 11)),
                    Flexible(
                      child: Text(r.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: T.text(context),
                            fontWeight: FontWeight.w500,
                          )),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class LiveDot extends StatefulWidget {
  final Color color;
  const LiveDot({super.key, this.color = const Color(0xFF3ED598)});
  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (c, _) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.4 + 0.6 * _ctrl.value),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5 * _ctrl.value), blurRadius: 6)],
        ),
      ),
    );
  }
}

void showSnack(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? T.err(c) : null,
    duration: const Duration(seconds: 2),
  ));
}
