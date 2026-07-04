import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

/// Gradient app bar shared by the Stock module screens (amber → orange),
/// matching the other admin masters.
PreferredSizeWidget stockGradientAppBar(String title, {List<Widget>? actions}) {
  return AppBar(
    title: Text(
      title,
      style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Colors.white),
    ),
    centerTitle: true,
    elevation: 0,
    iconTheme: const IconThemeData(color: Colors.white),
    actions: actions,
    flexibleSpace: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryAmber, AppColors.primaryOrange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    ),
  );
}
