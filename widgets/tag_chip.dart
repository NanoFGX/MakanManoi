import 'package:flutter/material.dart';
import '../core/constants.dart';

enum ChipTone { neutral, good, warn, bad }

class TagChip extends StatelessWidget {
  final String text;
  final ChipTone tone;

  const TagChip({super.key, required this.text, this.tone = ChipTone.neutral});

  @override
  Widget build(BuildContext context) {
    Color bg = AppColors.chip;
    Color fg = AppColors.text;

    switch (tone) {
      case ChipTone.good:
        bg = AppColors.goodBg;
        fg = AppColors.goodFg;
        break;
      case ChipTone.warn:
        bg = AppColors.warnBg;
        fg = AppColors.warnFg;
        break;
      case ChipTone.bad:
        bg = AppColors.badBg;
        fg = AppColors.badFg;
        break;
      case ChipTone.neutral:
        bg = AppColors.chip;
        fg = AppColors.text;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}