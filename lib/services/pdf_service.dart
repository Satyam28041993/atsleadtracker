import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/lead_model.dart';
import '../models/quote_request.dart';
import '../utils/pdf_text_normalize.dart';

class PdfService {
  static pw.Font? _cachedBaseFont;
  static pw.Font? _cachedBoldFont;
  static pw.Font? _cachedAtsSans;
  static pw.Font? _cachedAtsSansBold;
  static pw.Font? _cachedAtsSerif;
  static pw.Font? _cachedAtsSerifBold;
  static pw.Font? _cachedAtsMonoBold;

  static Future<(pw.Font base, pw.Font bold)> _loadQuotePdfFonts() async {
    if (_cachedBaseFont != null && _cachedBoldFont != null) {
      return (_cachedBaseFont!, _cachedBoldFont!);
    }

    try {
      final regular = await rootBundle.load(
        'Assets/fonts/NotoSans-Regular.ttf',
      );
      final bold = await rootBundle.load('Assets/fonts/NotoSans-Bold.ttf');
      _cachedBaseFont = pw.Font.ttf(regular);
      _cachedBoldFont = pw.Font.ttf(bold);
      return (_cachedBaseFont!, _cachedBoldFont!);
    } catch (e) {
      debugPrint(
        'PDF fonts missing ($e). Stop flutter run and start again after pubspec '
        'asset changes. Falling back to Helvetica.',
      );
      _cachedBaseFont = pw.Font.helvetica();
      _cachedBoldFont = pw.Font.helveticaBold();
      return (_cachedBaseFont!, _cachedBoldFont!);
    }
  }

  static Future<
    (
      pw.Font sans,
      pw.Font sansBold,
      pw.Font serif,
      pw.Font serifBold,
      pw.Font monoBold,
    )
  >
  _loadAtsPdfFonts() async {
    if (_cachedAtsSans != null &&
        _cachedAtsSansBold != null &&
        _cachedAtsSerif != null &&
        _cachedAtsSerifBold != null &&
        _cachedAtsMonoBold != null) {
      return (
        _cachedAtsSans!,
        _cachedAtsSansBold!,
        _cachedAtsSerif!,
        _cachedAtsSerifBold!,
        _cachedAtsMonoBold!,
      );
    }

    try {
      final sans = await rootBundle.load('Assets/fonts/ats/Arial.ttf');
      final sansBold = await rootBundle.load('Assets/fonts/ats/Arial-Bold.ttf');
      final serif = await rootBundle.load('Assets/fonts/ats/Calibri.ttf');
      final serifBold = await rootBundle.load(
        'Assets/fonts/ats/Calibri-Bold.ttf',
      );
      final monoBold = await rootBundle.load(
        'Assets/fonts/ats/CourierNew-Bold.ttf',
      );
      _cachedAtsSans = pw.Font.ttf(sans);
      _cachedAtsSansBold = pw.Font.ttf(sansBold);
      _cachedAtsSerif = pw.Font.ttf(serif);
      _cachedAtsSerifBold = pw.Font.ttf(serifBold);
      _cachedAtsMonoBold = pw.Font.ttf(monoBold);
    } catch (e) {
      debugPrint('ATS PDF font load failed ($e), falling back to core fonts.');
      _cachedAtsSans = pw.Font.helvetica();
      _cachedAtsSansBold = pw.Font.helveticaBold();
      _cachedAtsSerif = pw.Font.times();
      _cachedAtsSerifBold = pw.Font.timesBold();
      _cachedAtsMonoBold = pw.Font.courierBold();
    }

    return (
      _cachedAtsSans!,
      _cachedAtsSansBold!,
      _cachedAtsSerif!,
      _cachedAtsSerifBold!,
      _cachedAtsMonoBold!,
    );
  }

  Future<Uint8List> generateQuoteData(
    Lead lead,
    QuoteRequest quote, {
    String? creatorMobile,
    String? creatorName,
  }) async {
    quote = normalizeQuoteRequestForPdf(quote);
    final pdf = pw.Document();
    final (baseFont, boldFont) = await _loadQuotePdfFonts();
    final (atsSans, atsSansBold, atsSerif, atsSerifBold, atsMonoBold) =
        await _loadAtsPdfFonts();

    final isAts = quote.companyType == 'ATS';
    // ATS uses the single combined lockup (globe + wordmark) so the letterhead
    // matches the printed original exactly. Drawing the globe and setting the
    // words in a font left the two mis-registered against each other.
    final logoPath = isAts ? _atsHeaderLockupAsset : 'Assets/Logo/Logo.png';
    final logoData = await rootBundle.load(logoPath);
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());

    final signatureData = await rootBundle.load(
      'Assets/digital_signature.jpeg',
    );
    final signature = pw.MemoryImage(signatureData.buffer.asUint8List());

