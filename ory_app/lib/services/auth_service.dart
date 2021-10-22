import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ory_app/exceptions.dart';
import 'package:ory_app/storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthService {
  final kratosURL = dotenv.env['KRATOS_API'];
  final backendURL = dotenv.env['BACKEND'];

  Future<String> intiateRegistrationFlow() async {
    var response =
        await http.get(Uri.parse('$kratosURL/self-service/registration/api'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data["id"]; //return registration flow id
    } else {
      throw Exception();
    }
  }

  Future<String> initiateLoginFlow() async {
    var response = await http.get(
        Uri.parse('$kratosURL/self-service/login/api?refresh=true'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data["id"]; //return login flow id
    } else {
      throw Exception();
    }
  }

  Future<String> signIn(String flowId, String email, String password) async {
    var response = await http.post(
        Uri.parse('$kratosURL/self-service/login?flow=$flowId'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{
          "method": "password",
          "password": password,
          "password_identifier": email
        }));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final String sessionToken = data['session_token'];
      return sessionToken;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      final errors = checkForErrors(data);

      throw InvalidCredentialsException(errors);
    } else {
      throw Exception();
    }
  }

  Future<String> signUp(String flowId, String email, String password) async {
    final response = await http.post(
        Uri.parse("$kratosURL/self-service/registration?flow=$flowId"),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{
          "method": "password",
          "password": password,
          "traits.email": email
        }));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final String sessionToken = data["session_token"];
      return sessionToken;
    } else if (response.statusCode == 400) {
      final data = json.decode(response.body);

      final errors = checkForErrors(data);

      throw InvalidCredentialsException(errors);
    } else {
      throw Exception();
    }
  }

  Future<Map<String, dynamic>> getCurrentSession(String token) async {
    final response = await http.get(
      Uri.parse("$backendURL/whoami"),
      headers: <String, String>{
        'Accept': 'application/json',
        'Session_token': token
      },
    );

    if (response.statusCode == 200) {
      final userData = jsonDecode(response.body);
      return Map<String, dynamic>.from(userData["oryUser"]);
    } else if(response.statusCode == 401) {
      throw UnauthorizedException();
    } else {
      throw Exception();
    }
  }

  Future<void> signOut() async {
    final SecureStorage storage = SecureStorage();
    final String? sessionToken = await storage.getToken();
    if (sessionToken != null) {
      final response = await http.delete(
          Uri.parse(
              'https://blissful-chebyshev-drdmsyuc3t.projects.oryapis.com/api/kratos/public/self-service/logout/api'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{"session_token": sessionToken}));
      if (response.statusCode == 204) { //revokation successful
        await storage.deleteToken();
      } else {
        throw Exception();
      }
    }
  }

  Map<String, String> checkForErrors(Map<String, dynamic> response) {
    final ui = Map<String, dynamic>.from(response["ui"]);
    final list = ui["nodes"];
    final generalErrors = ui["messages"];

    Map errors = <String, String>{};
    for (var i = 0; i < list.length; i++) {
      //check if there are any input errors
      final entry = Map<String, dynamic>.from(list[i]);
      if ((entry["messages"] as List).isNotEmpty) {
        final String name = entry["attributes"]["name"];
        final message = entry["messages"][0] as Map<String, dynamic>;
        errors.putIfAbsent(name, () => message["text"] as String);
      }
    }

    if (generalErrors != null) {
      //check if there is a general error
      final message = (generalErrors as List)[0] as Map<String, dynamic>;
      errors.putIfAbsent("general", () => message["text"] as String);
    }

    return errors as Map<String, String>;
  }
}