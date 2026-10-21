# Prototype: `AppDataTable` + browser probes

Compiled and run against **Flutter 3.35.6 / Dart 3.9** (your SDK) with `data_table_2` **2.7.2**
(the newest release that resolves on it; 3.0.0 needs Flutter >= 3.47).

Run it (outside the app repo, so nothing here touches `pubspec.yaml`):

```bash
flutter create --platforms=web spike && cd spike
flutter pub add data_table_2            # resolves to 2.7.2 on Flutter 3.35.x
cp <repo>/docs/web-view/prototype/app_data_table.dart lib/
cp <repo>/docs/web-view/prototype/demo_and_probes_main.dart lib/main.dart
flutter run -d chrome                    # resize the window: table -> cards below 720 px
```

`demo_and_probes_main.dart` also logs `PROBE …` lines to the browser console that prove the web
blockers described in PLAN.md section 1.3 (open DevTools -> Console).
