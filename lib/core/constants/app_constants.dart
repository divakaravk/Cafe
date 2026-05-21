/// App-wide constants
class AppConstants {
  AppConstants._();

  static const String appName = 'RasaBhojan';
  static const String appVersion = '1.0.0';

  // Supabase - Replace with your actual values
  static const String supabaseUrl = 'https://vsbjkytdqhzbtideebwy.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzYmpreXRkcWh6YnRpZGVlYnd5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNDQ1NjYsImV4cCI6MjA5MDYyMDU2Nn0.P8H59qIbCam_COS3SUR_RR6SuNjnKvXz1xrJ0yIG5LQ';

  // Payment modes
  static const String paymentCash = 'CASH';
  static const String paymentUpi = 'UPI';
  static const String paymentCard = 'CARD';

  // Order types
  static const String orderDineIn = 'DINE_IN';
  static const String orderTakeaway = 'TAKEAWAY';

  // Table statuses
  static const String tableFree = 'FREE';
  static const String tableOccupied = 'OCCUPIED';

  // UI themes
  static const String uiQuickBill = 'QUICK_BILL';
  static const String uiModern = 'MODERN';
  static const String uiClassic = 'CLASSIC';

  // Item group types
  static const String groupDirect = 'DIRECT';
  static const String groupGrouped = 'GROUPED';

  // Roles
  static const String roleAdmin = 'ADMIN';
  static const String roleManager = 'MANAGER';
  static const String roleCashier = 'CASHIER';
}
