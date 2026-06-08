import 'package:dio/dio.dart';

import '../../features/chat/models/chat_message.dart';
import 'api_client.dart';

class MessagesApi {
  final ApiClient _apiClient = ApiClient();

  Future<List<ChatMessage>> getTimeline(String userId) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        '/api/conversations/$userId/timeline',
      );
      final data = response.data;

      if (data is! List) {
        throw const MessagesApiException('Invalid timeline response');
      }

      return data
          .map(
            (item) => ChatMessage.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (error) {
      final responseData = error.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw MessagesApiException(responseData['message'].toString());
      }

      throw MessagesApiException(
        error.message ?? 'Unable to load messages',
      );
    }
  }
}

class MessagesApiException implements Exception {
  const MessagesApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
