class SettingsModel {
  SettingsModel({required this.template});

  static const String collectionName = 'settings';
  static const String whatsappDocId = 'whatsapp_config';
  static const String defaultTemplate =
      'Hi {name}, this is Satyam from Applied Techno Systems. I am reaching out regarding your inquiry for {requirement}. How can I assist you further?';

  final String template;

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{'template': template};
  }

  static SettingsModel fromMap(Map<String, dynamic> data) {
    final template = (data['template'] as String?)?.trim();
    if (template == null || template.isEmpty) {
      return SettingsModel(template: defaultTemplate);
    }
    return SettingsModel(template: template);
  }
}
