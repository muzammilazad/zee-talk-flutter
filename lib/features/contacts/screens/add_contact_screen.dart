import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/api/contact_requests_api.dart';
import '../models/search_user.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final ContactRequestsApi _api = ContactRequestsApi();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _sendingUserIds = {};
  List<SearchUser> _users = [];
  Timer? _debounce;
  String? _errorMessage;
  bool _isSearching = false;
  int _searchVersion = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final version = ++_searchVersion;

    if (query.isEmpty) {
      setState(() {
        _users = [];
        _errorMessage = null;
        _isSearching = false;
      });
      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _search(query, version),
    );
  }

  Future<void> _search(String query, int version) async {
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final users = await _api.searchUsers(query);
      if (!mounted || version != _searchVersion) {
        return;
      }
      setState(() => _users = users);
    } catch (error) {
      if (!mounted || version != _searchVersion) {
        return;
      }
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted && version == _searchVersion) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _sendRequest(SearchUser user) async {
    setState(() => _sendingUserIds.add(user.id));

    try {
      await _api.sendRequest(user.id);
      if (!mounted) {
        return;
      }

      setState(() {
        _users = _users
            .map(
              (item) => item.id == user.id
                  ? item.withRelationshipStatus('pending_sent')
                  : item,
            )
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact request sent')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingUserIds.remove(user.id));
      }
    }
  }

  String? _avatarUrl(SearchUser user) {
    final avatarUrl = user.avatarUrl?.trim();
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return null;
    }
    return Uri.parse(AppConfig.baseUrl).resolve(avatarUrl).toString();
  }

  String _initial(SearchUser user) {
    final name = user.name.trim();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  String _subtitle(SearchUser user) {
    final phone = user.phone?.trim();
    if (phone != null && phone.isNotEmpty) {
      return phone;
    }
    return user.email?.trim() ?? '';
  }

  Widget _buildAction(SearchUser user) {
    final status = user.relationshipStatus?.toLowerCase();
    final isSending = _sendingUserIds.contains(user.id);

    if (status == 'contact' || status == 'accepted') {
      return const _StatusButton(label: 'Added');
    }
    if (status == 'pending_sent') {
      return const _StatusButton(label: 'Pending');
    }
    if (status == 'pending_received') {
      return const _StatusButton(label: 'Respond in Requests');
    }

    return SizedBox(
      height: 38,
      child: ElevatedButton(
        onPressed: isSending ? null : () => _sendRequest(user),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: isSending
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Add'),
      ),
    );
  }

  Widget _buildBody() {
    if (_searchController.text.trim().isEmpty) {
      return const Center(
        child: Text(
          'Search users by name, email, or phone',
          style: TextStyle(color: AppColors.mutedText),
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.mutedText),
          ),
        ),
      );
    }

    if (_users.isEmpty) {
      return const Center(
        child: Text(
          'No users found',
          style: TextStyle(color: AppColors.mutedText),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = _users[index];
        final avatarUrl = _avatarUrl(user);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.homeBorder),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.mintAvatar,
                backgroundImage:
                    avatarUrl == null ? null : NetworkImage(avatarUrl),
                child: avatarUrl == null
                    ? Text(
                        _initial(user),
                        style: const TextStyle(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.darkText,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(user),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _buildAction(user),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Add Contact'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search name, email, or phone',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 36, maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.softButton,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.mutedText,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
