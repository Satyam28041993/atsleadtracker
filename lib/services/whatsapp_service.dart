import '../models/lead_model.dart';
import 'message_template_service.dart';

enum LeadReplySentiment { positive, neutral, negative }

class SmartWhatsAppFollowUp {
  const SmartWhatsAppFollowUp({
    required this.dayOffset,
    required this.scheduledAt,
    required this.message,
  });

  final int dayOffset;
  final DateTime scheduledAt;
  final String message;
}

String _requirementPlaceholder(Lead lead) {
  final active = lead.activeProductLines;
  if (active.isEmpty) {
    return lead.requirement.trim().isEmpty ? 'our products' : lead.requirement.trim();
  }
  final names = active.map((l) => l.requirement.trim()).where((s) => s.isNotEmpty);
  final joined = names.join(', ');
  return joined.isEmpty ? 'our products' : joined;
}

class WhatsAppService {
  WhatsAppService({MessageTemplateService? templateService})
    : _templateService = templateService ?? MessageTemplateService.instance;

  final MessageTemplateService _templateService;

  Future<String> getTemplate() async {
    return _templateService.getTemplate();
  }

  String resolveTemplateMessage(String template, Lead lead) {
    return template
        .replaceAll(
          '{name}',
          lead.name.trim().isEmpty ? 'there' : lead.name.trim(),
        )
        .replaceAll(
          '{requirement}',
          _requirementPlaceholder(lead),
        );
  }

  Uri buildUriFromMessage(Lead lead, String message) {
    final phoneDigits = lead.phone.replaceAll(RegExp(r'\D'), '');
    return Uri.parse(
      'https://wa.me/$phoneDigits?text=${Uri.encodeComponent(message)}',
    );
  }

  Uri parseTemplate(String template, Lead lead) {
    final resolvedTemplate = resolveTemplateMessage(template, lead);
    return buildUriFromMessage(lead, resolvedTemplate);
  }

  Future<Uri> buildTemplateUri(Lead lead) async {
    final template = await getTemplate();
    return parseTemplate(template, lead);
  }

  LeadReplySentiment inferSentiment(List<String> previousReplies) {
    if (previousReplies.isEmpty) return LeadReplySentiment.neutral;
    final text = previousReplies.join(' ').toLowerCase();

    const positiveHints = <String>[
      'interested',
      'yes',
      'approved',
      'confirm',
      'go ahead',
      'share quote',
      'need this',
      'finalize',
      'ok',
      'thanks',
    ];
    const negativeHints = <String>[
      'not interested',
      'later',
      'busy',
      'no need',
      'too expensive',
      'expensive',
      'reject',
      'stop',
      'not now',
      'cancel',
    ];

    final positiveScore = positiveHints.where(text.contains).length;
    final negativeScore = negativeHints.where(text.contains).length;

    if (negativeScore > positiveScore && negativeScore > 0) {
      return LeadReplySentiment.negative;
    }
    if (positiveScore > negativeScore && positiveScore > 0) {
      return LeadReplySentiment.positive;
    }
    return LeadReplySentiment.neutral;
  }

  Future<List<SmartWhatsAppFollowUp>> generateSmartFollowUpSequence({
    required Lead lead,
    required List<String> previousReplies,
    DateTime? startAt,
  }) async {
    final sentiment = inferSentiment(previousReplies);
    final baseTemplate = await getTemplate();
    final opener = resolveTemplateMessage(baseTemplate, lead);
    final status = lead.status.trim().isEmpty
        ? 'Follow-up'
        : lead.status.trim();
    final anchor = startAt ?? DateTime.now();

    final stage0 = _stageMessage(
      opener: opener,
      status: status,
      sentiment: sentiment,
      dayOffset: 0,
    );
    final stage3 = _stageMessage(
      opener: opener,
      status: status,
      sentiment: sentiment,
      dayOffset: 3,
    );
    final stage7 = _stageMessage(
      opener: opener,
      status: status,
      sentiment: sentiment,
      dayOffset: 7,
    );

    return <SmartWhatsAppFollowUp>[
      SmartWhatsAppFollowUp(
        dayOffset: 0,
        scheduledAt: _withDayOffset(anchor, 0),
        message: stage0,
      ),
      SmartWhatsAppFollowUp(
        dayOffset: 3,
        scheduledAt: _withDayOffset(anchor, 3),
        message: stage3,
      ),
      SmartWhatsAppFollowUp(
        dayOffset: 7,
        scheduledAt: _withDayOffset(anchor, 7),
        message: stage7,
      ),
    ];
  }

  DateTime _withDayOffset(DateTime source, int dayOffset) {
    return DateTime(
      source.year,
      source.month,
      source.day + dayOffset,
      source.hour,
      source.minute,
    );
  }

  String _stageMessage({
    required String opener,
    required String status,
    required LeadReplySentiment sentiment,
    required int dayOffset,
  }) {
    final sentimentTone = switch (sentiment) {
      LeadReplySentiment.positive =>
        'I appreciated your positive response earlier.',
      LeadReplySentiment.negative =>
        'I understand timing may have been difficult earlier.',
      LeadReplySentiment.neutral =>
        'I wanted to follow up at the right time for your team.',
    };

    final statusLine = switch (status) {
      'New' => 'This is a quick intro follow-up from our side.',
      'Contacted' => 'Continuing from our initial discussion.',
      'Proposal' => 'Following up on the proposal we shared.',
      'Follow-up' => 'Sharing a concise follow-up update.',
      'Won' => 'Checking in post-confirmation for smooth execution.',
      'Lost' => 'Reconnecting in case priorities have changed.',
      _ => 'Following up from Applied Techno Systems.',
    };

    final ask = switch (dayOffset) {
      0 =>
        'Could we schedule a short 10-minute call to align your requirement?',
      3 => 'Would you like me to share a tailored recommendation and quote?',
      7 =>
        'If this is still relevant, I can prioritize this for immediate support this week.',
      _ => 'Please let me know the best next step from your side.',
    };

    return '$opener\n\n$statusLine $sentimentTone\n$ask';
  }
}
