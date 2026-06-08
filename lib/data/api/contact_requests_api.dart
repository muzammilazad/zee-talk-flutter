import 'package:dio/dio.dart';

import '../../features/contacts/models/contact_request.dart';
import '../../features/contacts/models/search_user.dart';
import 'api_client.dart';

class ContactRequestsApi {
  final ApiClient _apiClient = ApiClient();

  Future<List<SearchUser>> searchUsers(String query) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        '/api/users/search',
        queryParameters: {'q': query},
      );
      final data = response.data;
      if (data is! List) {
        throw const ContactRequestsApiException('Invalid search response');
      }

      return data
          .map(
            (item) => SearchUser.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw ContactRequestsApiException(_errorMessage(error));
    }
  }

  Future<void> sendRequest(String receiverId) async {
    try {
      await _apiClient.dio.post<dynamic>(
        '/api/contact-requests',
        data: {'receiverId': receiverId},
      );
    } on DioException catch (error) {
      throw ContactRequestsApiException(_errorMessage(error));
    }
  }

  Future<List<ContactRequest>> getIncomingRequests() async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        '/api/contact-requests',
      );
      final data = response.data;
      if (data is! List) {
        throw const ContactRequestsApiException(
          'Invalid contact requests response',
        );
      }

      return data
          .map(
            (item) => ContactRequest.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw ContactRequestsApiException(_errorMessage(error));
    }
  }

  Future<void> acceptRequest(String requestId) async {
    try {
      await _apiClient.dio.post<dynamic>(
        '/api/contact-requests/$requestId/accept',
      );
    } on DioException catch (error) {
      throw ContactRequestsApiException(_errorMessage(error));
    }
  }

  Future<void> rejectRequest(String requestId) async {
    try {
      await _apiClient.dio.post<dynamic>(
        '/api/contact-requests/$requestId/reject',
      );
    } on DioException catch (error) {
      throw ContactRequestsApiException(_errorMessage(error));
    }
  }

  String _errorMessage(DioException error) {
    final responseData = error.response?.data;
    if (responseData is Map && responseData['message'] != null) {
      return responseData['message'].toString();
    }
    return error.message ?? 'Unable to complete contact request';
  }
}

class ContactRequestsApiException implements Exception {
  const ContactRequestsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
