import 'package:atsleadtracker/models/quote_request.dart';
import 'package:atsleadtracker/utils/pdf_text_normalize.dart';
import 'package:flutter_test/flutter_test.dart';

QuoteRequest _quote({double discountAmount = 0}) {
  return QuoteRequest(
    refNo: 'ATEPL/0609/2026-2027',
    date: '07.09.2026',
    customerName: 'Ravi Kumar',
    companyName: 'Tesca Technologies Pvt. Ltd.',
    location: 'Jaipur, Rajasthan, India.',
    email: 'purchase02@tesca.in',
    phone: '7849821302',
    products: const [
      QuoteProduct(
        productName: 'Portable Flue Gas Analyzer',
        make: 'ATS',
        model: 'ATS-206A',
        hsnNo: '90271000',
        quantity: 1,
        unitPrice: 202950,
      ),
    ],
    termsPrices: 'Ex-Works, Mumbai',
    termsPf: '2% Extra',
    termsFreight: '2% Extra',
    termsPayment: '40% Advance & 60% against PI',
    termsGst: '18% Extra',
    termsExcise: 'Nil',
    termsValidity: '90 days.',
    termsDelivery: '2-3 Weeks',
    termsWarranty: 'One year.',
    discountAmount: discountAmount,
  );
}

void main() {
  group('normalizeQuoteRequestForPdf', () {
    // Regression: this rebuilds a fresh QuoteRequest field-by-field for
    // PDF-safe text, and it once forgot discountAmount — every generated
    // PDF silently defaulted it to 0, so a discount the user entered in the
    // quote builder and that was saved to Firestore never showed up on the
    // printed quotation. hasDiscount/discountValue/totalAmount all fall out
    // of discountAmount, so losing it here is invisible everywhere else.
    test('carries the discount amount through', () {
      final normalized = normalizeQuoteRequestForPdf(_quote(discountAmount: 20000));
      expect(normalized.discountAmount, 20000);
      expect(normalized.hasDiscount, isTrue);
      expect(normalized.totalAmount, 202950 - 20000);
    });

    test('a quote with no discount stays without one', () {
      final normalized = normalizeQuoteRequestForPdf(_quote());
      expect(normalized.discountAmount, 0);
      expect(normalized.hasDiscount, isFalse);
      expect(normalized.totalAmount, normalized.grossAmount);
    });
  });
}
