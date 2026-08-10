/// One product interest on a lead or tender (name + model).
class LeadProductLine {
  const LeadProductLine({
    this.requirement = '',
    this.modelNo = '',
  });

  final String requirement;
  final String modelNo;

  bool get isEmpty => requirement.trim().isEmpty && modelNo.trim().isEmpty;

  factory LeadProductLine.fromJson(Map<String, dynamic> json) {
    return LeadProductLine(
      requirement: json['requirement'] as String? ?? '',
      modelNo: json['modelNo'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'requirement': requirement.trim(),
      'modelNo': modelNo.trim(),
    };
  }

  LeadProductLine copyWith({String? requirement, String? modelNo}) {
    return LeadProductLine(
      requirement: requirement ?? this.requirement,
      modelNo: modelNo ?? this.modelNo,
    );
  }
}
