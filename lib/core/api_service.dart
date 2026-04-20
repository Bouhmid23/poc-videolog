import 'dart:convert';
import 'package:http/http.dart' as http;
class ApiService {
  static const String localURL = "http://192.168.1.7:7880";
  static const String remoteURL = "https://livekit.opkodelabs.com";
  static const String baseUrl = "$localURL/api";
  static const String tokenEndpoint = "livekit/token";

  static Future<String> getToken(String username, String room) async {
    final response = await http.post(
      Uri.parse("$remoteURL/$tokenEndpoint"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "username": username,
        "room": room,
      }),
    );

    final data = jsonDecode(response.body);
    return data["token"];
  }
}