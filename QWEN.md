# CafePOS - Flutter POS Application

## Project Overview

CafePOS is a **Point-of-Sale (POS) application for cafes and restaurants**, built with **Flutter** and backed by **Supabase**. It provides a modern, responsive interface for managing orders, tables, and billing across both mobile and tablet devices.

### Key Features
- **Multi-style POS screens**: Modern, Classic, and Quick Bill layouts
- **Table management**: Track table sessions for dine-in orders
- **Billing system**: Support for discounts, taxes (GST), multiple payment modes
- **Kitchen Order Tickets (KOT)**: Print and track kitchen orders
- **Role-based access control**: Admin, Manager, Cashier, Waiter roles with granular permissions
- **User preferences**: Theme customization (dark mode, UI layout, colors)
- **Multi-company isolation**: Row-level security in Supabase ensures data separation

### Architecture
The project follows a **feature-first** structure with **Riverpod** for state management:

```
lib/
├── core/                 # Shared utilities, services, constants, theme, widgets
│   ├── constants/
│   ├── services/         # Supabase initialization and API calls
│   ├── theme/            # App theming (light/dark, color palettes)
│   └── widgets/          # Reusable UI components
├── features/             # Feature modules
│   ├── auth/             # Authentication (login screen)
│   ├── orders/           # Table management screens
│   ├── pos/              # POS screens (modern, classic, quick bill)
│   └── reports/          # Bill history and reporting
├── models/               # Data models (models.dart)
├── providers/            # Riverpod providers (providers.dart)
├── home_shell.dart       # Main app shell (auth routing, navigation)
└── main.dart             # Entry point
```

### Tech Stack
| Category        | Technology                         |
|-----------------|------------------------------------|
| Framework       | Flutter (Dart)                     |
| State Mgmt      | Flutter Riverpod v3+               |
| Backend         | Supabase (PostgreSQL + Auth)       |
| Routing         | GoRouter                           |
| PDF/Printing    | pdf, printing                      |
| Styling         | Google Fonts, flutter_animate      |
| Code Generation | freezed, json_serializable         |

---

## Building and Running

### Prerequisites
- **Flutter SDK** >= 3.9.2
- **Dart SDK** >= 3.9.2
- A Supabase project (schema and seed SQL files provided)

### Setup

1. **Install dependencies:**
   ```bash
   flutter pub get
   ```

2. **Configure Supabase:**
   - Apply `supabase_schema_v2.sql` to your Supabase project
   - Run `supabase_seed_v2.sql` to populate initial data
   - Default credentials: `admin@cafe.com` / `admin123`

3. **Run the app:**
   ```bash
   flutter run
   ```

4. **Build for release:**
   ```bash
   flutter build apk          # Android
   flutter build ios          # iOS
   flutter build web          # Web
   ```

### Useful Commands
```bash
flutter analyze        # Static analysis
flutter test           # Run tests
flutter pub get        # Install dependencies
flutter pub upgrade    # Upgrade dependencies
```

---

## Database Schema

The database is defined in `supabase_schema_v2.sql` and includes:

| Table                  | Purpose                              |
|------------------------|--------------------------------------|
| `COMPANY_MASTER`       | Cafe/company configuration           |
| `COMPANY_HSN`          | GST tax rates                        |
| `COMPANY_PRINT_CONFIG` | Receipt printing settings            |
| `USER_MASTER`          | Staff profiles (linked to auth.users)|
| `USER_PREFERENCE`      | Per-user UI preferences              |
| `USER_PERMISSION`      | Per-user feature permissions         |
| `TABLE_MASTER`         | Restaurant tables                    |
| `TABLE_SESSION`        | Active dine-in sessions              |
| `ITEM_GROUP`           | Menu categories                      |
| `ITEM_MASTER`          | Menu items                           |
| `ITEM_VARIANT`         | Item size/options (e.g., S/M/L)     |
| `BILL_MASTER`          | Invoice headers                      |
| `BILL_ITEM`            | Line items per bill                  |
| `KOT_MASTER`           | Kitchen order tickets                |
| `KOT_ITEM`             | Items per kitchen ticket             |

Row Level Security (RLS) policies enforce **company-level data isolation**.

---

## Development Conventions

- **State Management**: Uses Flutter Riverpod with providers centralized in `lib/providers/providers.dart`
- **Feature-first organization**: Each feature (auth, pos, orders, reports) is self-contained under `lib/features/`
- **Linting**: Follows `flutter_lints` with custom rules in `analysis_options.yaml`
- **Code Generation**: Uses `freezed` for immutable data classes and `json_serializable` for JSON parsing (run `dart run build_runner build` to regenerate)
- **Responsive Design**: Adapts layout for mobile (bottom navigation) vs tablet (navigation rail)
- **Theming**: Supports light/dark modes with customizable UI themes (Modern, Classic, Quick Bill)

---

## Key Files

| File                          | Description                                      |
|-------------------------------|--------------------------------------------------|
| `lib/main.dart`               | Entry point, initializes Supabase and Riverpod   |
| `lib/home_shell.dart`         | Auth state routing and main navigation shell     |
| `pubspec.yaml`                | Dependencies and Flutter configuration           |
| `supabase_schema_v2.sql`      | Full database schema with RLS policies           |
| `supabase_seed_v2.sql`        | Sample data for testing                          |
| `lib/core/services/supabase_service.dart` | Supabase client initialization       |
| `lib/core/theme/app_theme.dart` | Light and dark theme definitions              |

---

## Notes

- **API keys** are stored in `api_keys.json` — do **not** commit this file to version control
- The project uses **UUIDs** for all primary keys
- Default company seed: "Gourmet Coffee House" with sample menu items and tables
- Supports GST billing (CGST/SGST/IGST) with HSN code tracking
