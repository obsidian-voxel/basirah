import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/blur_engine.dart';
import '../services/settings_store.dart';
import 'blockp_theme.dart';
import 'blockp_icons.dart';

/// Accountability partner: a trusted person's details and a local log of what
/// the app would report to them.
///
/// There is no messaging backend and no network permission, so nothing is ever
/// sent. The log can be copied by hand — the screen says that plainly instead
/// of claiming a delivered alert.
class AccountabilityScreen extends StatelessWidget {
  const AccountabilityScreen({super.key});

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editPartner(BuildContext context) async {
    final partner = blurEngine.settings.partner;
    final name = TextEditingController(text: partner.name);
    final email = TextEditingController(text: partner.email);
    final saved = await showBpDialog<bool>(
      context: context,
      title: 'Accountability partner',
      showActions: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: email,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'Email or phone'),
          ),
          const SizedBox(height: 12),
          Text(
            'Stored on this device only. Basirah has no server to send it '
            'to.',
            style: context.small,
          ),
          const SizedBox(height: 16),
          BpButton(
            label: 'Save',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (saved != true) {
      name.dispose();
      email.dispose();
      return;
    }
    await blurEngine.settings.setPartner(
      PartnerContact(name: name.text.trim(), email: email.text.trim()),
    );
    name.dispose();
    email.dispose();
    if (!context.mounted) return;
    blurEngine.refreshStatus();
  }

  Future<void> _recordTest(BuildContext context) async {
    final status = blurEngine.status;
    final partner = blurEngine.settings.partner;
    final target = partner.isEmpty ? 'no partner set' : partner.displayName;
    await blurEngine.addAlert(
      'Test entry · protection ${status.isActive ? 'active' : 'inactive'} · '
      'today ${blurEngine.todayCount} block(s) · recipient $target',
    );
    if (!context.mounted) return;
    _snack(context, 'Test entry recorded');
  }

  Future<void> _copyLog(BuildContext context) async {
    final log = blurEngine.settings.alertLog;
    final text = log.isEmpty
        ? 'Basirah: no accountability entries recorded.'
        : 'Basirah accountability log\n'
            '${log.map((e) => '${e.timeLabel}  ${e.message}').join('\n')}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    _snack(context, 'Log copied to the clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.bp;
    return Scaffold(
      backgroundColor: bp.canvas,
      body: DecoratedBox(
        decoration: context.bpCanvas,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: blurEngine,
            builder: (context, _) {
              final partner = blurEngine.settings.partner;
              final alerts = blurEngine.settings.alerts;
              final log = blurEngine.settings.alertLog;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(Icons.arrow_back, color: bp.ink),
                        ),
                        Expanded(
                          child: Text(
                            'Accountability Partner',
                            style: context.title.copyWith(fontSize: 21),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    BpCard(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              BpAbstractIcon(
                                BpAbstractIcon.bond,
                                size: 26,
                                color: bp.ink,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      partner.displayName,
                                      style: context.rowTitle.copyWith(
                                        fontSize: 18,
                                      ),
                                    ),
                                    Text(
                                      partner.email.isEmpty
                                          ? 'Add a trusted person'
                                          : partner.email,
                                      style: context.body,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.edit_outlined,
                                size: 22,
                                color: bp.muted,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          BpButton(
                            label: partner.isEmpty
                                ? 'Add a partner'
                                : 'Edit partner',
                            onPressed: () => _editPartner(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    BpSectionCard(
                      icon: Icons.notifications_none,
                      title: 'What is recorded',
                      children: [
                        BpRow.withIcon(
                          Icons.visibility_off_outlined,
                          title: 'Explicit content detected',
                          description: 'A blur happened',
                          trailing: BpSwitch(
                            value: alerts.explicitContent,
                            onChanged: (value) => blurEngine.setAlerts(
                              alerts.copyWith(explicitContent: value),
                            ),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.block,
                          title: 'Bypass attempts',
                          description: 'A blocked app or site was opened',
                          trailing: BpSwitch(
                            value: alerts.bypassAttempts,
                            onChanged: (value) => blurEngine.setAlerts(
                              alerts.copyWith(bypassAttempts: value),
                            ),
                          ),
                        ),
                        BpRow.withIcon(
                          Icons.power_settings_new,
                          title: 'Protection disabled',
                          description: 'Protection was switched off',
                          trailing: BpSwitch(
                            value: alerts.protectionDisabled,
                            onChanged: (value) => blurEngine.setAlerts(
                              alerts.copyWith(protectionDisabled: value),
                            ),
                          ),
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    BpCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Local log',
                                    style: context.title.copyWith(fontSize: 19),
                                  ),
                                ),
                                Text(
                                  '${log.length}',
                                  style: context.title.copyWith(fontSize: 19),
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: bp.divider,
                            indent: 18,
                            endIndent: 18,
                          ),
                          if (log.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 20, 18, 20),
                              child: Text(
                                'Nothing recorded yet. Use the button below to '
                                'record a test entry.',
                                style: context.body,
                              ),
                            )
                          else
                            for (var i = 0; i < log.length && i < 20; i++)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(18, 12, 18, 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 7,
                                      color: bp.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            log[i].message,
                                            style: context.body.copyWith(
                                              color: bp.ink,
                                            ),
                                          ),
                                          Text(
                                            log[i].timeLabel,
                                            style: context.small,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                BpButton(
                                  label: 'Record test entry',
                                  onPressed: () => _recordTest(context),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: BpOutlineButton(
                                        label: 'Copy log',
                                        onPressed: () => _copyLog(context),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: BpOutlineButton(
                                        label: 'Clear',
                                        onPressed: log.isEmpty
                                            ? null
                                            : () => blurEngine.clearAlertLog(),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Alerts are a local record, not a message. Android gives '
                      'no offline app a way to deliver them, so copy the log '
                      'and share it yourself.',
                      textAlign: TextAlign.center,
                      style: context.small,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
