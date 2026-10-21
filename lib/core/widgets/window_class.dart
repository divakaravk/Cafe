import 'package:flutter/material.dart';

/// Material 3 window-size classes — the single source of truth for
/// responsive breakpoints across the app (mobile phone -> desktop web).
enum WindowClass { compact, medium, expanded, large }

extension WindowClassX on BuildContext {
  /// `MediaQuery.sizeOf` rebuilds only when the size actually changes.
  WindowClass get windowClass {
    final w = MediaQuery.sizeOf(this).width;
    if (w < 600) return WindowClass.compact;
    if (w < 840) return WindowClass.medium;
    if (w < 1200) return WindowClass.expanded;
    return WindowClass.large;
  }

  bool get isCompactWindow => windowClass == WindowClass.compact;

  /// Wide enough for a permanent side nav instead of a slide-out drawer.
  bool get isWideWindow => windowClass.index >= WindowClass.expanded.index;
}
