/// The same subscription and current-period usage payloads used by macOS.
/// Missing data remains unknown; it must never look like a zero balance.
class AccountSummary {
  const AccountSummary({
    this.plan,
    this.paid = false,
    this.remaining,
    this.limit,
    this.unlimited = false,
    this.periodEnd,
  });

  final String? plan;
  final bool paid;
  final num? remaining, limit;
  final bool unlimited;
  final DateTime? periodEnd;

  factory AccountSummary.fromJson(
    Map<String, dynamic> billing,
    Map<String, dynamic> usage,
  ) {
    final subscription = billing['subscription'] is Map
        ? Map<String, dynamic>.from(billing['subscription'] as Map)
        : billing;
    final credits = usage['credits'] is Map
        ? Map<String, dynamic>.from(usage['credits'] as Map)
        : <String, dynamic>{};
    final code = (subscription['plan_code'] as String?)?.trim();
    final name = (subscription['plan_name'] as String?)?.trim();
    final visiblePlan =
        billing['billing_enabled'] == true ||
        subscription['billing_enabled'] == true ||
        subscription['paid'] == true;
    return AccountSummary(
      plan: !visiblePlan
          ? null
          : switch (code?.toLowerCase()) {
              'free' => 'Free',
              'pro' => 'Pro',
              _ =>
                name?.isNotEmpty == true
                    ? name
                    : code?.isNotEmpty == true
                    ? code
                    : null,
            },
      paid: subscription['paid'] == true,
      remaining: credits['remaining'] is num
          ? credits['remaining'] as num
          : null,
      limit: credits['limit'] is num ? credits['limit'] as num : null,
      unlimited: credits['unlimited'] == true,
      periodEnd: DateTime.tryParse(usage['period_end'] as String? ?? ''),
    );
  }

  bool get hasBalance => remaining != null && limit != null && limit! >= 0;
  double? get remainingFraction => hasBalance && limit! > 0
      ? (remaining! / limit!).clamp(0.0, 1.0).toDouble()
      : null;
}
