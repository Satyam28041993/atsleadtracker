import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:atsleadtracker/models/lead_model.dart';
import 'package:atsleadtracker/models/quote_request.dart';
import 'package:atsleadtracker/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Generate PDF Quote and write to disk', () async {
    print('Starting PDF generation test inside Flutter context...');
    
    final lead = Lead(
      id: '1',
      name: 'John Doe',
      company: 'Applied Techno Engineers Pvt. Ltd.',
      phone: '9899453080',
      email: 'works@puretronics.com',
      location: 'Mumbai',
      requirement: 'Portable Flue Gas Analyzer',
      modelNo: 'ATS-206A',
      source: 'Direct',
      status: 'New',
      createdAt: DateTime.now(),
      assignedTo: 'Admin',
      remark: 'Test ATEPL Quote',
      website: 'www.at-epl.com',
    );

    final quote = QuoteRequest(
      companyType: 'ATEPL',
      refNo: 'ATEPL/0123/2026-2027',
      date: '19.06.2026',
      customerName: 'John Doe',
      companyName: 'Applied Techno Engineers Pvt. Ltd.',
      location: 'Mumbai, Maharashtra',
      email: 'works@puretronics.com',
      phone: '9899453080',
      products: [
        QuoteProduct(
          productName: 'Portable Flue Gas Analyzer (State - GAS)',
          make: 'ATS',
          model: 'ATS-206A',
          hsnNo: '90271000',
          parametersMeasured: 'O2,EC,0-25.0%vol,0.1%vol\nCO,NDIR,0-1000PPM,1PPM\nCO2,NDIR,0-100%vol,0.1%vol\nNOx,EC,0-5000PPM,1PPM\nSO2,EC,0-10000PPM,1PPM\nTemp,Tc,0-450°C,1°C',
          productOverview: 'The Portable Flue Gas Analyzer is a compact and rugged instrument designed for combustion efficiency analysis and emissions monitoring in boilers, furnaces, engines, heaters, and industrial combustion systems. Utilizing advanced electrochemical sensor technology, the analyzer provides accurate measurement of oxygen (O2), carbon monoxide (CO), carbon dioxide (CO2), nitric oxide (NO), nitrogen dioxide (NO2), sulfur dioxide (SO2), and flue gas temperature for efficient combustion control and environmental compliance.',
          keyFeatures: 'Simultaneous Multi-Gas Measurement\nHigh Accuracy Electrochemical Sensors\nBuilt-in Sample Pump and Condensate Trap\nLarge Color TFT LCD Display\nRechargeable Lithium-Ion Battery\nCombustion Efficiency Calculation\nData Logging and USB Interface\nBuilt-in Thermal Printer (Optional)\nAutomatic Zero Calibration\nRugged Portable Construction',
          specification: 'Accuracy ±2% of Reading\nResponse Time (T90) <30 Seconds\nDisplay 128 x 64 Graphics LCD\nSample Pump Built-in Diaphragm Pump\nFlow Rate Approx. 1 LPM\nTemperature Measurement 0-1,200°C\nPressure Measurement ±100 mbar\nDraft Measurement ±100 mbar\nCombustion Efficiency Calculation Automatic\nData Storage Capacity Up to 50,000 Records\nCommunication Interface USB / RS-232\nBattery Type Rechargeable Lithium-Ion\nBattery Backup Up to 10 Hours\nOperating Temperature 0°C to 50°C\nHumidity <95% RH (Non-Condensing)\nDimensions 300 x 250 x 120 mm\nWeight Approx. 3.0 kg',
          accessories: 'Flue Gas Probe with Thermocouple\nCondensate Trap and Filter Assembly\nUSB Communication Cable\nCharger',
          documentAndCertificate: '',
          quantity: 1,
          unitPrice: 375000,
          srNo: '1.',
        ),
      ],
      additionalItems: const [],
      termsPrices: 'Ex-Works',
      termsPf: '2%',
      termsFreight: '2%',
      termsPayment: '40% advance',
      termsGst: '18%',
      termsExcise: 'Nil',
      termsValidity: '90 days',
      termsDelivery: '2 weeks',
      termsWarranty: '1 year',
      terms: [
        QuoteTerm(key: 'Prices', value: 'Ex-Works, Mumbai'),
        QuoteTerm(key: 'P&F', value: 'Nil'),
        QuoteTerm(key: 'Freight', value: 'Extra at actual.'),
        QuoteTerm(key: 'Payment', value: '100% Advance'),
        QuoteTerm(key: 'GST', value: '18% Extra'),
        QuoteTerm(key: 'GST No', value: '27AAVCA1127G1ZN'),
        QuoteTerm(key: 'Excise', value: 'Nil'),
        QuoteTerm(key: 'Validity', value: '90 days'),
        QuoteTerm(key: 'Delivery', value: '1 Weeks'),
        QuoteTerm(key: 'Warranty', value: 'One year.'),
      ],
    );

    final pdfService = PdfService();
    final bytes = await pdfService.generateQuoteData(lead, quote);
    
    final file = File('test_quote.pdf');
    await file.writeAsBytes(bytes);
    print('SUCCESS: Saved generated PDF to ${file.absolute.path}');
  });
}
