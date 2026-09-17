/// A currency a quotation's prices can be entered and printed in.
class QuoteCurrency {
  const QuoteCurrency({
    required this.code,
    required this.label,
    required this.symbol,
    required this.pdfHeaderLabel,
    this.usesSlashSuffix = false,
  });

  /// ISO-ish code stored on the quote, e.g. 'INR', 'USD'.
  final String code;

  /// Shown in the currency dropdown, e.g. 'US Dollar (USD)'.
  final String label;

  /// Printed before an amount, e.g. '₹', '\$', 'AED'.
  final String symbol;

  /// Column-header text on the PDF item table, e.g. 'IN Rs', 'USD'.
  final String pdfHeaderLabel;

  /// Only INR quotes end an amount with "/-" — that is an Indian
  /// legal-document convention, not an international one.
  final bool usesSlashSuffix;
}

const String kDefaultQuoteCurrencyCode = 'INR';

const List<QuoteCurrency> kQuoteCurrencies = <QuoteCurrency>[
  QuoteCurrency(
    code: 'INR',
    label: 'Indian Rupee (INR)',
    symbol: '₹',
    pdfHeaderLabel: 'IN Rs',
    usesSlashSuffix: true,
  ),
  QuoteCurrency(
    code: 'USD',
    label: 'US Dollar (USD)',
    symbol: '\$',
    pdfHeaderLabel: 'USD',
  ),
  QuoteCurrency(
    code: 'EUR',
    label: 'Euro (EUR)',
    symbol: '€',
    pdfHeaderLabel: 'EUR',
  ),
  QuoteCurrency(
    code: 'GBP',
    label: 'British Pound (GBP)',
    symbol: '£',
    pdfHeaderLabel: 'GBP',
  ),
  QuoteCurrency(
    code: 'AED',
    label: 'UAE Dirham (AED)',
    symbol: 'AED',
    pdfHeaderLabel: 'AED',
  ),
];

/// The [QuoteCurrency] for a stored code, falling back to INR for a blank or
/// unrecognised one (legacy quotes never stored a currency at all).
QuoteCurrency quoteCurrencyFor(String? code) {
  final trimmed = code?.trim() ?? '';
  return kQuoteCurrencies.firstWhere(
    (c) => c.code == trimmed,
    orElse: () => kQuoteCurrencies.first,
  );
}
