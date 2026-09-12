import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/date_utils.dart' as du;

/// 日期选择条：← / → 切日、星期显示、「今天」快捷按钮。
///
/// 移植自 sales-tracker 的 DateSelector.tsx，默认今天。
class DateSelector extends StatelessWidget {
  const DateSelector({
    super.key,
    required this.dateKey,
    required this.onChanged,
  });

  final String dateKey; // 'YYYY-MM-DD'
  final ValueChanged<String> onChanged;

  bool get _isToday => dateKey == du.todayKey();

  void _shift(int days) {
    final d = du.parseDateKey(dateKey).add(Duration(days: days));
    onChanged(du.dateKey(d));
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: du.parseDateKey(dateKey),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) onChanged(du.dateKey(picked));
  }

  @override
  Widget build(BuildContext context) {
    final d = du.parseDateKey(dateKey);
    return Container(
      decoration: AppTheme.cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: '前一天',
            icon: const Icon(Icons.chevron_left, size: 28),
            onPressed: () => _shift(-1),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              onTap: () => _pick(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      du.dayLabel(dateKey),
                      style: const TextStyle(
                        fontSize: AppTheme.fontSectionTitle,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${du.weekdayLabel(d)}${dateKey == du.todayKey() ? ' · 今天' : ''} · 点击选择日期',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_isToday)
            TextButton(
              onPressed: () => onChanged(du.todayKey()),
              child: const Text('今天', style: TextStyle(fontSize: 15)),
            ),
          IconButton(
            tooltip: '后一天',
            icon: const Icon(Icons.chevron_right, size: 28),
            onPressed: () => _shift(1),
          ),
        ],
      ),
    );
  }
}
