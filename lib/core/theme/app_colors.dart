import 'package:flutter/material.dart';

/// Premium color palette for CafePOS
class AppColors {
  AppColors._();

  // Primary brand colors - warm coffee tones
  static const Color primaryBrown = Color(0xFF3E2723);
  static const Color primaryAmber = Color(0xFFFF8F00);
  static const Color primaryOrange = Color(0xFFE65100);

  // Accent
  static const Color accentGold = Color(0xFFFFAB00);
  static const Color accentTeal = Color(0xFF00897B);
  static const Color accentCoral = Color(0xFFFF6E40);

  // Surfaces - Dark theme
  static const Color darkBg = Color(0xFF0F0F14);
  static const Color darkSurface = Color(0xFF1A1A24);
  static const Color darkCard = Color(0xFF222233);
  static const Color darkElevated = Color(0xFF2A2A3E);
  static const Color darkBorder = Color(0xFF333350);

  // Surfaces - Light theme
  static const Color lightBg = Color(0xFFF8F6F3);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFF8F0);
  static const Color lightElevated = Color(0xFFFFF3E0);
  static const Color lightBorder = Color(0xFFE0D5C8);

  // Text
  static const Color textWhite = Color(0xFFF5F5F5);
  static const Color textWhiteMuted = Color(0xFFB0B0C0);
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color textDarkMuted = Color(0xFF6E6E73);

  // Status
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF007AFF);

  // Table statuses
  static const Color tableFree = Color(0xFF2E7D32);
  static const Color tableOccupied = Color(0xFFC62828);
  static const Color tableReserved = Color(0xFFE65100);
}
