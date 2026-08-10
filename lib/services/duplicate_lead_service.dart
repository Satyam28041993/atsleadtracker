import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// One existing lead that looks like the one being entered.
class DuplicateLeadMatch {
  const DuplicateLeadMatch({
    required this.leadId,
    required this.matchedOn,
    required this.name,
    required this.company,
    required this.status,
    required this.ownerName,
    required this.isMine,
    required this.isTender,
  });

  final String leadId;

  /// `'phone'`, `'email'` or `'company'`.
  final String matchedOn;
  final String name;
  final String company;
  final String status;
  final String ownerName;

  /// True when the existing lead is already assigned to the current user.
  final bool isMine;
  final bool isTender;

  String get matchedOnLabel {
    switch (matchedOn) {
      case 'phone':
        return 'Same phone number';
      case 'email':
        return 'Same email';
      case 'company':
        return 'Same company name';
      default:
        return 'Possible match';
    }
  }

  String get displayTitle {
    if (company.trim().isNotEmpty) return company.trim();
    if (name.trim().isNotEmpty) return name.trim();
    return leadId;
  }
}

/// Result of a duplicate lookup.
class DuplicateLeadResult {
  const DuplicateLeadResult({
    required this.matches,
    required this.checkedEveryone,
  });

  const DuplicateLeadResult.empty()
      : matches = const <DuplicateLeadMatch>[],
        checkedEveryone = false;

  final List<DuplicateLeadMatch> matches;

  /// True when the whole CRM was searched (server check succeeded). False when
  /// only the caller's own visible leads could be searched, so the warning
  /// dialog can say so honestly instead of implying a clean bill of health.
  final bool checkedEveryone;

  bool get hasMatches => matches.isNotEmpty;
}

/// Warns about leads that already exist before a new one is created.
///
/// Firestore rules deliberately stop an employee from reading another
/// employee's leads, which is exactly the case worth catching ("two people
/// chasing the same party"). So the primary path is a callable Cloud Function
/// (`checkDuplicateLead`) that does the lookup with admin rights and returns
/// only a short summary — owner name, company, status — never the full lead.
///
/// If that function is unreachable (not deployed yet, offline, timeout) the
/// service quietly falls back to a client-side query, which still covers
/// everything the signed-in user is allowed to read: all leads for an admin,
/// their own leads for an employee. The result is flagged via
/// [DuplicateLeadResult.checkedEveryone] so the UI never overstates it.
///
/// This is advisory only. It never blocks a save and never writes anything.
class DuplicateLeadService {
  DuplicateLeadService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  /// Client-side fallback reads at most this many leads, so a large collection
  /// can never turn a duplicate check into an expensive scan.
  static const int _fallbackScanLimit = 400;

  static const Duration _timeout = Duration(seconds: 8);

  /// Digits only, last 10 — so "+91 98765 43210" and "9876543210" match.
  static String normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return '';
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }

  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  static final RegExp _companyNoise = RegExp(
    r'\b(pvt|private|ltd|limited|llp|inc|co|company|corp|corporation|enterprises|industries|technologies|technology|solutions|systems|india)\b',
  );

  static String normalizeCompany(String raw) {
    var value = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    value = value.replaceAll(_companyNoise, ' ');
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Looks for existing leads matching any of [phone], [email] or [company].
  ///
  /// Returns an empty result rather than throwing — a duplicate check must
  /// never be the reason a lead cannot be saved.
  Future<DuplicateLeadResult> check({
    String phone = '',
    String email = '',
    String company = '',
    String? excludeLeadId,
  }) async {
    final phoneKey = normalizePhone(phone);
    final emailKey = normalizeEmail(email);
    final companyKey = normalizeCompany(company);
    if (phoneKey.isEmpty && emailKey.isEmpty && companyKey.isEmpty) {
      return const DuplicateLeadResult.empty();
    }

    try {
      final callable = _functions.httpsCallable('checkDuplicateLead');
      final response = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'phone': phone,
        'email': email,
        'company': company,
        if (excludeLeadId != null) 'excludeLeadId': excludeLeadId,
      }).timeout(_timeout);

      final raw = (response.data['matches'] as List<dynamic>?) ?? const [];
      return DuplicateLeadResult(
        matches: raw
            .whereType<Map<Object?, Object?>>()
            .map(_matchFromMap)
            .toList(growable: false),
        checkedEveryone: true,
      );
    } catch (e) {
      debugPrint('[DuplicateLeadService] Server check unavailable: $e');
      return _fallbackCheck(
        phoneKey: phoneKey,
        emailKey: emailKey,
        companyKey: companyKey,
        excludeLeadId: excludeLeadId,
      );
    }
  }

  DuplicateLeadMatch _matchFromMap(Map<Object?, Object?> map) {
    String str(String key) => (map[key] as String?)?.trim() ?? '';
    return DuplicateLeadMatch(
      leadId: str('leadId'),
      matchedOn: str('matchedOn'),
      name: str('name'),
      company: str('company'),
      status: str('status'),
      ownerName: str('ownerName').isEmpty ? 'Another employee' : str('ownerName'),
      isMine: map['isMine'] == true,
      isTender: map['isTender'] == true,
    );
  }

  /// Only sees what Firestore rules already allow this user to read.
  Future<DuplicateLeadResult> _fallbackCheck({
    required String phoneKey,
    required String emailKey,
    required String companyKey,
    String? excludeLeadId,
  }) async {
    try {
      final snap = await _firestore
          .collection('leads')
          .limit(_fallbackScanLimit)
          .get()
          .timeout(_timeout);

      final matches = <DuplicateLeadMatch>[];
      for (final doc in snap.docs) {
        if (doc.id == excludeLeadId) continue;
        final data = doc.data();

        final docPhone = normalizePhone((data['phone'] as String?) ?? '');
        final docEmail = normalizeEmail((data['email'] as String?) ?? '');
        final docCompany = normalizeCompany((data['company'] as String?) ?? '');

        String? matchedOn;
        if (phoneKey.isNotEmpty && docPhone == phoneKey) {
          matchedOn = 'phone';
        } else if (emailKey.isNotEmpty && docEmail == emailKey) {
          matchedOn = 'email';
        } else if (companyKey.isNotEmpty && docCompany == companyKey) {
          matchedOn = 'company';
        }
        if (matchedOn == null) continue;

        matches.add(
          DuplicateLeadMatch(
            leadId: doc.id,
            matchedOn: matchedOn,
            name: ((data['name'] as String?) ?? '').trim(),
            company: ((data['company'] as String?) ?? '').trim(),
            status: ((data['status'] as String?) ?? '').trim(),
            ownerName: 'Someone in your team',
            isMine: false,
            isTender: data['isTender'] == true,
          ),
        );
        if (matches.length >= 8) break;
      }

      return DuplicateLeadResult(matches: matches, checkedEveryone: false);
    } catch (e) {
      debugPrint('[DuplicateLeadService] Fallback check failed: $e');
      return const DuplicateLeadResult.empty();
    }
  }
}
