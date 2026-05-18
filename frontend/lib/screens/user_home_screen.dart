import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/moderation_debug.dart';
import '../widgets/glass_container.dart';
import '../widgets/moderation_banner.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();

  bool _isLoading = false;
  bool _isPosting = false;
  List<dynamic> _comments = [];
  String? _error;
  String? _currentUsername;

  Uint8List? _pendingImageBytes;
  String? _pendingImageName;
  String? _pendingContentType;
  Map<String, dynamic>? _imageScanResult;
  bool _isScanningImage = false;

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final api = Provider.of<ApiService>(context, listen: false);
    final name = await api.getUsername();
    if (mounted) setState(() => _currentUsername = name);
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _loadComments({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final comments = await api.getComments();
      if (mounted) {
        setState(() => _comments = comments);
        _scrollToBottom(animated: false);
      }
    } on AuthException {
      return;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 88,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pendingImageBytes = bytes;
        _pendingImageName = file.name;
        _pendingContentType = _mimeFromName(file.name);
        _imageScanResult = null;
        _isScanningImage = false;
      });
      await _scanPendingImage();
    } catch (_) {
      _snack('Could not load image', isError: true);
    }
  }

  void _clearPendingImage() {
    setState(() {
      _pendingImageBytes = null;
      _pendingImageName = null;
      _pendingContentType = null;
      _imageScanResult = null;
    });
  }

  String _uniqueScanFilename(String name) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dot = name.lastIndexOf('.');
    if (dot > 0) {
      return '${name.substring(0, dot)}_$stamp${name.substring(dot)}';
    }
    return '${name}_$stamp.jpg';
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<bool> _scanPendingImage() async {
    if (_pendingImageBytes == null) return true;
    setState(() => _isScanningImage = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final scan = await api.analyzeVisionImage(
        _pendingImageBytes!,
        _uniqueScanFilename(_pendingImageName ?? 'upload.jpg'),
        _pendingContentType,
      );
      if (!mounted) return false;
      logVisionScan('image-scan', scan);
      final status = scan['status']?.toString() ?? '';
      setState(() => _imageScanResult = Map<String, dynamic>.from(scan));
      if (status == 'SAFE') {
        return true;
      }
      final msg = scan['message']?.toString() ??
          'This photo is not allowed.';
      _snack(msg, isError: true);
      return false;
    } catch (e) {
      if (mounted) {
        final msg = e is ApiException ? e.message : 'Image scan failed';
        _snack(msg, isError: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _isScanningImage = false);
    }
  }

  void _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty && _pendingImageBytes == null) return;

    setState(() => _isPosting = true);
    try {
      if (_pendingImageBytes != null) {
        final ok = await _scanPendingImage();
        if (!ok || !mounted) return;
      }

      if (!mounted) return;
      final api = Provider.of<ApiService>(context, listen: false);
      final result = await api.postComment(
        text,
        imageBytes: _pendingImageBytes,
        filename: _uniqueScanFilename(_pendingImageName ?? 'upload.jpg'),
        contentType: _pendingContentType,
      );

      _commentController.clear();
      _clearPendingImage();

      if (mounted) {
        final status = result['status']?.toString() ?? 'PENDING';
        final message = status == 'APPROVED'
            ? 'Posted!'
            : status == 'REJECTED'
                ? 'Not published — broke our rules'
                : 'Submitted';
        _snack(message, isError: status == 'REJECTED');
        await _loadComments(silent: true);
        _scrollToBottom();
      }
    } on AuthException {
      return;
    } on ApiException catch (e) {
      if (mounted) _snack(e.message, isError: true);
    } catch (_) {
      if (mounted) _snack('Failed to send', isError: true);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTheme.mono(size: 11, color: AppTheme.paperLight),
        ),
        backgroundColor: isError ? AppTheme.rust : AppTheme.ink,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
      ),
    );
  }

  void _logout() async {
    await Provider.of<ApiService>(context, listen: false).logout();
    if (mounted) Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: NexusBackground(
        child: SafeArea(
          child: Column(
            children: [
              _masthead(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.ink,
                          strokeWidth: 1.8,
                        ),
                      )
                    : _error != null
                        ? _errorState()
                        : _comments.isEmpty
                            ? _emptyState()
                            : _commentsList(),
              ),
              _composer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _masthead() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.paperLight,
        border: Border(bottom: BorderSide(color: AppTheme.ink, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Community',
                    style: AppTheme.label(color: AppTheme.textTertiary)),
                const SizedBox(height: 4),
                Text('Chat',
                    style: AppTheme.display(
                      size: 28,
                      weight: FontWeight.w700,
                      letterSpacing: -1,
                    )),
              ],
            ),
          ),
          AppIconButton(
            icon: Icons.auto_awesome,
            onPressed: () => Navigator.pushNamed(context, '/chat'),
            tooltip: 'AI assistant',
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.refresh,
            onPressed: _loadComments,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.logout,
            onPressed: _logout,
            color: AppTheme.rust,
            tooltip: 'Sign out',
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final scanStatus = _imageScanResult?['status']?.toString();
    final scanning = _isScanningImage || (_isPosting && _pendingImageBytes != null);

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.paperLight,
        border: Border(top: BorderSide(color: AppTheme.hairline, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImageBytes != null) _pendingImagePreview(),
          if (_isScanningImage) const ModerationScanningBanner(),
          if (!_isScanningImage &&
              _imageScanResult != null &&
              scanStatus != null)
            ModerationBanner.fromScan(_imageScanResult!, compact: true),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: scanning ? null : _pickImage,
                icon: const Icon(Icons.image_outlined, color: AppTheme.ink),
                tooltip: 'Attach image',
              ),
              Expanded(
                child: TextField(
                  controller: _commentController,
                  maxLines: 4,
                  minLines: 1,
                  style: AppTheme.body(size: 15, color: AppTheme.ink),
                  decoration: InputDecoration(
                    hintText: 'Type a message…',
                    hintStyle: AppTheme.body(
                      size: 15,
                      color: AppTheme.textTertiary,
                    ),
                    filled: true,
                    fillColor: AppTheme.paper,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppTheme.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppTheme.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppTheme.ink, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _postComment(),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppTheme.ink,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  onTap: scanning ? null : _postComment,
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: scanning
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.paperLight,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: AppTheme.paperLight,
                            size: 22,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pendingImagePreview() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              _pendingImageBytes!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _pendingImageName ?? 'Image',
              style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: _clearPendingImage,
            icon: const Icon(Icons.close, size: 20, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppTheme.rust),
            const SizedBox(height: 12),
            Text('Could not load messages',
                style: AppTheme.body(size: 15, color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
            ActionButton(
              text: 'Retry',
              icon: Icons.refresh,
              onPressed: _loadComments,
              height: 44,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 56, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('No messages yet',
              style: AppTheme.body(size: 16, color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text('Say hello or share a photo',
              style: AppTheme.body(
                size: 14,
                color: AppTheme.textTertiary,
                style: FontStyle.italic,
              )),
        ],
      ),
    );
  }

  Widget _commentsList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: _comments.length,
      itemBuilder: (context, index) => _messageBubble(_comments[index]),
    );
  }

  Widget _messageBubble(dynamic comment) {
    final author = comment['author']?['username']?.toString() ?? 'Reader';
    final isMe = _currentUsername != null && author == _currentUsername;
    final content = comment['content']?.toString() ?? '';
    final imageUrl = comment['imageUrl']?.toString();
    final imageBytes = _decodeDataUrl(imageUrl);
    final createdAt = comment['createdAt']?.toString() ?? '';
    final timeLabel = _formatTime(createdAt);
    final initial = author.isNotEmpty ? author[0].toUpperCase() : '?';

    final bubbleColor = isMe ? AppTheme.ink : AppTheme.paperLight;
    final textColor = isMe ? AppTheme.paperLight : AppTheme.ink;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final rowAlign = isMe ? MainAxisAlignment.end : MainAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 44, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(author,
                      style: AppTheme.body(
                        size: 11,
                        weight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      )),
                  if (timeLabel.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(timeLabel,
                        style: AppTheme.mono(
                          size: 10,
                          color: AppTheme.textTertiary,
                        )),
                  ],
                ],
              ),
            ),
          Row(
            mainAxisAlignment: rowAlign,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.persimmonSoft,
                  child: Text(initial,
                      style: AppTheme.body(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppTheme.ink,
                      )),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    border: isMe
                        ? null
                        : Border.all(color: AppTheme.hairline, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageBytes != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            imageBytes,
                            width: 240,
                            fit: BoxFit.cover,
                          ),
                        ),
                        if (content.isNotEmpty) const SizedBox(height: 8),
                      ],
                      if (content.isNotEmpty)
                        Text(
                          content,
                          style: AppTheme.body(
                            size: 15,
                            color: textColor,
                            height: 1.45,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (isMe) const SizedBox(width: 4),
            ],
          ),
          if (isMe && timeLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(timeLabel,
                  style: AppTheme.mono(
                    size: 10,
                    color: AppTheme.textTertiary,
                  )),
            ),
        ],
      ),
    );
  }

  Uint8List? _decodeDataUrl(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length >= 16 ? iso.substring(11, 16) : '';
    }
  }
}
