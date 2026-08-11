import '../models/quote_request.dart';

/// Leading characters pasted from Word/Excel used as faux bullets.
final RegExp _leadingBulletPrefix = RegExp(
  r'^[\s\u2022\u2023\u2043\u2219\u00B7\u25AA\u25AB\u25CF\u25CB\u25E6\u2013\u2014\-*'
  r'\u2713\u2714\u2611\u2610\u2612\u221A\u00B1]+\s*',
);

/// Normalizes user-entered text for PDF output. Smart quotes and uncommon
/// punctuation are mapped to readable ASCII where needed; symbols like ±, ≤,
/// °, ₹, and ✓ are kept when using Noto Sans in [PdfService].
String normalizeForPdf(String text) {
  if (text.isEmpty) return text;

  var result = text
      // Curly / smart double quotes -> straight inch/mark quote
      .replaceAll('\u201C', '"') // "
      .replaceAll('\u201D', '"') // "
      .replaceAll('\u201E', '"') // „
      .replaceAll('\u00AB', '"') // «
      .replaceAll('\u00BB', '"') // »
      // Inch / foot primes
      .replaceAll('\u2033', '"') // ″ double prime
      .replaceAll('\u2032', "'") // ′ prime
      // Single quotes
      .replaceAll('\u2018', "'") // '
      .replaceAll('\u2019', "'") // '
      .replaceAll('\u201A', "'") // ‚
      .replaceAll('\u201B', "'") // ‛
      // Dashes / minus variants
      .replaceAll('\u2013', '-') // en dash
      .replaceAll('\u2014', '-') // em dash
      .replaceAll('\u2212', '-') // minus sign
      .replaceAll('\u2010', '-') // hyphen
      .replaceAll('\u2011', '-') // non-breaking hyphen
      // Spaces / ellipsis
      .replaceAll('\u00A0', ' ') // non-breaking space
      .replaceAll('\u2026', '...') // …
      // Multiplication / division (Word often uses Unicode times)
      .replaceAll('\u00D7', ' x ') // ×
      .replaceAll('\u00F7', ' / ') // ÷
      // Comparison / math symbols that sometimes fail in legacy fonts
      .replaceAll('\u2264', '<=') // ≤
      .replaceAll('\u2265', '>=') // ≥
      .replaceAll('\u2248', '~') // ≈
      .replaceAll('\u2260', '!=') // ≠
      // Checkbox / icon bullets from Word templates
      .replaceAll('\u2610', '') // ☐
      .replaceAll('\u2611', '') // ☑
      .replaceAll('\u2612', '') // ☒
      // Currency
      .replaceAll('\u20B9', 'Rs.'); // ₹

  // Subscript digits (e.g. N₂) -> plain digits for safety.
  const subscripts = {
    '\u2080': '0',
    '\u2081': '1',
    '\u2082': '2',
    '\u2083': '3',
    '\u2084': '4',
    '\u2085': '5',
    '\u2086': '6',
    '\u2087': '7',
    '\u2088': '8',
    '\u2089': '9',
  };
  for (final entry in subscripts.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }

  // Superscript digits -> plain digits.
  const superscripts = {
    '\u2070': '0',
    '\u00B9': '1',
    '\u00B2': '2',
    '\u00B3': '3',
    '\u2074': '4',
    '\u2075': '5',
    '\u2076': '6',
    '\u2077': '7',
    '\u2078': '8',
    '\u2079': '9',
  };
  for (final entry in superscripts.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }

  // Normalize uncommon degree symbols to standard degree (°).
  result = result
      .replaceAll('\u2103', '°C') // ℃
      .replaceAll('\u02DA', '°') // ˚ ring above (often pasted as degree)
      .replaceAll('\u00BA', '°'); // º masculine ordinal (sometimes misused)

  return result;
}

/// Strips Word-style bullet/check prefixes before drawing our own bullet dot.
String stripLeadingBulletPrefix(String text) {
  return text.replaceFirst(_leadingBulletPrefix, '').trim();
}

/// Returns a copy of [quote] with PDF-safe display strings.
QuoteRequest normalizeQuoteRequestForPdf(QuoteRequest quote) {
  String t(String s) => normalizeForPdf(s);

  return QuoteRequest(
    refNo: t(quote.refNo),
    date: t(quote.date),
    customerName: t(quote.customerName),
    companyName: t(quote.companyName),
    location: t(quote.location),
    email: t(quote.email),
    phone: t(quote.phone),
    products: quote.products
        .map(
          (p) => QuoteProduct(
            productName: t(p.productName),
            make: t(p.make),
            model: t(p.model),
            hsnNo: t(p.hsnNo),
            productOverview: t(p.productOverview),
            keyFeatures: t(p.keyFeatures),
            specification: t(p.specification),
            accessories: t(p.accessories),
            documentAndCertificate: t(p.documentAndCertificate),
            parametersMeasured: t(p.parametersMeasured),
            quantity: p.quantity,
            unitPrice: p.unitPrice,
            productImageUrl: p.productImageUrl,
            srNo: t(p.srNo),
          ),
        )
        .toList(),
    additionalItems: quote.additionalItems
        .map(
          (item) => AdditionalQuoteItem(
            description: t(item.description),
            specification: t(item.specification),
            qty: t(item.qty),
            unitRate: item.unitRate,
            amount: item.amount,
            itemType: item.itemType,
          ),
        )
        .toList(),
    termsPrices: t(quote.termsPrices),
    termsPf: t(quote.termsPf),
    termsFreight: t(quote.termsFreight),
    termsPayment: t(quote.termsPayment),
    termsGst: t(quote.termsGst),
    termsExcise: t(quote.termsExcise),
    termsValidity: t(quote.termsValidity),
    termsDelivery: t(quote.termsDelivery),
    termsWarranty: t(quote.termsWarranty),
    companyType: quote.companyType,
    terms: quote.terms.map((e) => QuoteTerm(key: t(e.key), value: t(e.value))).toList(),
  );
}
