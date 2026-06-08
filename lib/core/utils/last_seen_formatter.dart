String formatLastSeen(String? isoDate) {
  if (isoDate == null || isoDate.trim().isEmpty) {
    return 'offline';
  }

  final parsedDate = DateTime.tryParse(isoDate);
  if (parsedDate == null) {
    return 'offline';
  }

  final date = parsedDate.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(date.year, date.month, date.day);
  final difference = today.difference(messageDay).inDays;
  final time = _formatTime(date);

  if (difference == 0) {
    return 'last seen $time';
  }
  if (difference == 1) {
    return 'last seen yesterday $time';
  }

  return 'last seen ${date.day.toString().padLeft(2, '0')} '
      '${_months[date.month - 1]}, $time';
}

String _formatTime(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
