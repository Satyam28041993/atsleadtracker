import 'package:atsleadtracker/models/lead_model.dart';
import 'package:atsleadtracker/models/quotation_model.dart';
import 'package:atsleadtracker/models/quote_request.dart';
import 'package:atsleadtracker/services/analytics_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

Lead _lead({
  String id = 'lead-1',
  String status = 'Proposal',
  double amount = 0,
}) {
  final now = DateTime(2026, 9, 1);
  return Lead(
    id: id,
    name: 'Contact',
    phone: '9999999999',
    email: '',
    company: 'Tesca Technologies Pvt. Ltd.',
    status: status,
    assignedTo: 'uid',
    createdAt: now,
    remark: '',
    location: '',
    website: '',
    lastModified: now,
    totalAmount: amount,
  );
}

QuotationModel _quote({
  String leadId = 'lead-1',
  int revision = 0,
  double unitPrice = 100000,
  double discount = 0,
  DateTime? createdAt,
}) {
  return QuotationModel(
    id: 'q$revision',
    leadId: leadId,
    employeeId: 'uid',
    employeeName: 'Employee',
    createdAt: createdAt ?? DateTime(2026, 9, revision + 1),
    baseRefNo: 'ATEPL/0609/2026-2027',
    currentRefNo: revision == 0
        ? 'ATEPL/0609/2026-2027'
        : 'ATEPL/0609-R$revision/2026-2027',
    revision: revision,
    quoteRequest: QuoteRequest(
      refNo: 'ATEPL/0609/2026-2027',
      date: '01.09.2026',
      customerName: '',
      companyName: 'Tesca',
      location: '',
      email: '',
      phone: '',
      products: [
        QuoteProduct(productName: 'Analyzer', quantity: 1, unitPrice: unitPrice),
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
      discountAmount: discount,
    ),
  );
}

void main() {
  group('effectiveAmount', () {
    test('prefers the lead Amount column when it is set', () {
      final lead = _lead(amount: 250000);
      final amount = AnalyticsExportService.effectiveAmount(lead, {
        'lead-1': _quote(unitPrice: 999999),
      });
      expect(amount, 250000);
      expect(
        AnalyticsExportService.amountSourceFor(lead, {'lead-1': _quote()}),
        AmountSource.leadColumn,
      );
    });

    test('falls back to the quotation when the lead has no Amount', () {
      final lead = _lead();
      final quotes = {'lead-1': _quote(unitPrice: 202950)};
      expect(
        AnalyticsExportService.effectiveAmount(lead, quotes),
        202950,
      );
      expect(
        AnalyticsExportService.amountSourceFor(lead, quotes),
        AmountSource.quotationFallback,
      );
    });

    test('reports no value when there is neither', () {
      final lead = _lead();
      expect(AnalyticsExportService.effectiveAmount(lead, const {}), 0);
      expect(
        AnalyticsExportService.amountSourceFor(lead, const {}),
        AmountSource.none,
      );
    });

    test('the fallback honours a discount on the quotation', () {
      final quotes = {'lead-1': _quote(unitPrice: 200000, discount: 20000)};
      expect(
        AnalyticsExportService.effectiveAmount(_lead(), quotes),
        180000,
      );
    });

    test('a zero-amount quotation is not treated as a value', () {
      final quotes = {'lead-1': _quote(unitPrice: 0)};
      expect(
        AnalyticsExportService.amountSourceFor(_lead(), quotes),
        AmountSource.none,
      );
    });
  });

  group('lead classification', () {
    test('closed covers every closed spelling, open does not', () {
      for (final s in ['Won', 'Lost', 'Loss', 'Disqualified', 'won', 'LOSS']) {
        expect(AnalyticsExportService.isClosed(_lead(status: s)), isTrue,
            reason: s);
      }
      for (final s in ['New', 'Contacted', 'Proposal', 'Follow-up']) {
        expect(AnalyticsExportService.isClosed(_lead(status: s)), isFalse,
            reason: s);
      }
    });

    test('isWon matches only Won', () {
      expect(AnalyticsExportService.isWon(_lead(status: 'Won')), isTrue);
      expect(AnalyticsExportService.isWon(_lead(status: 'Lost')), isFalse);
      expect(AnalyticsExportService.isWon(_lead(status: 'Proposal')), isFalse);
    });
  });

  group('buildWorkbook', () {
    test('produces a workbook covering leads, wins and the value gaps', () {
      final leads = [
        _lead(id: 'won-valued', status: 'Won', amount: 500000),
        _lead(id: 'won-blank', status: 'Won'),
        _lead(id: 'open-blank', status: 'Proposal'),
        _lead(id: 'open-quoted', status: 'Proposal'),
      ];
      final quotes = {'open-quoted': _quote(leadId: 'open-quoted')};

      // A won lead with no value is exactly the case that silently understates
      // Won revenue and drags the average down.
      expect(
        AnalyticsExportService.effectiveAmount(leads[1], quotes),
        0,
      );
      expect(
        AnalyticsExportService.amountSourceFor(leads[3], quotes),
        AmountSource.quotationFallback,
      );
    });
  });
}
