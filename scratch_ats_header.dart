// Renders a sample ATS quote so the letterhead can be eyeballed without going
// through the app. Not under test/, so `flutter test` does not pick it up.
//
//   flutter test scratch_ats_header.dart
//
// Writes ats_header_preview.pdf next to this file.
import 'dart:io';

import 'package:atsleadtracker/models/lead_model.dart';
import 'package:atsleadtracker/models/quote_request.dart';
import 'package:atsleadtracker/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render ATS letterhead preview', () async {
    final lead = Lead(
      id: 'preview',
      name: 'BPCL AFS',
      company: 'M/S. BPCL AFS',
      phone: '7086332277',
      email: 'incharge.shillong@bsspl.in',
      location: 'Shillong Airport Umroi, Meghalaya Ri-Bhoi- 793103',
      requirement: 'Oxygen Spare sensor',
      source: 'Direct',
      status: 'New',
      createdAt: DateTime.now(),
      assignedTo: 'Admin',
      remark: '',
      website: '',
    );

    final quote = QuoteRequest(
      companyType: 'ATS',
      refNo: 'ATS/0759/2026-2027',
      date: '24.07.2026',
      customerName: 'BPCL AFS',
      companyName: 'M/S. BPCL AFS',
      location: 'Shillong Airport Umroi, Meghalaya Ri-Bhoi- 793103',
      email: 'incharge.shillong@bsspl.in',
      phone: '7086332277',
      products: [
        QuoteProduct(
          productName: 'Oxygen Spare sensor',
          make: 'Applied Techno Systems',
          model: '',
          hsnNo: '90271000',
          parametersMeasured: '',
          productOverview: '',
          keyFeatures: '',
          specification: '',
          accessories: '',
          documentAndCertificate: '',
          quantity: 1,
          unitPrice: 11500,
          srNo: '1',
        ),
      ],
      additionalItems: const [],
      termsPrices: 'Ex-Works, Mumbai',
      termsPf: 'Nil',
      termsFreight: 'Extra at actual.',
      termsPayment: '100% Against Deilivery',
      termsGst: '18% Extra',
      termsExcise: 'Nil',
      termsValidity: '90 days',
      termsDelivery: '1 Weeks',
      termsWarranty: 'One year.',
      terms: [
        QuoteTerm(key: 'Prices', value: 'Ex-Works, Mumbai'),
        QuoteTerm(key: 'P&F', value: 'Nil'),
        QuoteTerm(key: 'Freight', value: 'Extra at actual.'),
        QuoteTerm(key: 'Payment', value: '100% Against Deilivery'),
        QuoteTerm(key: 'GST', value: '18% Extra'),
        QuoteTerm(key: 'GST No', value: '27ACYPB658A1ZN'),
        QuoteTerm(key: 'Excise', value: 'Nil'),
        QuoteTerm(key: 'Validity', value: '90 days'),
        QuoteTerm(key: 'Delivery', value: '1 Weeks'),
        QuoteTerm(key: 'Warranty', value: 'One year.'),
      ],
    );

    final bytes = await PdfService().generateQuoteData(
      lead,
      quote,
      creatorName: 'Admin',
      creatorMobile: '08010915931',
    );
    final file = File('ats_header_preview.pdf');
    await file.writeAsBytes(bytes);
    stdout.writeln('WROTE ${file.absolute.path} (${bytes.length} bytes)');
  });
}
