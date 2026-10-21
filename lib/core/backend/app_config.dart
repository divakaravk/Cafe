/// Compile-time switch between the two backends. Defaults to Supabase, so
/// every existing `flutter run` / `flutter build` keeps behaving exactly as
/// before. Flip it with:
///
///   flutter run --dart-define=USE_SUPABASE=false --dart-define=API_BASE_URL=http://10.0.2.2:3000
///
/// See docs/backend-migration/PLAN.md for the Node+MySQL side of this.
class AppConfig {
  AppConfig._();

  static const bool useSupabase = bool.fromEnvironment(
    'USE_SUPABASE',
    defaultValue: true,
  );

  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');
}
