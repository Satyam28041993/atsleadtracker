import '../models/lead_model.dart';
import '../models/quotation_model.dart';

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Strips an Indian country code / trunk zero so `+91 98765 43210`,
/// `098765 43210` and `9876543210` all compare equal.
String _nationalDigits(String digits) {
  if (digits.length > 10 && digits.startsWith('91')) {
    return digits.substring(digits.length - 10);
  }
  if (digits.length == 11 && digits.startsWith('0')) {
    return digits.substring(1);
  }
  return digits;
}

/// True when [query] (as typed by a user) matches a phone number in [stored].
///
/// Compares digits only, so spaces, dashes, brackets and a `+91` / leading
/// `0` on either side do not matter. [stored] may hold several numbers
/// (`98765 43210 / 91234 56789`); each is checked separately so digits from
/// two numbers never join into a false match. Needs at least 3 digits.
bool phoneMatches(String stored, String query) {
  final q = _nationalDigits(_digits(query));
  if (q.length < 3 || stored.trim().isEmpty) return false;
  for (final part in stored.split(RegExp(r'[,/;|\n]|\s{2,}'))) {
    final d = _digits(part);
    if (d.isEmpty) continue;
    if (d.contains(q) || _nationalDigits(d).contains(q)) return true;
  }
  return false;
}

/// Shared lead search used by Kanban, Tender, Follow-ups, Today's Work and
/// the analytics drill-down: name, company, email, bid no and phone.
bool leadMatchesSearch(Lead lead, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return lead.name.toLowerCase().contains(q) ||
      lead.company.toLowerCase().contains(q) ||
      lead.email.toLowerCase().contains(q) ||
      lead.bidNo.toLowerCase().contains(q) ||
      lead.phone.toLowerCase().contains(q) ||
      phoneMatches(lead.phone, q);
}

/// Quotation search: ref no, company, customer, phone, email, location,
/// creator, and every product's name / make / model / HSN plus additional
/// item descriptions.
///
/// Each word of [query] must match somewhere, so `portable 2000` finds a
/// quote with a "Portable gas detector" whose model is "GD-2000".
bool quotationMatchesSearch(QuotationModel quote, String query) {
  final words = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return true;

  final r = quote.quoteRequest;
  final haystack = [
    quote.currentRefNo,
    quote.baseRefNo,
    r.refNo,
    r.companyName,
    r.customerName,
    r.email,
    r.location,
    r.phone,
    quote.employeeName,
    for (final p in r.products) ...[p.productName, p.make, p.model, p.hsnNo],
    for (final item in r.additionalItems) item.description,
  ].join('\n').toLowerCase();

  return words.every((w) => haystack.contains(w)) ||
      // A phone typed with spaces ("98765 43210") is several words; try it
      // whole as a number too.
      phoneMatches(r.phone, query);
}
