import 'package:flutter/material.dart';

import 'mobile_design.dart';

String accountInitials(String? name, String? email) {
  final value = name?.trim().isNotEmpty == true
      ? name!.trim()
      : email?.split('@').first ?? '';
  final parts = value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'T';
  return (parts.length > 1
          ? '${parts.first.characters.first}${parts.last.characters.first}'
          : parts.first.characters.take(2).toString())
      .toUpperCase();
}

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.initials, this.size = 32});
  final String initials;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff8c5cf5), Color(0xff2e6df0)],
      ),
    ),
    child: Text(
      initials,
      style: TextStyle(
        color: Colors.white,
        fontSize: size >= 50 ? 19 : 12.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class AccountPlanBadge extends StatelessWidget {
  const AccountPlanBadge({super.key, required this.plan, required this.paid});
  final String plan;
  final bool paid;
  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: paid
            ? (p.dark ? const Color(0xff15263e) : const Color(0xffe6eefd))
            : p.hover,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        plan,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: paid
              ? (p.dark ? const Color(0xff8ebdff) : const Color(0xff1b57d6))
              : p.secondary,
        ),
      ),
    );
  }
}
