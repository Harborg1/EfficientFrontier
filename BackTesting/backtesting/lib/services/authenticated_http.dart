import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// HTTP helpers that authenticate requests with the current Firebase user.
class AuthenticatedHttp {
  AuthenticatedHttp._();

  static Future<Map<String, String>> _headers({
    required bool forceRefresh,
    bool json = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to use the portfolio API.');
    }

    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) {
      throw StateError('Could not obtain a Firebase authentication token.');
    }

    return {
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(Uri url) async {
    var response = await http.get(
      url,
      headers: await _headers(forceRefresh: false),
    );

    if (response.statusCode == 401) {
      response = await http.get(
        url,
        headers: await _headers(forceRefresh: true),
      );
    }
    return response;
  }

  static Future<http.Response> post(
    Uri url, {
    Object? body,
  }) async {
    var response = await http.post(
      url,
      headers: await _headers(forceRefresh: false, json: true),
      body: body,
    );

    if (response.statusCode == 401) {
      response = await http.post(
        url,
        headers: await _headers(forceRefresh: true, json: true),
        body: body,
      );
    }
    return response;
  }
}
