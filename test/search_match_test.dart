import 'package:atsleadtracker/models/lead_model.dart';
import 'package:atsleadtracker/models/quotation_model.dart';
import 'package:atsleadtracker/models/quote_request.dart';
import 'package:atsleadtracker/utils/search_match.dart';
import 'package:flutter_test/flutter_test.dart';

Lead _lead({String phone = '', String name = 'Rishabh Jain'}) => Lead(
  id: 'l1',
  name: name,
  phone: phone,
  email: 'rj@padmavati.in',
  company: 'Padmavati Electricals',
  status: 'New',
  assignedTo: 'u1',
  createdAt: DateTime(2026, 10, 1),
  remark: '',
  location: 'Pune',
  website: '',
);

QuotationModel _quote() => QuotationModel(
  id: 'q1',
  leadId: 'l1',
  employeeId: 'u1',
  employeeName: 'Pratyush',
  createdAt: DateTime(2026, 10, 1),
  baseRefNo: 'ATEPL/0609/2026-2027',
  currentRefNo: 'ATEPL/0609-R1/2026-2027',
  revision: 1,
  quoteRequest: const QuoteRequest(
    refNo: 'ATEPL/0609-R1/2026-2027',
    date: '01.10.2026',
    customerName: 'Mr. Sahil',
    companyName: 'Sahil Enterprises',
    location: 'Jaipur',
    email: '',
    phone: '+91 98765-43210',
    products: [
      QuoteProduct(
        productName: 'Portable Gas Detector',
        make: 'ATS',
        model: 'GD-2000',
        hsnNo: '9027',
      ),
      QuoteProduct(productName: 'Calibration Kit', model: 'CK-10'),
    ],
    termsPrices: '',
    termsPf: '',
    termsFreight: '',
    termsPayment: '',
    termsGst: '',
    termsExcise: '',
    termsValidity: '',
    termsDelivery: '',
    termsWarranty: '',
  ),
);

void main() {
  group('phoneMatches', () {
    test('ignores spaces, dashes and +91 on the stored number', () {
      expect(phoneMatches('+91 98765-43210', '9876543210'), isTrue);
      expect(phoneMatches('+91 98765-43210', '98765'), isTrue);
      expect(phoneMatches('(098765) 43210', '9876543210'), isTrue);
    });

    test('ignores +91 / leading 0 / spaces in what was typed', () {
      expect(phoneMatches('9876543210', '+91 98765 43210'), isTrue);
      expect(phoneMatches('9876543210', '09876543210'), isTrue);
      expect(phoneMatches('9876543210', '919876543210'), isTrue);
    });

    test('checks each of several stored numbers on its own', () {
      const stored = '98765 43210 / 91234 56789';
      expect(phoneMatches(stored, '9123456789'), isTrue);
      // Tail of the first + head of the second must not match.
      expect(phoneMatches(stored, '4321091234'), isFalse);
    });

    test('needs at least 3 digits and real digits', () {
      expect(phoneMatches('9876543210', '98'), isFalse);
      expect(phoneMatches('9876543210', 'abc'), isFalse);
      expect(phoneMatches('', '98765'), isFalse);
    });
  });

  group('leadMatchesSearch', () {
    test('finds a formatted number typed plainly', () {
      final lead = _lead(phone: '+91-98765 43210');
      expect(leadMatchesSearch(lead, '9876543210'), isTrue);
      expect(leadMatchesSearch(lead, '98765 43210'), isTrue);
    });

    test('still matches name, company, email', () {
      final lead = _lead();
      expect(leadMatchesSearch(lead, 'rishabh'), isTrue);
      expect(leadMatchesSearch(lead, 'PADMAVATI'), isTrue);
      expect(leadMatchesSearch(lead, 'rj@'), isTrue);
      expect(leadMatchesSearch(lead, 'nothing here'), isFalse);
      expect(leadMatchesSearch(lead, '  '), isTrue);
    });
  });

  group('quotationMatchesSearch', () {
    final q = _quote();

    test('matches product name, model, make and HSN', () {
      expect(quotationMatchesSearch(q, 'portable'), isTrue);
      expect(quotationMatchesSearch(q, 'gd-2000'), isTrue);
      expect(quotationMatchesSearch(q, 'CK-10'), isTrue);
      expect(quotationMatchesSearch(q, '9027'), isTrue);
    });

    test('every word must match somewhere', () {
      expect(quotationMatchesSearch(q, 'portable 2000'), isTrue);
      expect(quotationMatchesSearch(q, 'sahil detector'), isTrue);
      expect(quotationMatchesSearch(q, 'portable pump'), isFalse);
    });

    test('still matches ref no, company, customer and phone', () {
      expect(quotationMatchesSearch(q, '0609'), isTrue);
      expect(quotationMatchesSearch(q, 'sahil enterprises'), isTrue);
      expect(quotationMatchesSearch(q, '9876543210'), isTrue);
      expect(quotationMatchesSearch(q, '98765 43210'), isTrue);
    });
  });
}
