import 'package:dio/dio.dart';

import '../../features/chat/models/conversation_summary.dart';
import 'api_client.dart';

class ConversationsApi {
  final ApiClient _apiClient = ApiClient();

  Future<List<ConversationSummary>> getSummary() async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        '/api/conversations/summary',
      );
      final data = response.data;
      if (data is! List) {
        throw const ConversationsApiException(
          'Invalid conversation summary response',
        );
      }

      return data
          .map(
            (item) => ConversationSummary.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (error) {
      final responseData = error.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        throw ConversationsApiException(responseData['message'].toString());
      }
      throw ConversationsApiException(
        error.message ?? 'Unable to load conversation summaries',
      );
    }
  }
}

class ConversationsApiException implements Exception {
  const ConversationsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
