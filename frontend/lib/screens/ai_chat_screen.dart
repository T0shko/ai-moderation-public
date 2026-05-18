import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final List<_ChatMessage> _messages = [];
  bool _isSending = false;
  String _provider = 'combined';

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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
    } catch (_) {
      if (mounted) {
        setState(() => _messages.add(_ChatMessage(
              role: 'error',
              content:
                  'The wire failed. Check your connection and try again.',
              time: DateTime.now(),
            )));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
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
        content: Text(
          'Copied',
          style: AppTheme.mono(size: 11, color: AppTheme.paperLight),
        ),
        backgroundColor: AppTheme.ink,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
      ),
    );
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
                child:
                    _messages.isEmpty ? _welcome() : _messageList(),
              ),
              if (_isSending) _typingBlock(),
              _input(),
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
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_back,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 14),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.persimmonSoft,
              border: Border.all(color: AppTheme.persimmon, width: 1.2),
            ),
            child: const Icon(Icons.auto_awesome,
                color: AppTheme.persimmon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: AppTheme.display(
                      size: 22,
                      weight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                    children: [
                      const TextSpan(text: 'The '),
                      TextSpan(
                        text: 'Concierge',
                        style: AppTheme.display(
                          size: 22,
                          weight: FontWeight.w400,
                          style: FontStyle.italic,
                          letterSpacing: -0.8,
                          color: AppTheme.persimmon,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                        width: 6, height: 6, color: AppTheme.olive),
                    const SizedBox(width: 6),
                    Text('ON WIRE',
                        style: AppTheme.label(
                            color: AppTheme.olive, size: 9)),
                    const SizedBox(width: 10),
                    Text('· ${_providerLabel(_provider)}',
                        style: AppTheme.label(
                            color: AppTheme.textTertiary, size: 9)),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _provider = v),
            icon: const Icon(Icons.tune,
                color: AppTheme.ink, size: 20),
            color: AppTheme.paperLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              side: const BorderSide(color: AppTheme.ink),
            ),
            itemBuilder: (_) => [
              _providerItem('combined', 'Combined', Icons.merge_type),
              _providerItem('groq', 'Groq (free API)', Icons.bolt),
              _providerItem('opennlp', 'OpenNLP', Icons.memory),
              _providerItem(
                  'huggingface', 'HuggingFace', Icons.cloud_outlined),
            ],
          ),
          AppIconButton(
            icon: Icons.delete_outline,
            onPressed: _clearChat,
            color: AppTheme.rust,
          ),
        ],
      ),
    );
  }

  String _providerLabel(String p) {
    return switch (p) {
      'combined' => 'Combined',
      'groq' => 'Groq',
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
              size: 16,
              color: selected ? AppTheme.persimmon : AppTheme.textTertiary),
          const SizedBox(width: 12),
          Text(label,
              style: AppTheme.body(
                size: 14,
                color: selected ? AppTheme.persimmon : AppTheme.ink,
                weight: selected ? FontWeight.w600 : FontWeight.w400,
              )),
          const Spacer(),
          if (selected)
            const Icon(Icons.check,
                size: 14, color: AppTheme.persimmon),
        ],
      ),
    );
  }

  // ── Welcome ───────────────────────────────────────────────────
  Widget _welcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('§ HOUSE CONCIERGE',
                      style: AppTheme.label(color: AppTheme.persimmon)),
                  const Spacer(),
                  Text('AVAILABLE \u00B7 24h',
                      style: AppTheme.label(color: AppTheme.textTertiary)),
                ],
              ),
              const SizedBox(height: 8),
              Container(height: 2, color: AppTheme.ink),
              const SizedBox(height: 18),
              RichText(
                text: TextSpan(
                  style: AppTheme.display(
                    size: 38,
                    weight: FontWeight.w700,
                    letterSpacing: -1.4,
                    height: 0.98,
                  ),
                  children: [
                    const TextSpan(text: 'How may I '),
                    TextSpan(
                      text: 'assist',
                      style: AppTheme.display(
                        size: 38,
                        weight: FontWeight.w400,
                        style: FontStyle.italic,
                        letterSpacing: -1.4,
                        color: AppTheme.persimmon,
                      ),
                    ),
                    const TextSpan(text: ' you,\ndear reader?'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'I explain moderation, read sentiment, and report on the day\u2019s dispatches.',
                style: AppTheme.body(
                  size: 14,
                  color: AppTheme.textSecondary,
                  style: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 22),
              Text('SUGGESTED QUESTIONS',
                  style: AppTheme.label(color: AppTheme.textSecondary)),
              const SizedBox(height: 12),
              _suggestion(
                '01',
                'How does moderation work?',
                () => _sendMessage('How does content moderation work?'),
              ),
              _suggestion(
                '02',
                'What is sentiment analysis?',
                () => _sendMessage(
                    'What is sentiment analysis and how does it work?'),
              ),
              _suggestion(
                '03',
                'Show me recent dispatches',
                () => _sendMessage('Show me the recent community posts'),
              ),
              _suggestion(
                '04',
                'How does image detection work?',
                () => _sendMessage('How does image moderation work?'),
                last: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestion(String index, String label, VoidCallback onTap,
      {bool last = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: const BorderSide(color: AppTheme.hairline),
            bottom: last
                ? const BorderSide(color: AppTheme.hairline)
                : BorderSide.none,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Text(index,
                style: AppTheme.mono(
                    size: 11,
                    color: AppTheme.persimmon,
                    weight: FontWeight.w600)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: AppTheme.body(
                  size: 16,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward,
                size: 16, color: AppTheme.ink),
          ],
        ),
      ),
    );
  }

  // ── Messages ──────────────────────────────────────────────────
  Widget _messageList() {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final msg = _messages[_messages.length - 1 - i];
        return _messageBlock(msg);
      },
    );
  }

  Widget _messageBlock(_ChatMessage msg) {
    final isUser = msg.role == 'user';
    final isError = msg.role == 'error';
    final t = msg.time;
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final rowAlign = isUser ? MainAxisAlignment.end : MainAxisAlignment.start;
    final bubbleColor = isError
        ? AppTheme.rust.withValues(alpha: 0.12)
        : isUser
            ? AppTheme.ink
            : AppTheme.paperLight;
    final textColor = isError
        ? AppTheme.rust
        : isUser
            ? AppTheme.paperLight
            : AppTheme.ink;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onLongPress: () => _copyMessage(msg.content),
        child: Column(
          crossAxisAlignment: align,
          children: [
            Row(
              mainAxisAlignment: rowAlign,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isUser) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.persimmonSoft,
                      border: Border.all(color: AppTheme.persimmon, width: 1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        size: 16, color: AppTheme.persimmon),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                      border: isUser || isError
                          ? null
                          : Border.all(color: AppTheme.hairline),
                    ),
                    child: Text(
                      msg.content,
                      style: AppTheme.body(
                        size: 15,
                        color: textColor,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(
                top: 4,
                left: isUser ? 0 : 40,
                right: isUser ? 8 : 0,
              ),
              child: Text(
                isError ? 'Error · $timeStr' : timeStr,
                style: AppTheme.mono(
                  size: 10,
                  color: AppTheme.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typingBlock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        children: [
          Text('CONCIERGE',
              style: AppTheme.label(color: AppTheme.persimmon, size: 10)),
          const SizedBox(width: 10),
          ...List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _BounceDot(delay: i * 160),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.paperLight,
        border: Border(top: BorderSide(color: AppTheme.hairline, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              maxLines: 4,
              minLines: 1,
              style: AppTheme.body(size: 15, color: AppTheme.ink),
              decoration: InputDecoration(
                hintText: 'Ask the concierge…',
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
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: AppTheme.persimmon,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              onTap: _isSending ? null : _sendMessage,
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: 48,
                height: 48,
                child: _isSending
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
    );
  }
}

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
      duration: const Duration(milliseconds: 720),
      vsync: this,
    );
    _bounce = Tween<double>(begin: 0, end: -4).animate(
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
      builder: (_, _) => Transform.translate(
        offset: Offset(0, _bounce.value),
        child: Container(
          width: 5,
          height: 5,
          color: AppTheme.persimmon,
        ),
      ),
    );
  }
}
