import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Banner for alerts arriving from outside the app.
///
/// The bridge republishes on its state WebSocket what external programs send
/// it over UDP — astro_monitor reporting that KStars died, a weather script,
/// a script of one's own. On a phone those also become system notifications;
/// in a browser they cannot, because a page served over plain HTTP has no
/// secure context and the browser refuses the Notification API outright.
/// This banner is what remains, and in the field, with the tablet propped up
/// next to the mount, it is what one actually looks at.
///
/// It stays until dismissed: an alert that fades away on its own is an alert
/// missed by whoever was at the eyepiece.
class NotificationBanner extends StatelessWidget {
  /// Width of the coloured bar down the left edge. The tinted background
  /// alone is dim on a screen turned down for night vision, and at a glance
  /// the eye catches the solid bar first: it carries the level in full
  /// saturation, the same colour as the icon.
  static const double accentBarWidth = 6;

  const NotificationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final n = context.watch<AppState>().pendingNotification;
    if (n == null) return const SizedBox.shrink();

    final level = n['level']?.toString() ?? 'info';
    final color = switch (level) {
      'error' => T.err(context),
      'warning' => T.warn(context),
      _ => T.accent(context),
    };
    final icon = switch (level) {
      'error' => Icons.error_outline,
      'warning' => Icons.warning_amber_outlined,
      _ => Icons.notifications_active_outlined,
    };
    final title = n['title']?.toString() ?? '';
    final message = n['message']?.toString() ?? '';
    final source = n['source']?.toString() ?? '';

    return Material(
      color: color.withValues(alpha: 0.16),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: accentBarWidth)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(title,
                      style: TextStyle(
                          color: T.text(context),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                if (message.isNotEmpty)
                  Text(message,
                      style: TextStyle(color: T.text(context), fontSize: 12.5)),
                if (source.isNotEmpty)
                  Text(source,
                      style: TextStyle(color: T.muted(context), fontSize: 10.5)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Chiudi avviso'.tr(context),
            onPressed: () => context.read<AppState>().dismissNotification(),
          ),
        ]),
      ),
    );
  }
}

/// The alerts received so far, newest first.
///
/// Reachable from the banner's own history and from the drawer: a dismissed
/// alert must remain findable, or a message arriving while nobody was looking
/// is lost for good.
class NotificationHistorySheet extends StatelessWidget {
  const NotificationHistorySheet({super.key});

  static Future<void> show(BuildContext context) {
    context.read<AppState>().markNotificationsSeen();
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => const NotificationHistorySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<AppState>().notifications.reversed.toList();
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Nessun avviso ricevuto'.tr(context),
            style: TextStyle(color: T.muted(context))),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          itemCount: items.length,
          // The default divider is near-white on the dark themes, and on a
          // list read at night the separator should be felt, not seen.
          separatorBuilder: (_, __) => Divider(
            height: 1,
            thickness: 1,
            color: T.muted(context).withValues(alpha: 0.18),
          ),
          itemBuilder: (context, i) {
        final n = items[i];
        final level = n['level']?.toString() ?? 'info';
        final ts = (n['ts'] as num?)?.toDouble();
        final when = ts == null
            ? ''
            : DateTime.fromMillisecondsSinceEpoch((ts * 1000).round())
                .toLocal()
                .toString()
                .substring(11, 19);
        return ListTile(
          dense: true,
          leading: Icon(
            switch (level) {
              'error' => Icons.error_outline,
              'warning' => Icons.warning_amber_outlined,
              _ => Icons.notifications_none,
            },
            size: 18,
            color: switch (level) {
              'error' => T.err(context),
              'warning' => T.warn(context),
              _ => T.muted(context),
            },
          ),
          title: Text(
            [n['title'], n['message']]
                .where((s) => s != null && s.toString().isNotEmpty)
                .join(' — '),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            [when, n['source']?.toString() ?? '']
                .where((s) => s.isNotEmpty)
                .join(' · '),
            style: TextStyle(fontSize: 11, color: T.muted(context)),
          ),
        );
          },
        ),
      ),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text('Cancella tutti'.tr(context)),
            style: TextButton.styleFrom(foregroundColor: T.err(context)),
            onPressed: () => _confirmClear(context),
          ),
        ),
      ),
    ]);
  }

  Future<void> _confirmClear(BuildContext context) async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cancellare tutti gli avvisi?'.tr(dialogContext)),
        content: Text(
            'La cronaca della sessione andrà persa, su tutti i dispositivi.'
                .tr(dialogContext)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Annulla'.tr(dialogContext)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: T.err(dialogContext)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Cancella tutti'.tr(dialogContext)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await state.clearNotifications();
      if (context.mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'Errore: '.tr(context)}$e')),
        );
      }
    }
  }
}
