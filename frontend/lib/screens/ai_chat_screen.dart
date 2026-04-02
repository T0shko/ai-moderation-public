import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with TickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final List<_ChatMessage> _messages = [];
  bool _isSending = false;
  String _provider = 'combined';

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage([String? prefilled]) async {
    final text = (prefilled ?? _messageController.text).trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_ChatMessage(
        role: 'user',
        content: text,
        time: DateTime.now(),
      ));
      _isSending = true;
    });
    _messageController.clear();
    _scrollToEnd();

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final response = await api.sendChatMessage(text, provider: _provider);
      if (mounted) {
        setState(() => _messages.add(_ChatMessage(
              role: 'assistant',
              content: response['response'] ?? 'No response',
              time: DateTime.now(),
            )));
        _scrollToEnd();
      }
    } on AuthException {
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add(_ChatMessage(
              role: 'error',
              content: 'Could not get a response. Please check your connection and try again.',
              time: DateTime.now(),
            )));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToEnd() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _clearChat() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.clearChatHistory();
      if (mounted) setState(() => _messages.clear());
    } on AuthException {
      return;
    } catch (_) {}
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard',
            style: GoogleFonts.dmSans(fontSize: 13)),
        backgroundColor: AppTheme.bgElevated,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: NexusBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child:
                    _messages.isEmpty ? _buildWelcome() : _buildMessageList(),
              ),
              if (_isSending) _buildTypingIndicator(),
              _buildInput(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary.withValues(alpha: 0.85),
        border:
            const Border(bottom: BorderSide(color: AppTheme.borderDefault)),
      ),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_back_rounded,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 14),
          // AI avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppTheme.accentGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.glow(AppTheme.amber, 0.2),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Assistant',
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: AppTheme.success.withValues(alpha: 0.4),
                              blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('Online',
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: AppTheme.success)),
                    Text('  \u2022  ',
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: AppTheme.textTertiary)),
                    Text(_providerLabel(_provider),
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: AppTheme.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _provider = v),
            icon: const Icon(Icons.tune_rounded,
                color: AppTheme.textSecondary, size: 20),
            color: AppTheme.bgElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              side: const BorderSide(color: AppTheme.borderDefault),
            ),
            itemBuilder: (_) => [
              _providerItem('combined', 'Combined', Icons.merge_type_rounded),
              _providerItem('opennlp', 'OpenNLP', Icons.memory_rounded),
              _providerItem(
                  'huggingface', 'HuggingFace', Icons.cloud_outlined),
            ],
          ),
          AppIconButton(
              icon: Icons.delete_outline_rounded,
              onPressed: _clearChat,
              color: AppTheme.error),
        ],
      ),
    );
  }

  String _providerLabel(String p) {
    return switch (p) {
      'combined' => 'Combined AI',
      'opennlp' => 'OpenNLP',
      'huggingface' => 'HuggingFace',
      _ => p,
    };
  }

  PopupMenuItem<String> _providerItem(
      String value, String label, IconData icon) {
    final selected = _provider == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: selected ? AppTheme.amber : AppTheme.textTertiary),
          const SizedBox(width: 12),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: selected ? AppTheme.amber : AppTheme.textPrimary,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400)),
          const Spacer(),
          if (selected)
            const Icon(Icons.check_rounded, size: 16, color: AppTheme.amber),
        ],
      ),
    );
  }

  // ── Welcome / Empty state ──────────────────────────────────────
  Widget _buildWelcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Large AI icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: AppTheme.accentGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppTheme.glow(AppTheme.amber, 0.3),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 24),
          Text('How can I help?',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text(
              'I can explain moderation, analyze sentiment,\nor show you what\'s happening in the community.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: AppTheme.textTertiary,
                  height: 1.5)),
          const SizedBox(height: 32),
          // Suggestion chips
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _SuggestionChip(
                label: 'How does moderation work?',
                icon: Icons.shield_outlined,
                onTap: () => _sendMessage('How does content moderation work?'),
              ),
              _SuggestionChip(
                label: 'What is sentiment analysis?',
                icon: Icons.psychology_outlined,
                onTap: () =>
                    _sendMessage('What is sentiment analysis and how does it work?'),
              ),
              _SuggestionChip(
                label: 'Show recent posts',
                icon: Icons.article_outlined,
                onTap: () =>
                    _sendMessage('Show me the recent community posts'),
              ),
              _SuggestionChip(
                label: 'How does image detection work?',
                icon: Icons.image_search_outlined,
                onTap: () =>
                    _sendMessage('How does image moderation work?'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Messages ───────────────────────────────────────────────────
  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final showAvatar = index == 0 ||
            _messages[index - 1].role != msg.role;
        return _buildMessage(msg, showAvatar: showAvatar);
      },
    );
  }

  Widget _buildMessage(_ChatMessage msg, {bool showAvatar = true}) {
    final isUser = msg.role == 'user';
    final isError = msg.role == 'error';
    final timeStr =
        '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(bottom: showAvatar ? 16 : 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // AI avatar
          if (!isUser) ...[
            if (showAvatar)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: isError
                      ? AppTheme.dangerGradient
                      : AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.auto_awesome_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              )
            else
              const SizedBox(width: 32),
            const SizedBox(width: 10),
          ],
          // Message bubble
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: () => _copyMessage(msg.content),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppTheme.coral.withValues(alpha: 0.15)
                          : isError
                              ? AppTheme.error.withValues(alpha: 0.08)
                              : AppTheme.bgTertiary,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                      border: Border.all(
                        color: isUser
                            ? AppTheme.coral.withValues(alpha: 0.25)
                            : isError
                                ? AppTheme.error.withValues(alpha: 0.2)
                                : AppTheme.borderDefault,
                      ),
                    ),
                    child: Text(
                      msg.content,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color:
                            isError ? AppTheme.error : AppTheme.textPrimary,
                        height: 1.55,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(timeStr,
                    style: GoogleFonts.dmSans(
                        fontSize: 10, color: AppTheme.textTertiary)),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  // ── Typing indicator ───────────────────────────────────────────
  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppTheme.accentGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.bgTertiary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: AppTheme.borderDefault),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _BounceDot(delay: i * 160)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input ──────────────────────────────────────────────────────
  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary.withValues(alpha: 0.95),
        border:
            const Border(top: BorderSide(color: AppTheme.borderDefault)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.bgTertiary,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.borderActive),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                style: GoogleFonts.dmSans(
                    color: AppTheme.textPrimary, fontSize: 14),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: 'Ask me anything...',
                  hintStyle:
                      GoogleFonts.dmSans(color: AppTheme.textTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _isSending ? null : _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient:
                    _isSending ? null : AppTheme.accentGradient,
                color: _isSending ? AppTheme.bgTertiary : null,
                shape: BoxShape.circle,
                boxShadow: _isSending
                    ? null
                    : AppTheme.glow(AppTheme.amber, 0.25),
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                          color: AppTheme.textTertiary, strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data model ─────────────────────────────────────────────────────
class _ChatMessage {
  final String role;
  final String content;
  final DateTime time;

  _ChatMessage({
    required this.role,
    required this.content,
    required this.time,
  });
}

// ── Suggestion chip ────────────────────────────────────────────────
class _SuggestionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.borderDefault),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.amber),
            const SizedBox(width: 10),
            Flexible(
              child: Text(label,
                  style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Animated bounce dot ────────────────────────────────────────────
class _BounceDot extends StatefulWidget {
  final int delay;
  const _BounceDot({required this.delay});

  @override
  State<_BounceDot> createState() => _BounceDotState();
}

class _BounceDotState extends State<_BounceDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _bounce = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounce,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _bounce.value),
        child: Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: AppTheme.amber.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
