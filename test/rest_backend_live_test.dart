// Drives the REAL RestBackend implementation against the locally running dev
// Node API (see backend/scripts/dev-mysql.mjs + `npm run dev`), exercising the
// exact HTTP calls the Flutter app will make — not a mock. Skipped unless
// API_BASE_URL is set, so it never runs in a normal `flutter test` pass.
//
// Run with:
//   flutter test test/rest_backend_live_test.dart --dart-define=API_BASE_URL=http://127.0.0.1:3099 --dart-define=USE_SUPABASE=false
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:cafe/core/backend/app_config.dart';
import 'package:cafe/core/backend/rest/rest_backend.dart';
import 'package:cafe/core/utils/api_helper.dart';
import 'package:cafe/models/models.dart';

/// Reads a just-created registration's OTP straight from the test MySQL via a
/// throwaway `node` one-liner — the same, simplest approach
/// `backend/scripts/smoke.mjs` uses, kept out of `RestBackend` itself (no
/// test-only backdoor in production code). Requires `DB_PORT` in the
/// environment (the embedded MySQL's port — see backend/dev-mysql.json).
Future<String> readOtpForTest(String registrationId) async {
  final dbPort = Platform.environment['DB_PORT'];
  if (dbPort == null) {
    throw StateError(
      'Set DB_PORT (see backend/dev-mysql.json) to run this test.',
    );
  }
  final script =
      '''
    const mysql = require('mysql2/promise');
    (async () => {
      const c = await mysql.createConnection({ host: '127.0.0.1', port: $dbPort, user: 'root', database: 'cafe' });
      const [rows] = await c.query('SELECT otp_code FROM company_registration WHERE id = ?', ['$registrationId']);
      process.stdout.write(rows[0].otp_code);
      await c.end();
    })();
  ''';
  final result = await Process.run('node', [
    '-e',
    script,
  ], workingDirectory: 'backend');
  if (result.exitCode != 0)
    throw StateError('OTP lookup failed: ${result.stderr}');
  return (result.stdout as String).trim();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // TestWidgetsFlutterBinding installs an HttpOverrides that makes every
  // HttpClient return a canned 400 with no real I/O — correct default for
  // hermetic unit tests, but this file's entire point is a real network call
  // to the locally running dev API. Restoring the real HttpClient is the
  // documented way to opt a specific test file out of that sandboxing.
  HttpOverrides.global = null;

  // flutter_secure_storage's platform channel doesn't exist in the test
  // harness — back it with a simple in-memory map so TokenStore works exactly
  // as it does on a real device, without touching TokenStore's production code.
  final fakeSecureStore = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'write':
            fakeSecureStore[call.arguments['key']] = call.arguments['value'];
            return null;
          case 'read':
            return fakeSecureStore[call.arguments['key']];
          case 'delete':
            fakeSecureStore.remove(call.arguments['key']);
            return null;
          default:
            return null;
        }
      });

  test(
    'RestBackend end-to-end against the live dev API',
    () async {
      if (AppConfig.apiBaseUrl.isEmpty) {
        // ignore: avoid_print
        print(
          'SKIPPED: pass --dart-define=API_BASE_URL=http://127.0.0.1:3099 to run this test.',
        );
        return;
      }
      try {
        await _run();
      } on ApiException catch (e) {
        fail('ApiException(${e.type}, code=${e.code}): ${e.message}');
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<void> _run() async {
  // Constructed inside the test's zone: RestBackend -> ApiClient.instance
  // eagerly builds an http.Client(), and flutter_test's HTTP mock override
  // requires that to happen inside a running test's zone, not at main()'s
  // top level (a "no current invoker" error otherwise).
  final backend = RestBackend();
  final rand = DateTime.now().microsecondsSinceEpoch.toString();

  // ---- registration -> OTP -> first admin -> login
  final reg = await backend.requestCompanyRegistration(
    company: {'company_code': 'DRT$rand', 'company_name': 'Dart Test Cafe'},
    owner: {'owner_name': 'Owner'},
  );
  expect(reg['registration_id'], isNotNull);
  expect(reg['company_id'], isNotNull);
  final companyId = reg['company_id'] as String;
  final registrationId = reg['registration_id'] as String;

  // Read the OTP the same way scripts/smoke.mjs does: this is our own
  // just-created row, not a security bypass.
  final otp = await readOtpForTest(registrationId);

  final verify = await backend.verifyCompanyRegistrationOtp(
    registrationId: registrationId,
    code: otp,
  );
  expect(verify['ok'], true, reason: verify.toString());

  final username = 'dartadmin_$rand';
  await backend.upsertUserWithPermissions(
    userData: {
      'id': 'ignored-by-server',
      'company_id': companyId,
      'user_name': 'Dart Admin',
      'employee_code': 'DA$rand',
      'username': username,
      'user_role': 'admin',
      'password': 'DartSecret123!',
    },
    permissionData: UserPermission.all('ignored').toJson(),
    isNew: true,
  );

  final profile = await backend.signInWithUserMaster(
    input: username,
    password: 'DartSecret123!',
  );
  expect(profile['company_id'], companyId);
  expect(profile.containsKey('password'), isFalse);
  expect(profile.containsKey('password_hash'), isFalse);

  // ---- exercise a representative core-path slice through the SAME
  // RestBackend methods the app calls (Item/CafeTable/Bill/KotMaster models
  // parse the responses to prove the JSON shapes really match).
  final groupId = const Uuid().v4();
  await backend.saveItemGroup({
    'id': groupId,
    'item_code': 'D1',
    'item_name': 'Dart Item',
    'base_rate': 10,
  });
  final groups = await backend.getItemGroups(companyId);
  final parsedItems = groups.map((g) => Item.fromJson(g)).toList();
  expect(parsedItems.any((i) => i.id == groupId), isTrue);

  await backend.createTable(
    companyId: companyId,
    tableNumber: 'DT1',
    seatingCapacity: 2,
  );
  final tables = await backend.getTables(companyId);
  final parsedTables = tables.map((t) => CafeTable.fromJson(t)).toList();
  expect(parsedTables, isNotEmpty);

  final bills = await backend.getBills(companyId);
  bills.map((b) => Bill.fromJson(b)).toList(); // must not throw

  final kots = await backend.getActiveKots(companyId);
  kots.map((k) => KotMaster.fromJson(k)).toList(); // must not throw

  await backend.signOut();
}
