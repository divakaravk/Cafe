import 'package:http/http.dart' as http;

/// Native/desktop default: refresh tokens live in `flutter_secure_storage`
/// and are sent as an explicit body field, so no cookie transport is needed.
http.Client createHttpClient() => http.Client();
