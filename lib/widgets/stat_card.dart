import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 月度统计四宫格小卡片。
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.subLabel,
    this.color = AppTheme.primary,
  });

  final String label;
  final String value;
  final String? subLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: AppTheme.fontCaption,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (subLabel != null) ...[
            const SizedBox(height: 2),
            Text(subLabel!,
                style: const TextStyle(
                    fontSize: AppTheme.fontCaption,
                    color: AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }
}
