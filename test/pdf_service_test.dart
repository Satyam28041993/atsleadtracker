import 'dart:typed_data';

import 'package:atsleadtracker/models/lead_model.dart';
import 'package:atsleadtracker/models/quote_request.dart';
import 'package:atsleadtracker/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

QuoteRequest _quote({
  String customerName = 'Ravi Kumar',
  String companyName = 'Tesca Technologies Pvt. Ltd.',
  String companyType = 'ATEPL',
  double discount = 0,
}) {
  return QuoteRequest(
    refNo: '$companyType/0609/2026-2027',
    date: '07.09.2026',
    customerName: customerName,
    companyName: companyName,
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
    companyType: companyType,
    discountAmount: discount,
  );
}

Lead _lead() {
  final now = DateTime(2026, 9, 7);
  return Lead(
    id: 'lead-1',
    name: 'Ravi Kumar',
    phone: '7849821302',
    email: 'purchase02@tesca.in',
    company: 'Tesca Technologies Pvt. Ltd.',
    status: 'Proposal',
    assignedTo: 'uid-emp',
    createdAt: now,
    remark: '',
    location: 'Jaipur',
    website: '',
    lastModified: now,
  );
}

/// Counts `/Type /Page` objects in the raw PDF.
int _pageCount(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
}

void main() {
  // rootBundle needs the binding for the fonts and letterhead assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfService.generateQuoteData', () {
    test('ATEPL quote fits on three pages, not four', () async {
      // Terms used to be emitted by a third addPage(), and every addPage
      // starts a new physical sheet — so they were pushed onto a fresh page
      // and left the rest of the previous one blank.
      final bytes = await PdfService().generateQuoteData(_lead(), _quote());
      expect(_pageCount(bytes), lessThanOrEqualTo(3));
      expect(bytes.length, greaterThan(1000));
    });

    test('ATS quote also collapses to three pages', () async {
      final bytes =
          await PdfService().generateQuoteData(_lead(), _quote(companyType: 'ATS'));
      expect(_pageCount(bytes), lessThanOrEqualTo(3));
    });

    test('generates with a blank contact name', () async {
      // The ATEPL branch used to fall back to a hardcoded person's name here,
      // printing a stranger on a real customer quotation.
      final bytes = await PdfService().generateQuoteData(_lead(), _quote(customerName: ''));
      expect(bytes.length, greaterThan(1000));
    });

    test('generates with both name and company blank', () async {
      final bytes = await PdfService().generateQuoteData(
        _lead(),
        _quote(customerName: '', companyName: ''),
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('a discounted quote still renders', () async {
      final bytes =
          await PdfService().generateQuoteData(_lead(), _quote(discount: 20000));
      expect(bytes.length, greaterThan(1000));
    });
  });
}
