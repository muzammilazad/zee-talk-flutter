import 'package:dio/dio.dart';

import '../../features/users/models/contact_user.dart';
import 'api_client.dart';

class UsersApi {
  final ApiClient _apiClient = ApiClient();

  Future<List<ContactUser>> getContacts() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('/api/contacts');
      final data = response.data;

      if (data is! List) {
        throw const UsersApiException('Invalid contacts response');
      }

      return data
          .map(
            (item) => ContactUser.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (error) {
      final responseData = error.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw UsersApiException(responseData['message'].toString());
      }

      throw UsersApiException(
        error.message ?? 'Unable to load contacts',
      );
    }
  }
}

class UsersApiException implements Exception {
  const UsersApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
