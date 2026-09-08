import 'package:atsleadtracker/models/quotation_model.dart';
import 'package:atsleadtracker/models/quote_request.dart';
import 'package:atsleadtracker/services/quotation_service.dart';
import 'package:flutter_test/flutter_test.dart';

QuoteRequest _quote({
  double unitPrice = 0,
  int qty = 1,
  double discount = 0,
}) {
  return QuoteRequest(
    refNo: 'ATEPL/0609/2026-2027',
    date: '07.09.2026',
    customerName: '',
    companyName: 'Tesca Technologies Pvt. Ltd.',
    location: 'Jaipur',
    email: '',
    phone: '',
    products: [QuoteProduct(productName: 'ATS-206A', quantity: qty, unitPrice: unitPrice)],
    termsPrices: '',
    termsPf: '',
    termsFreight: '',
    termsPayment: '',
    termsGst: '',
    termsExcise: '',
    termsValidity: '',
    termsDelivery: '',
    termsWarranty: '',
    discountAmount: discount,
  );
}

QuotationModel _model({
  required String id,
  required String baseRefNo,
  required int revision,
  required DateTime createdAt,
  bool hasServerCreatedAt = true,
  double unitPrice = 1000,
}) {
  return QuotationModel(
    id: id,
    leadId: 'lead-1',
    employeeId: 'emp-1',
    employeeName: 'Employee',
    createdAt: createdAt,
    baseRefNo: baseRefNo,
    currentRefNo: revision == 0 ? baseRefNo : '$baseRefNo-R$revision',
    revision: revision,
    quoteRequest: _quote(unitPrice: unitPrice),
    hasServerCreatedAt: hasServerCreatedAt,
  );
}

void main() {
  group('QuotationService.sortForLead', () {
    test('puts the highest revision of the newest group first', () {
      final quotes = [
        _model(
          id: 'r1',
          baseRefNo: 'A/0609',
          revision: 1,
          createdAt: DateTime(2026, 9, 2),
        ),
        _model(
          id: 'r3',
          baseRefNo: 'A/0609',
          revision: 3,
          createdAt: DateTime(2026, 9, 4),
        ),
        _model(
          id: 'r0',
          baseRefNo: 'A/0609',
          revision: 0,
          createdAt: DateTime(2026, 9, 1),
        ),
      ];

      final sorted = QuotationService.sortForLead(quotes);

      expect(sorted.map((q) => q.id), ['r3', 'r1', 'r0']);
    });

    test('picks the latest revision even when an older one is worth more', () {
      // A revision that lowers the price must still win — this is the
      // difference between "latest" and the old "max amount" behaviour.
      final quotes = [
        _model(
          id: 'expensive-r0',
          baseRefNo: 'A/0609',
          revision: 0,
          createdAt: DateTime(2026, 9, 1),
          unitPrice: 500000,
        ),
        _model(
          id: 'discounted-r1',
          baseRefNo: 'A/0609',
          revision: 1,
          createdAt: DateTime(2026, 9, 5),
          unitPrice: 100000,
        ),
      ];

      final latest = QuotationService.sortForLead(quotes).first;

      expect(latest.id, 'discounted-r1');
      expect(latest.quoteRequest.totalAmount, 100000);
    });

    test('newest base ref group wins over an older group', () {
      final quotes = [
        _model(
          id: 'old-r5',
          baseRefNo: 'A/0100',
          revision: 5,
          createdAt: DateTime(2026, 5, 1),
        ),
        _model(
          id: 'new-r0',
          baseRefNo: 'A/0609',
          revision: 0,
          createdAt: DateTime(2026, 9, 1),
        ),
      ];

      expect(QuotationService.sortForLead(quotes).first.id, 'new-r0');
    });

    test('a doc whose serverTimestamp has not resolved sorts newest', () {
      // createdAt fell back to DateTime.now() on the first read, so its value
      // is untrustworthy — but it was written by this client seconds ago.
      final quotes = [
        _model(
          id: 'settled',
          baseRefNo: 'A/0100',
          revision: 0,
          createdAt: DateTime(2030, 1, 1),
        ),
        _model(
          id: 'just-written',
          baseRefNo: 'A/0609',
          revision: 0,
          createdAt: DateTime(2020, 1, 1),
          hasServerCreatedAt: false,
        ),
      ];

      expect(QuotationService.sortForLead(quotes).first.id, 'just-written');
    });

    test('handles an empty list', () {
      expect(QuotationService.sortForLead([]), isEmpty);
    });
  });

  group('QuoteRequest discount', () {
    test('no discount leaves the total as the gross', () {
      final q = _quote(unitPrice: 202950);
      expect(q.grossAmount, 202950);
      expect(q.discountValue, 0);
      expect(q.totalAmount, 202950);
      expect(q.hasDiscount, isFalse);
    });

    test('subtracts the discount and reports the matching percentage', () {
      final q = _quote(unitPrice: 200000, discount: 20000);
      expect(q.grossAmount, 200000);
      expect(q.discountValue, 20000);
      expect(q.totalAmount, 180000);
      expect(q.discountPercent, 10);
      expect(q.hasDiscount, isTrue);
    });

    test('never discounts below zero', () {
      final q = _quote(unitPrice: 1000, discount: 5000);
      expect(q.discountValue, 1000);
      expect(q.totalAmount, 0);
    });

    test('a negative discount is ignored', () {
      final q = _quote(unitPrice: 1000, discount: -500);
      expect(q.discountValue, 0);
      expect(q.totalAmount, 1000);
    });

    test('survives a JSON round trip', () {
      final q = _quote(unitPrice: 200000, discount: 15000);
      final restored = QuoteRequest.fromJson(q.toJson());
      expect(restored.discountAmount, 15000);
      expect(restored.totalAmount, 185000);
    });

    test('a legacy quote with no discount field reads as undiscounted', () {
      final json = _quote(unitPrice: 50000).toJson()..remove('discountAmount');
      final restored = QuoteRequest.fromJson(json);
      expect(restored.discountAmount, 0);
      expect(restored.totalAmount, 50000);
    });
  });
}
