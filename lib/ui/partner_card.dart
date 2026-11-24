import 'package:flutter/material.dart';

import '../services/blur_engine.dart';
import '../services/settings_store.dart';
import 'blockp_icons.dart';
import 'theme.dart';
import 'widgets.dart';

class PartnerCard extends StatelessWidget {
  const PartnerCard({super.key});

  Future<void> _edit(BuildContext context) async {
    final current = blurEngine.settings.partner;
    final name = TextEditingController(text: current.name);
    final email = TextEditingController(text: current.email);
    final phone = TextEditingController(text: current.phone);

    final result = await showDialog<PartnerContact>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accountability partner'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 12),
              Text(
                'Stored only on this device. The app has no messaging backend, '
                'so nothing is sent automatically.',
                style: TextStyle(fontSize: 12, color: context.paletteMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const PartnerContact()),
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              PartnerContact(
                name: name.text.trim(),
                email: email.text.trim(),
                phone: phone.text.trim(),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    name.dispose();
    email.dispose();
    phone.dispose();

    if (result == null) return;
    await blurEngine.setPartner(result);
  }

  @override
  Widget build(BuildContext context) {
    final partner = blurEngine.settings.partner;
    final detail = [
      if (partner.email.isNotEmpty) partner.email,
      if (partner.phone.isNotEmpty) partner.phone,
    ].join('  •  ');

    return AppCard(
      color: context.palettePrimary.withValues(alpha: 0.06),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.palettePrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: BpAbstractIcon(
              BpAbstractIcon.bond,
              size: 26,
              color: context.palettePrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partner.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: context.paletteInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.isEmpty ? 'Add a trusted contact' : detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.paletteMuted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _edit(context),
            child: Text(partner.isEmpty ? 'Set partner' : 'Edit'),
          ),
        ],
      ),
    );
  }
}