    // Pre-load every product image (multiple products supported).
    final productImages = <int, pw.ImageProvider>{};
    for (var i = 0; i < quote.products.length; i++) {
      final url = quote.products[i].productImageUrl;
      if (url.isEmpty) continue;
      try {
        productImages[i] = await networkImage(
          url,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }

    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: isAts
          ? const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 16)
          : const pw.EdgeInsets.all(32),
      buildBackground: (context) {
        if (isAts) {
          return pw.FullPage(
            ignoreMargins: true,
            child: pw.Center(
              child: pw.Transform.rotate(
                angle: -0.5,
                child: pw.Opacity(
                  opacity: 0.08,
                  child: pw.Text(
                    'ATS',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 180,
                      color: PdfColor.fromHex('#C2272D'),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return pw.FullPage(
          ignoreMargins: true,
          child: pw.Center(
            child: pw.Opacity(opacity: 0.12, child: pw.Image(logo, width: 450)),
          ),
        );
      },
    );

    if (isAts) {
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pageTheme,
          header: (context) => _buildTopHeader(
            logo,
            baseFont,
            boldFont,
            quote.companyType,
            atsMonoBold: atsMonoBold,
          ),
          footer: (context) =>
              _buildFooterBanner(baseFont, boldFont, quote.companyType),
          build: (context) {
            final empName = creatorName != null && creatorName.isNotEmpty
                ? creatorName
                : 'Mrs. Pratima.';
            final empMobile = creatorMobile != null && creatorMobile.isNotEmpty
                ? creatorMobile
                : '08010915931';
            return [
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'REF: ${quote.refNo}',
                    style: pw.TextStyle(
                      font: atsSansBold,
                      fontSize: 10.6,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.Text(
                    'Date: ${quote.date}',
                    style: pw.TextStyle(
                      font: atsSansBold,
                      fontSize: 10.6,
                      color: PdfColors.black,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              _buildRecipientBlock(
                quote,
                baseFont,
                boldFont,
                quote.companyType,
                atsSerifBold: atsSerifBold,
              ),
              pw.SizedBox(height: 10),
              ..._buildCommercialSection(
                quote,
                baseFont,
                boldFont,
                companyType: quote.companyType,
                atsBodyFont: atsSerif,
                atsBodyBoldFont: atsSerifBold,
                atsTableHeaderFont: atsSansBold,
                productImages: productImages,
              ),
              pw.SizedBox(height: 8),
              _buildAtsTermsLayout(
                quote,
                baseFont,
                boldFont,
                creatorName,
                creatorMobile,
                atsSerif: atsSerif,
                atsSerifBold: atsSerifBold,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Hope the above meets with your requirement; meanwhile should you require any further information or any clarification please feel free to contact the undersigned. We will be more than pleased to provide any help required.',
                style: pw.TextStyle(
                  font: atsSerif,
                  fontSize: 11.5,
                  color: PdfColors.black,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Yours faithfully',
                style: pw.TextStyle(
                  font: atsSerif,
                  fontSize: 11.5,
                  color: PdfColors.black,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'For Applied Techno Systems',
                style: pw.TextStyle(
                  font: atsSerifBold,
                  fontSize: 11.5,
                  color: PdfColors.black,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                empName,
                style: pw.TextStyle(
                  font: atsSerif,
                  fontSize: 11.5,
                  color: PdfColors.black,
                ),
              ),
              pw.Text(
                empMobile,
                style: pw.TextStyle(
                  font: atsSerif,
                  fontSize: 11.5,
                  color: PdfColors.black,
                ),
              ),
            ];
          },
        ),
      );
    } else {
      final firstProduct = quote.products.isNotEmpty
          ? quote.products.first
          : const QuoteProduct(productName: '');

      // Page 1: Introduction Letter. Keep this static first page compact so the
      // signatory stamp stays with the introduction; product growth starts later.
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pageTheme,
          header: (context) => _buildTopHeader(
            logo,
            baseFont,
            boldFont,
            quote.companyType,
            atsMonoBold: atsMonoBold,
          ),
          footer: (context) =>
              _buildFooterBanner(baseFont, boldFont, quote.companyType),
          build: (context) {
            return [
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'REF: ${quote.refNo}',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 9,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                  pw.Text(
                    'Date: ${quote.date}',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 9,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              _buildRecipientBlock(
                quote,
                baseFont,
                boldFont,
                quote.companyType,
              ),
              pw.SizedBox(height: 8),
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'Quotation',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 12,
                    decoration: pw.TextDecoration.underline,
                    color: PdfColors.blueGrey900,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Dear Customer,',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 8.8,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'We thank you very much for the kind courtesy extended to Mr. ${quote.customerName.trim().isNotEmpty ? quote.customerName.trim() : 'Praveen Singh'} during the telephonic conversation. As discussed, we are glad to extend our quotation for ${firstProduct.productName.trim().isNotEmpty ? firstProduct.productName.trim() : 'Oxygen Analyzer'} Model ${firstProduct.model.trim().isNotEmpty ? firstProduct.model.trim() : 'ATS 208A'}.',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 8.6,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Please find enclosed the following:-',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 8.8,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 14, top: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildBulletPoint('Introduction', baseFont, 8),
                    _buildBulletPoint('Techno-Commercial Offer', baseFont, 8),
                    _buildBulletPoint('Product Catalogue', baseFont, 8),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'We have reviewed your requirement and we trust that our offer meet your technical specifications, we are waiting for your approval and look forward to a long and successful association with your Organization.',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 8.6,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'We use emerging technologies and customized cutting edge solutions to best fit the instrument to the application. With qualified and experienced electronics and instrumentation engineers we are committed to R&D and innovation in our products to cater to the clients need.',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 8.6,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 8),
              _buildOverviewTable(baseFont, boldFont, compact: true),
              pw.SizedBox(height: 7),
              pw.Text(
                'May you need any additional information or clarifications, please feel free to contact us.\nThanking you in anticipation.\nRegards,',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 8.2,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Applied Techno Engineers Pvt. Ltd.',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 8.6,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Image(signature, width: 46, height: 46),
              pw.SizedBox(height: 2),
              pw.Text(
                'Authorized Signatory',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ];
          },
        ),
      );

      // Page 2+: Commercial Table (MultiPage => flows across pages automatically)
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pageTheme,
          header: (context) => _buildTopHeader(
            logo,
            baseFont,
            boldFont,
            quote.companyType,
            atsMonoBold: atsMonoBold,
          ),
          footer: (context) =>
              _buildFooterBanner(baseFont, boldFont, quote.companyType),
          build: (context) {
            return [
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'REF: ${quote.refNo}',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 9.5,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                  pw.Text(
                    'Date: ${quote.date}',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 9.5,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              _buildRecipientBlock(
                quote,
                baseFont,
                boldFont,
                quote.companyType,
              ),
              pw.SizedBox(height: 18),
              ..._buildCommercialSection(
                quote,
                baseFont,
                boldFont,
                companyType: quote.companyType,
                productImages: productImages,
              ),
            ];
          },
        ),
      );

      // Last page(s): Terms and Conditions
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pageTheme,
          header: (context) => _buildTopHeader(
            logo,
            baseFont,
            boldFont,
            quote.companyType,
            atsMonoBold: atsMonoBold,
          ),
          footer: (context) =>
              _buildFooterBanner(baseFont, boldFont, quote.companyType),
          build: (context) {
            return [
              pw.SizedBox(height: 10),
              pw.Text(
                'COMMERCIAL TERMS AND CONDITION',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 11,
                  decoration: pw.TextDecoration.underline,
                  color: PdfColor.fromHex('#C2272D'),
                ),
              ),
              pw.SizedBox(height: 10),
              _buildTermsBox(quote, baseFont, boldFont),
              pw.SizedBox(height: 18),
              pw.Text(
                'Hope the above meets with your requirement; meanwhile should you require any further information or any clarification please feel free to contact the undersigned. We will be more than pleased to provide any help required.',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 9.5,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Yours faithfully\nFor Applied Techno Engineers Pvt. Ltd.',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 10,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Image(signature, width: 60, height: 60),
              pw.SizedBox(height: 4),
              pw.Text(
                '${creatorMobile != null && creatorMobile.isNotEmpty ? creatorMobile : '8010915931'}/8652226750',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 10,
                  color: PdfColors.blueGrey800,
                ),
              ),
            ];
          },
        ),
      );
    }

    return pdf.save();
  }

  static pw.Widget _buildAtsTermsLayout(
    QuoteRequest quote,
    pw.Font baseFont,
    pw.Font boldFont,
    String? creatorName,
    String? creatorMobile, {
    required pw.Font atsSerif,
    required pw.Font atsSerifBold,
  }) {
    final empName = creatorName != null && creatorName.isNotEmpty
        ? creatorName
        : 'Mrs. Pratima.';
    final empMobile = creatorMobile != null && creatorMobile.isNotEmpty
        ? creatorMobile
        : '08010915931';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'TERMS & CONDITIONS',
          style: pw.TextStyle(
            font: atsSerifBold,
            fontSize: 11,
            color: PdfColors.black,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 170,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4, right: 10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Thanking You,',
                      style: pw.TextStyle(font: atsSerif, fontSize: 11),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Yours faithfully,',
                      style: pw.TextStyle(font: atsSerif, fontSize: 11),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'For M/s. Applied Techno Systems',
                      style: pw.TextStyle(font: atsSerif, fontSize: 11),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                      empName,
                      style: pw.TextStyle(font: atsSerif, fontSize: 11),
                    ),
                    pw.Text(
                      empMobile,
                      style: pw.TextStyle(font: atsSerif, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 0.8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'TERMS & CONDITIONS :',
                      style: pw.TextStyle(
                        font: atsSerifBold,
                        fontSize: 11,
                        color: PdfColors.black,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    for (var i = 0; i < quote.terms.length; i++) ...[
                      _buildTermRow(
                        '${i + 1}. ${quote.terms[i].key}',
                        quote.terms[i].value,
                        atsSerif,
                        atsSerif,
                        fontSize: 10.5,
                        keyWidth: 70,
                      ),
                      if (i < quote.terms.length - 1) pw.SizedBox(height: 2),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Logo + company info header, with the red divider, used as the repeating
  // ── ATS letterhead lockup (globe + wordmark) ───────────────────────────
  //
  // Two artworks exist and they are NOT the same shape, so the path and the
  // aspect below must always be swapped together:
  //
  //   ats_header_lockup.png        246x32   compact wordmark (from the
  //                                         supplied "logo Header.png").
  //                                         Only 246px wide, so it starts
  //                                         looking soft in print past ~380pt.
  //   ats_header_lockup_hires.png  1931x167 same globe, but the wordmark is
  //                                         spaced about twice as wide. Lifted
  //                                         from the client's own letterhead,
  //                                         so it stays crisp at any width
  //                                         this page can give it.
  static const String _atsHeaderLockupAsset =
      'Assets/Logo/ats_header_lockup_hires.png';
  static const double _atsHeaderLockupAspect = 1931 / 167;

  /// Drawn width in PDF points, centred in the 531pt content column.
  static const double _atsHeaderLockupWidth = 380;

  /// `pw.Image` falls back to the artwork's pixel size when only one dimension
  /// is given, so both are passed. `BoxFit.contain` then letterboxes rather
  /// than stretches if [_atsHeaderLockupAspect] ever drifts from the asset.
  static const double _atsHeaderLockupHeight =
      _atsHeaderLockupWidth / _atsHeaderLockupAspect;

  /// header on every page (MultiPage repeats this automatically on overflow).
  static pw.Widget _buildTopHeader(
    pw.ImageProvider logo,
    pw.Font baseFont,
    pw.Font boldFont,
    String companyType, {
    pw.Font? atsMonoBold,
  }) {
    if (companyType == 'ATS') {
      return _buildPageHeader(
        logo,
        baseFont,
        boldFont,
        companyType,
        atsMonoBold: atsMonoBold,
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildPageHeader(logo, baseFont, boldFont, companyType),
        pw.Divider(color: PdfColor.fromHex('#C2272D'), thickness: 1.2),
      ],
    );
  }

  static pw.Widget _buildPageHeader(
    pw.ImageProvider logo,
    pw.Font baseFont,
    pw.Font boldFont,
    String companyType, {
    pw.Font? atsMonoBold,
  }) {
    if (companyType == 'ATS') {
      final safeAtsMonoBold = atsMonoBold ?? pw.Font.courierBold();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // One artwork, not an image beside styled text — the wordmark keeps
          // its own spacing and weight. Centred to sit over the ISO and
          // address lines below, which are centred too.
          pw.Center(
            child: pw.Image(
              logo,
              width: _atsHeaderLockupWidth,
              height: _atsHeaderLockupHeight,
              fit: pw.BoxFit.contain,
            ),
          ),
          pw.SizedBox(height: 2.5),
          pw.Divider(color: PdfColors.black, thickness: 1.6),
          pw.SizedBox(height: 3),
          pw.Text(
            'AN ISO 9001:2015 Certified Company',
            style: pw.TextStyle(
              font: safeAtsMonoBold,
              fontSize: 18,
              color: PdfColor.fromHex('#660099'),
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 1.5),
          pw.Text(
            'Reg Off : 104,Delta Industrial Estate,Building No.1,Bhoidapada,Ghokivare,Sativali Road,Vasai(E)Thane-401208',
            style: pw.TextStyle(
              font: safeAtsMonoBold,
              fontSize: 11.8,
              color: PdfColors.black,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Image(logo, width: 62, height: 62, fit: pw.BoxFit.contain),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Applied Techno Engineers Pvt. Ltd.',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 20,
                  color: PdfColor.fromHex('#C2272D'),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'A/104, Delta Industrial Estate, Building No.1, Bhoidapada, Sativali Road,\nVasai East (Thane), Dist-Palghar, Maharashtra. Pincode: 401208.',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 8,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Text(
                    'Email: ',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 8,
                      color: PdfColor.fromHex('#C2272D'),
                    ),
                  ),
                  pw.Text(
                    'sales@at-epl.com | info@at-epl.com',
                    style: pw.TextStyle(
                      font: baseFont,
                      fontSize: 8,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Text(
                    'Phone: ',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 8,
                      color: PdfColor.fromHex('#C2272D'),
                    ),
                  ),
                  pw.Text(
                    '+91 8652226750 | 7767048603',
                    style: pw.TextStyle(
                      font: baseFont,
                      fontSize: 8,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'GST NO. 27AAVCA1127G1ZN | CIN : U29309MH2021PTC359067',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 8,
                  color: PdfColors.blueGrey800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildRecipientBlock(
    QuoteRequest quote,
    pw.Font baseFont,
    pw.Font boldFont,
    String companyType, {
    pw.Font? atsSerifBold,
  }) {
    if (companyType == 'ATS') {
      final atsRecipientBlue = PdfColor.fromHex('#2F5496');
      final safeAtsSerifBold = atsSerifBold ?? pw.Font.timesBold();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'M/S. ${quote.companyName}',
            style: pw.TextStyle(
              font: safeAtsSerifBold,
              fontSize: 12,
              color: atsRecipientBlue,
            ),
          ),
          pw.Text(
            quote.location,
            style: pw.TextStyle(
              font: safeAtsSerifBold,
              fontSize: 12,
              color: atsRecipientBlue,
            ),
          ),
          pw.Text(
            'Email Id - ${quote.email}',
            style: pw.TextStyle(
              font: safeAtsSerifBold,
              fontSize: 12,
              color: atsRecipientBlue,
            ),
          ),
          pw.Text(
            'Mobile - ${quote.phone}',
            style: pw.TextStyle(
              font: safeAtsSerifBold,
              fontSize: 12,
              color: atsRecipientBlue,
            ),
          ),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'M/S. ${quote.companyName}',
          style: pw.TextStyle(
            font: boldFont,
            fontSize: 10,
            color: PdfColors.blueGrey900,
          ),
        ),
        pw.Text(
          quote.location,
          style: pw.TextStyle(
            font: baseFont,
            fontSize: 9.5,
            color: PdfColors.blueGrey800,
          ),
        ),
        pw.Text(
          'Email Id- ${quote.email}',
          style: pw.TextStyle(
            font: baseFont,
            fontSize: 9.5,
            color: PdfColors.blueGrey800,
          ),
        ),
        pw.Text(
          'Mobile: ${quote.phone}',
          style: pw.TextStyle(
            font: baseFont,
            fontSize: 9.5,
            color: PdfColors.blueGrey800,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildOverviewTable(
    pw.Font baseFont,
    pw.Font boldFont, {
    bool compact = false,
  }) {
    final headerPadding = compact
        ? const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 3)
        : const pw.EdgeInsets.all(5);
    final headerFontSize = compact ? 7.2 : 8.5;
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1.2),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: headerPadding,
              child: pw.Text(
                'Products',
                style: pw.TextStyle(font: boldFont, fontSize: headerFontSize),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: headerPadding,
              child: pw.Text(
                'Clients',
                style: pw.TextStyle(font: boldFont, fontSize: headerFontSize),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: headerPadding,
              child: pw.Text(
                'Applications',
                style: pw.TextStyle(font: boldFont, fontSize: headerFontSize),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
        ),
        // Rows
        _buildOverviewRow(
          'GAS Detectors',
          'Process Industries',
          'Ambient Air Pollution Monitoring',
          baseFont,
          compact: compact,
        ),
        _buildOverviewRow(
          'GAS Analyzers',
          'Chemical & Pharmaceutical',
          'Industrial Hygiene & Safety',
          baseFont,
          compact: compact,
        ),
        _buildOverviewRow(
          'Flue/Stack Gas Analyser',
          'Power Plants',
          'Stack Emission/ Source Emission',
          baseFont,
          compact: compact,
        ),
        _buildOverviewRow(
          'Dust Particulate Monitors',
          'Petrochemical and Oil industries',
          'Quality Control',
          baseFont,
          compact: compact,
        ),
        _buildOverviewRow(
          'Opacity Monitors',
          'Oil & Gas',
          'Research and Development',
          baseFont,
          compact: compact,
        ),
        _buildOverviewRow(
          'Dew Point/ Moisture Analyzer',
          'Defense Laboratories',
          'Flame/ Fire/ Smoke Detection',
          baseFont,
          compact: compact,
        ),
        _buildOverviewRow(
          'Dust Guard',
          'Transport & Retail Industries',
          'Moisture/ Dew-Point & Velocity',
          baseFont,
          compact: compact,
        ),
        _buildOverviewRow(
          'Solid Flow / Broken Bag Detectors',
          'Original Equipment Manufacturer',
          'Process Analysis',
          baseFont,
          compact: compact,
        ),
        _buildOverviewRow(
          'Energy Monitoring System',
          'Telecom Industries',
          '',
          baseFont,
          compact: compact,
        ),
        _buildOverviewRow(
          'Web Data Acquisition Systems',
          'Healthcare Industries',
          '',
          baseFont,
          compact: compact,
        ),
      ],
    );
  }

  static pw.TableRow _buildOverviewRow(
    String prod,
    String client,
    String app,
    pw.Font baseFont, {
    bool compact = false,
  }) {
    final padding = compact
        ? const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3)
        : const pw.EdgeInsets.all(4);
    final fontSize = compact ? 6.7 : 8.0;
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: padding,
          child: pw.Text(
            prod,
            style: pw.TextStyle(font: baseFont, fontSize: fontSize),
          ),
        ),
        pw.Padding(
          padding: padding,
          child: pw.Text(
            client,
            style: pw.TextStyle(font: baseFont, fontSize: fontSize),
          ),
        ),
        pw.Padding(
          padding: padding,
          child: pw.Text(
            app,
            style: pw.TextStyle(font: baseFont, fontSize: fontSize),
          ),
        ),
      ],
    );
  }

  static List<pw.TableRow> _buildProductDetailRows(
    QuoteProduct product,
    int srNo,
    pw.Font baseFont,
    pw.Font boldFont,
  ) {
    final detailRows = <pw.TableRow>[];
    final detailWidgets = <pw.Widget>[];

    // 1. Header: "Item $srNo - Technical Details"
    final displaySr = product.srNo.isNotEmpty ? product.srNo : '$srNo';
    detailWidgets.add(
      pw.Text(
        'Item $displaySr - Technical Details',
        style: pw.TextStyle(
          font: boldFont,
          fontSize: 9,
          decoration: pw.TextDecoration.underline,
          color: PdfColors.blueGrey900,
        ),
      ),
    );

    // Helper to extract bullet points
    List<pw.Widget> getBulletWidgets(String title, String text) {
      final lines = text.split('\n').where((s) => s.trim().isNotEmpty).toList();
      if (lines.isEmpty) return const [];
      final list = <pw.Widget>[];
      list.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            title,
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 8.5,
              decoration: pw.TextDecoration.underline,
              color: PdfColors.blueGrey900,
            ),
          ),
        ),
      );
      for (final line in lines) {
        final cleanLine = stripLeadingBulletPrefix(line);
        list.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3, left: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 4, right: 6),
                  width: 3,
                  height: 3,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blueGrey900,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    cleanLine,
                    style: pw.TextStyle(
                      font: baseFont,
                      fontSize: 8,
                      color: PdfColors.blueGrey800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return list;
    }

    // 2. Product Overview
    if (product.productOverview.trim().isNotEmpty) {
      detailWidgets.addAll(
        getBulletWidgets('Product Overview:', product.productOverview),
      );
    }

    // 3. Key Feature
    if (product.keyFeatures.trim().isNotEmpty) {
      detailWidgets.addAll(
        getBulletWidgets('Key Feature:', product.keyFeatures),
      );
    }

    // 4. Technical Specification
    if (product.specification.trim().isNotEmpty) {
      detailWidgets.addAll(
        getBulletWidgets('Technical Specification:', product.specification),
      );
    }

    // 5. Parameter Measured
    if (product.parametersMeasured.isNotEmpty) {
      detailWidgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'Parameter Measured :',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 8.5,
              color: PdfColors.blueGrey900,
            ),
          ),
        ),
      );
      detailWidgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: _buildParametersTable(
            product.parametersMeasured,
            baseFont,
            boldFont,
          ),
        ),
      );
    }

    // 6. Accessories
    if (product.accessories.trim().isNotEmpty) {
      detailWidgets.addAll(
        getBulletWidgets('Accessories:', product.accessories),
      );
    }

    // 7. Document and Certificate
    if (product.documentAndCertificate.trim().isNotEmpty) {
      detailWidgets.addAll(
        getBulletWidgets(
          'Document and Certificate:',
          product.documentAndCertificate,
        ),
      );
    }

    // Wrap each detail widget inside its own TableRow!
    for (var i = 0; i < detailWidgets.length; i++) {
      detailRows.add(
        pw.TableRow(
          children: [
            pw.Text(''), // Cell 0: SR. NO. (blank)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 2,
                horizontal: 6,
              ),
              child: detailWidgets[i],
            ), // Cell 1: DESCRIPTION
            pw.Text(''), // Cell 2: QTY (blank)
            pw.Text(''), // Cell 3: UNIT RATE (blank)
            pw.Text(''), // Cell 4: AMOUNT (blank)
          ],
        ),
      );
    }

    return detailRows;
  }

  static List<pw.Widget> _buildCommercialSection(
    QuoteRequest quote,
    pw.Font baseFont,
    pw.Font boldFont, {
    String companyType = 'ATEPL',
    pw.Font? atsBodyFont,
    pw.Font? atsBodyBoldFont,
    pw.Font? atsTableHeaderFont,
    Map<int, pw.ImageProvider> productImages = const {},
  }) {
    final sections = <pw.Widget>[];
    final isAts = companyType == 'ATS';
    final safeBodyFont = isAts ? (atsBodyFont ?? pw.Font.times()) : baseFont;
    final safeBodyBoldFont = isAts
        ? (atsBodyBoldFont ?? pw.Font.timesBold())
        : boldFont;
    final safeHeaderFont = isAts
        ? (atsTableHeaderFont ?? pw.Font.helveticaBold())
        : boldFont;

    // Shared column width configurations to guarantee perfect alignment
    final columnWidths = {
      0: const pw.FixedColumnWidth(28),
      1: const pw.FlexColumnWidth(3),
      2: const pw.FixedColumnWidth(42),
      3: const pw.FixedColumnWidth(78),
      4: const pw.FixedColumnWidth(78),
    };

    final borderSide = pw.BorderSide(
      color: isAts ? PdfColors.black : PdfColors.grey500,
      width: isAts ? 0.8 : 0.5,
    );

    final tableBorder = pw.TableBorder(
      top: borderSide,
      bottom: borderSide,
      left: borderSide,
      right: borderSide,
      verticalInside: borderSide,
    );

    final allRows = <pw.TableRow>[];

    allRows.add(
      pw.TableRow(
        decoration: isAts
            ? null
            : const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text(
              isAts ? 'R.\nNo.' : 'SR.\nNO.',
              style: pw.TextStyle(
                font: safeHeaderFont,
                fontSize: isAts ? 9.8 : 8,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text(
              'DESCRIPTION',
              style: pw.TextStyle(
                font: safeHeaderFont,
                fontSize: isAts ? 9.8 : 8,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text(
              'QTY',
              style: pw.TextStyle(
                font: safeHeaderFont,
                fontSize: isAts ? 9.8 : 8,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text(
              isAts ? 'UNIT RATE\n(IN Rs.)' : 'UNIT RATE\n(IN Rs)',
              style: pw.TextStyle(
                font: safeHeaderFont,
                fontSize: isAts ? 9.8 : 8,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text(
              isAts ? 'AMOUNT\n(IN Rs. )' : 'AMOUNT\n(IN Rs)',
              style: pw.TextStyle(
                font: safeHeaderFont,
                fontSize: isAts ? 9.8 : 8,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
      ),
    );

    var srNo = 1;
    var isFirstRow = true;
    var atsAdditionalIndex = 1;

    for (var i = 0; i < quote.products.length; i++) {
      final product = quote.products[i];
      if (!_hasProductSummary(product)) continue;

      final hasDetails = _hasProductDetails(product);
      final displaySr = product.srNo.isNotEmpty ? product.srNo : '$srNo.';

      final topBorder = (!isFirstRow)
          ? pw.Border(top: borderSide)
          : pw.Border(top: borderSide);
      isFirstRow = false;

      allRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(border: topBorder),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                displaySr,
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: isAts ? 11 : 9.5,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: _buildProductSummaryCell(
                product,
                safeBodyFont,
                safeBodyBoldFont,
                productImages[i],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                '${product.quantity} NO',
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: isAts ? 11 : 9,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                '${_formatPrice(product.unitPrice)}/-',
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: isAts ? 11 : 9,
                  color: PdfColors.black,
                ),
                textAlign: isAts ? pw.TextAlign.center : pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                '${_formatPrice(product.total)}/-',
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: isAts ? 11 : 9,
                  color: PdfColors.black,
                ),
                textAlign: isAts ? pw.TextAlign.center : pw.TextAlign.right,
              ),
            ),
          ],
        ),
      );

      if (hasDetails && !isAts) {
        allRows.addAll(
          _buildProductDetailRows(
            product,
            srNo,
            safeBodyFont,
            safeBodyBoldFont,
          ),
        );
      }

      srNo++;
    }

    for (final item in quote.additionalItems) {
      if (!_hasAdditionalItemRow(item)) continue;

      final addSpecs = _buildAdditionalItemDetailWidgets(
        item,
        baseFont,
        boldFont,
      );
      final hasSpecs = addSpecs.isNotEmpty;

      final topBorder = (!isFirstRow)
          ? pw.Border(top: borderSide)
          : pw.Border(top: borderSide);
      isFirstRow = false;

      allRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(border: topBorder),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                isAts ? '1.${atsAdditionalIndex++}' : '$srNo.',
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: isAts ? 11 : 9.5,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                item.description,
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: isAts ? 11 : 8.5,
                  color: PdfColors.black,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                item.qty.isNotEmpty ? item.qty : '-',
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: isAts ? 11 : 9,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                item.unitRate > 0 ? '${_formatPrice(item.unitRate)}/-' : '-',
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: isAts ? 11 : 9,
                  color: PdfColors.black,
                ),
                textAlign: isAts ? pw.TextAlign.center : pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                item.amount > 0 ? '${_formatPrice(item.amount)}/-' : '-',
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: isAts ? 11 : 9,
                  color: PdfColors.black,
                ),
                textAlign: isAts ? pw.TextAlign.center : pw.TextAlign.right,
              ),
            ),
          ],
        ),
      );

      if (hasSpecs) {
        for (var idx = 0; idx < addSpecs.length; idx++) {
          allRows.add(
            pw.TableRow(
              children: [
                pw.Text(''),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 2,
                    horizontal: 6,
                  ),
                  child: addSpecs[idx],
                ),
                pw.Text(''),
                pw.Text(''),
                pw.Text(''),
              ],
            ),
          );
        }
      }

      srNo++;
    }

    final topBorder = (!isFirstRow)
        ? pw.Border(top: borderSide)
        : pw.Border(top: borderSide);
    allRows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(border: topBorder),
        children: [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'TOTAL AMOUNT (IN Rs) :',
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: isAts ? 10.5 : 9,
                  color: PdfColors.black,
                ),
              ),
            ),
          ),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(
              '${_formatPrice(quote.totalAmount)}/-',
              style: pw.TextStyle(
                font: safeBodyBoldFont,
                fontSize: isAts ? 11 : 10,
                color: PdfColors.black,
              ),
              textAlign: isAts ? pw.TextAlign.center : pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );

    sections.add(
      pw.Table(
        columnWidths: columnWidths,
        border: tableBorder,
        children: allRows,
      ),
    );

    sections.add(pw.SizedBox(height: 10));

    return sections;
  }

  static bool _hasProductSummary(QuoteProduct product) {
    return product.productName.trim().isNotEmpty ||
        product.make.trim().isNotEmpty ||
        product.model.trim().isNotEmpty ||
        product.hsnNo.trim().isNotEmpty ||
        product.quantity > 0 ||
        product.unitPrice > 0;
  }

  static bool _hasProductDetails(QuoteProduct product) {
    return product.productOverview.trim().isNotEmpty ||
        product.keyFeatures.trim().isNotEmpty ||
        product.parametersMeasured.trim().isNotEmpty ||
        product.specification.trim().isNotEmpty ||
        product.accessories.trim().isNotEmpty ||
        product.documentAndCertificate.trim().isNotEmpty;
  }

  static bool _hasAdditionalItemRow(AdditionalQuoteItem item) {
    return item.description.trim().isNotEmpty ||
        item.specification.trim().isNotEmpty ||
        item.unitRate > 0 ||
        item.amount > 0;
  }

  static pw.Widget _buildProductSummaryCell(
    QuoteProduct product,
    pw.Font baseFont,
    pw.Font boldFont,
    pw.ImageProvider? productImage,
  ) {
    final details = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          product.productName,
          style: pw.TextStyle(
            font: boldFont,
            fontSize: 8.5,
            color: PdfColors.blueGrey900,
          ),
        ),
        if (product.make.isNotEmpty)
          pw.Text(
            'Make: ${product.make}',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 8,
              color: PdfColors.blueGrey800,
            ),
          ),
        if (product.model.isNotEmpty)
          pw.Text(
            'Model: ${product.model}',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 8,
              color: PdfColors.blueGrey800,
            ),
          ),
        if (product.hsnNo.isNotEmpty)
          pw.Text(
            'HSN: ${product.hsnNo}',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 8,
              color: PdfColors.blueGrey800,
            ),
          ),
      ],
    );

    if (productImage == null) return details;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: details),
        pw.SizedBox(width: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(3),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Image(
            productImage,
            height: 58,
            width: 76,
            fit: pw.BoxFit.contain,
          ),
        ),
      ],
    );
  }

  static List<pw.Widget> _buildAdditionalItemDetailWidgets(
    AdditionalQuoteItem item,
    pw.Font baseFont,
    pw.Font boldFont,
  ) {
    if (item.specification.trim().isEmpty) return const [];
    return _buildBulletSection(
      'Specification:',
      item.specification,
      baseFont,
      boldFont,
    );
  }

  static List<pw.Widget> _buildBulletSection(
    String title,
    String text,
    pw.Font baseFont,
    pw.Font boldFont,
  ) {
    final lines = text.split('\n').where((s) => s.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const [];

    return [
      pw.SizedBox(height: 8),
      pw.Text(
        title,
        style: pw.TextStyle(
          font: boldFont,
          fontSize: 8.5,
          decoration: pw.TextDecoration.underline,
          color: PdfColors.blueGrey900,
        ),
      ),
      pw.SizedBox(height: 2),
      for (final line in lines)
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10),
          child: _buildBulletPoint(line, baseFont, 8, boldFont: boldFont),
        ),
    ];
  }

  static pw.Widget _buildTermsBox(
    QuoteRequest quote,
    pw.Font baseFont,
    pw.Font boldFont,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blueGrey800, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < quote.terms.length; i++) ...[
            _buildTermRow(
              '${i + 1}. ${quote.terms[i].key}',
              quote.terms[i].value,
              baseFont,
              boldFont,
            ),
            if (i < quote.terms.length - 1) pw.SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildTermRow(
    String title,
    String val,
    pw.Font baseFont,
    pw.Font boldFont, {
    double fontSize = 9.5,
    double keyWidth = 90,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: keyWidth,
          child: pw.Text(
            '$title:',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: fontSize,
              color: PdfColors.blueGrey900,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            val,
            style: pw.TextStyle(
              font: baseFont,
              fontSize: fontSize,
              color: PdfColors.blueGrey900,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFooterBanner(
    pw.Font baseFont,
    pw.Font boldFont,
    String companyType,
  ) {
    if (companyType == 'ATS') {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Divider(color: PdfColors.black, thickness: 0.8),
          pw.SizedBox(height: 3),
          pw.RichText(
            textAlign: pw.TextAlign.center,
            text: pw.TextSpan(
              style: pw.TextStyle(
                font: baseFont,
                fontSize: 7.5,
                color: PdfColors.black,
              ),
              children: [
                const pw.TextSpan(text: 'Email: '),
                pw.TextSpan(
                  text: 'info@appliedtechnosystems.net',
                  style: pw.TextStyle(
                    color: PdfColor.fromHex('#0000FF'),
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
                const pw.TextSpan(text: '  '),
                pw.TextSpan(
                  text: 'appliedtechnosystems@gmail.com',
                  style: pw.TextStyle(
                    color: PdfColor.fromHex('#0000FF'),
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
                const pw.TextSpan(text: '  Web: '),
                pw.TextSpan(
                  text: 'www.appliedtechnosystems.net',
                  style: pw.TextStyle(
                    color: PdfColor.fromHex('#0000FF'),
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 1.5),
          pw.RichText(
            textAlign: pw.TextAlign.center,
            text: pw.TextSpan(
              style: pw.TextStyle(
                font: baseFont,
                fontSize: 7.5,
                color: PdfColors.black,
              ),
              children: [
                const pw.TextSpan(text: 'Contact No.: '),
                pw.TextSpan(
                  text: '+91 8652226750',
                  style: pw.TextStyle(font: boldFont),
                ),
                const pw.TextSpan(text: '  '),
                pw.TextSpan(
                  text: '+91 7767048603',
                  style: pw.TextStyle(font: boldFont),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return pw.Column(
      children: [
        pw.Container(
          height: 16,
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF58220), // Orange/Gold corporate bar
          ),
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.symmetric(horizontal: 14),
          child: pw.Text(
            'www.at-epl.com',
            style: pw.TextStyle(
              font: baseFont,
              fontSize: 8.5,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildParametersTable(
    String csvData,
    pw.Font baseFont,
    pw.Font boldFont,
  ) {
    final lines = csvData
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final rows = <pw.TableRow>[];

    // Header Row
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: pw.Text(
              'Gas',
              style: pw.TextStyle(font: boldFont, fontSize: 7.5),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: pw.Text(
              'Sensor',
              style: pw.TextStyle(font: boldFont, fontSize: 7.5),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: pw.Text(
              'Range',
              style: pw.TextStyle(font: boldFont, fontSize: 7.5),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: pw.Text(
              'Resolution',
              style: pw.TextStyle(font: boldFont, fontSize: 7.5),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
      ),
    );

    for (final line in lines) {
      final cells = line.split(',').map((c) => c.trim()).toList();
      while (cells.length < 4) {
        cells.add('');
      }
      rows.add(
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 2,
              ),
              child: pw.Text(
                cells[0],
                style: pw.TextStyle(font: baseFont, fontSize: 7.5),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 2,
              ),
              child: pw.Text(
                cells[1],
                style: pw.TextStyle(font: baseFont, fontSize: 7.5),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 2,
              ),
              child: pw.Text(
                cells[2],
                style: pw.TextStyle(font: baseFont, fontSize: 7.5),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 2,
              ),
              child: pw.Text(
                cells[3],
                style: pw.TextStyle(font: baseFont, fontSize: 7.5),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      width: 240,
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(40),
          1: pw.FixedColumnWidth(55),
          2: pw.FixedColumnWidth(85),
          3: pw.FixedColumnWidth(60),
        },
        children: rows,
      ),
    );
  }

  static pw.Widget _buildBulletPoint(
    String text,
    pw.Font font,
    double fontSize, {
    pw.Font? boldFont,
  }) {
    var cleanText = stripLeadingBulletPrefix(text.trim());

    final colonIndex = cleanText.indexOf(':');
    pw.Widget textWidget;
    if (colonIndex != -1 && boldFont != null) {
      final key = cleanText.substring(0, colonIndex + 1);
      final val = cleanText.substring(colonIndex + 1);
      textWidget = pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: key,
              style: pw.TextStyle(
                font: boldFont,
                fontSize: fontSize,
                color: PdfColors.blueGrey900,
              ),
            ),
            pw.TextSpan(
              text: val,
              style: pw.TextStyle(
                font: font,
                fontSize: fontSize,
                color: PdfColors.blueGrey900,
              ),
            ),
          ],
        ),
      );
    } else {
      textWidget = pw.Text(
        cleanText,
        style: pw.TextStyle(
          font: font,
          fontSize: fontSize,
          color: PdfColors.blueGrey900,
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 3,
            height: 3,
            margin: const pw.EdgeInsets.only(top: 3.5, right: 6),
            decoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.Expanded(child: textWidget),
        ],
      ),
    );
  }

  static String _formatPrice(double value) {
    final format = value.toStringAsFixed(0);
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String formatted = format.replaceAllMapped(reg, (Match m) => '${m[1]},');
    return formatted;
  }
}
