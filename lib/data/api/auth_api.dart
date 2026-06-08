import 'package:dio/dio.dart';

import 'api_client.dart';

class AuthApi {
  AuthApi(this.apiClient);

  final ApiClient apiClient;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await apiClient.dio.post<dynamic>(
        '/api/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      throw AuthApiException(_errorMessage(error));
    }
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    String? phone,
    required String password,
  }) async {
    try {
      final data = <String, dynamic>{
        'name': name,
        'email': email,
        'password': password,
      };
      if (phone != null && phone.isNotEmpty) {
        data['phone'] = phone;
      }

      final response = await apiClient.dio.post<dynamic>(
        '/api/auth/register',
        data: data,
      );

      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      throw AuthApiException(_errorMessage(error));
    }
  }

  String _errorMessage(DioException error) {
    final responseData = error.response?.data;
    if (responseData is Map && responseData['message'] != null) {
      return responseData['message'].toString();
    }

    return error.message ?? 'Unable to connect to the server';
  }
}

class AuthApiException implements Exception {
  const AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
