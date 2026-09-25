import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_data_table.dart';  // same folder

// ---- Runtime probes: what really happens on web with the app's current dart:io patterns? ----
Future<void> runProbes() async {
  // 1) the app's `_hasNetwork()` pattern (my_profile / table_master / user_master screens)
  try {
    final r = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 5));
    debugPrint('PROBE lookup: OK ${r.length} results');
  } catch (e) {
    debugPrint('PROBE lookup: THREW ${e.runtimeType}: $e');
  }
  // 2) the app's picked-image preview pattern: FileImage(File(xfile.path)) / Image.file(...)
  try {
    final img = Image.file(File('blob:http://localhost/abc'));
    debugPrint('PROBE Image.file: constructed ${img.runtimeType}');
  } catch (e) {
    debugPrint('PROBE Image.file: THREW ${e.runtimeType}: $e');
  }
  try {
    final p = FileImage(File('blob:http://localhost/abc'));
    debugPrint('PROBE FileImage: constructed ${p.runtimeType}');
  } catch (e) {
    debugPrint('PROBE FileImage: THREW ${e.runtimeType}: $e');
  }
  // 3) the app's my_profile extension logic: XFile.path on web is a blob: URL
  const blob = 'blob:http://localhost:8099/6f1c2d7e-1a2b-4c3d-8e9f-0a1b2c3d4e5f';
  debugPrint('PROBE ext from path.split(".").last -> "${blob.split('.').last.toLowerCase()}"  (name-based would be "png")');
}

class Bill {
  Bill(this.no, this.date, this.table, this.items, this.mode, this.status, this.total);
  final String no; final DateTime date; final String table; final int items; final String mode; final String status; final double total;
}

final _bills = List.generate(87, (i) => Bill(
  'COMP001/2026-27/${(195 - i).toString().padLeft(3, '0')}',
  DateTime(2026, 9, 19, 12, 0).subtract(Duration(minutes: 37 * i)),
  'T${(i % 9) + 1}', (i % 5) + 1, ['cash', 'upi', 'card'][i % 3], i % 17 == 0 ? 'cancelled' : 'paid', 120.0 + (i * 37 % 900),
));

Widget _statusChip(String s) {
  final ok = s == 'paid';
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: (ok ? Colors.green : Colors.red).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(s.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ok ? Colors.green.shade800 : Colors.red.shade800)),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (d) => debugPrint('PROBE FlutterError: ${d.exceptionAsString().split('\n').first}');
  runProbes();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFFF8A00), visualDensity: VisualDensity.compact),
    home: Scaffold(
      backgroundColor: const Color(0xFFFBF6F1),
      floatingActionButton: SizedBox(width: 48, height: 48, child: Image.file(File('blob:http://localhost:8099/abc'), errorBuilder: (c, e, st) { debugPrint('PROBE Image.file RENDER errorBuilder: $e'); return const Icon(Icons.broken_image); })),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440), // content never stretches past 1440
              child: AppDataTable<Bill>(
                title: 'Bills & History',
                rows: _bills,
                searchText: (b) => '${b.no} ${b.table} ${b.mode} ${b.status}',
                toolbar: [
                  FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.download, size: 18), label: const Text('Export CSV')),
                ],
                actions: [
                  AppRowAction<Bill>('View', Icons.visibility_outlined, (_) {}),
                  AppRowAction<Bill>('Print', Icons.print_outlined, (_) {}),
                  AppRowAction<Bill>('Cancel', Icons.block, (_) {}),
                ],
                onRowTap: (_) {},
                columns: [
                  AppColumn<Bill>(label: 'Bill No', value: (b) => b.no, size: ColumnSize.L),
                  AppColumn<Bill>(label: 'Date', value: (b) => b.date, cell: (b) => Text('${b.date.day}/${b.date.month}/${b.date.year}  ${b.date.hour.toString().padLeft(2, '0')}:${b.date.minute.toString().padLeft(2, '0')}'), size: ColumnSize.M, minWindow: WindowClass.medium),
                  AppColumn<Bill>(label: 'Table', value: (b) => b.table, size: ColumnSize.S),
                  AppColumn<Bill>(label: 'Items', value: (b) => b.items, numeric: true, size: ColumnSize.S, minWindow: WindowClass.expanded),
                  AppColumn<Bill>(label: 'Payment', value: (b) => b.mode, size: ColumnSize.S, minWindow: WindowClass.expanded),
                  AppColumn<Bill>(label: 'Status', value: (b) => b.status, cell: (b) => _statusChip(b.status), size: ColumnSize.S),
                  AppColumn<Bill>(label: 'Total (₹)', value: (b) => b.total, cell: (b) => Text(b.total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700)), numeric: true, size: ColumnSize.S),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ));
}
