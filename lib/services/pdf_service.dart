import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
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

  /// Stamp artwork with its white paper background knocked out, keyed by asset.
  static final Map<String, pw.MemoryImage> _cachedStamps =
      <String, pw.MemoryImage>{};

  /// Loads a stamp/signature asset and makes its white paper transparent so
  /// the page watermark shows through.
  ///
  /// The ATEPL asset is a baseline JPEG, which cannot carry alpha at all — it
  /// was painting an opaque white square over the watermark. Rather than
  /// shipping a second pre-processed file we knock the white out here, so any
  /// future stamp scan works the same way.
  ///
  /// Alpha is `255 - min(R,G,B)`, i.e. a multiply blend: dark ink stays fully
  /// opaque, paper vanishes, and anti-aliased edges keep partial alpha instead
  /// of the jagged fringe a binary threshold leaves behind.
  static Future<pw.MemoryImage> _loadStampImage(String asset) async {
    final cached = _cachedStamps[asset];
    if (cached != null) return cached;

    final raw = (await rootBundle.load(asset)).buffer.asUint8List();
    Uint8List bytes = raw;
    try {
      final decoded = img.decodeImage(raw);
      if (decoded != null) {
        final rgba = decoded.convert(numChannels: 4);
        for (final p in rgba) {
          final ink = 255 - [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
          // Keep an already-transparent pixel transparent.
          p.a = p.a == 0 ? 0 : ink.clamp(0, 255).toDouble();
        }
        bytes = Uint8List.fromList(img.encodePng(rgba));
      }
    } catch (e) {
      // Fall back to the untouched asset — a white box beats no stamp.
      debugPrint('[PdfService] Stamp knockout failed for $asset: $e');
    }
    return _cachedStamps[asset] = pw.MemoryImage(bytes);
  }

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

    // ATEPL letterhead: crop header + footer from reference AEQ 0302 PDF and
    // embed as images (same idea as ATS header lockup) so fonts/colours/spacing
    // match the printed letterhead exactly.
    pw.MemoryImage? ateplHeaderLetterhead;
    pw.MemoryImage? ateplFooterBanner;
    if (!isAts) {
      try {
        final headerData = await rootBundle.load(_ateplHeaderLetterheadAsset);
        ateplHeaderLetterhead = pw.MemoryImage(headerData.buffer.asUint8List());
      } catch (_) {
        ateplHeaderLetterhead = null;
      }
      try {
        final footerData = await rootBundle.load(_ateplFooterBannerAsset);
        ateplFooterBanner = pw.MemoryImage(footerData.buffer.asUint8List());
      } catch (_) {
        ateplFooterBanner = null;
      }
    }

    final signature = await _loadStampImage(
      isAts ? _atsStampAsset : _ateplStampAsset,
    );

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
      final empName = creatorName != null && creatorName.isNotEmpty
          ? creatorName
          : 'Mrs. Pratima.';
      final empMobile = creatorMobile != null && creatorMobile.isNotEmpty
          ? creatorMobile
          : '08010915931';
      final firstProduct = quote.products.isNotEmpty
          ? quote.products.first
          : const QuoteProduct(productName: '');

      pw.TextStyle atsText({double size = 11.5, bool bold = false}) =>
          pw.TextStyle(
            font: bold ? atsSerifBold : atsSerif,
            fontSize: size,
            color: PdfColors.black,
          );

      pw.Widget atsHeader(pw.Context context) => _buildTopHeader(
        logo,
        baseFont,
        boldFont,
        quote.companyType,
        atsMonoBold: atsMonoBold,
      );

      pw.Widget atsFooter(pw.Context context) =>
          _buildFooterBanner(baseFont, boldFont, quote.companyType);

      pw.Widget atsRefDateRow() => pw.Row(
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
      );

      // Page 1: introduction letter. Same three-section shape as the ATEPL
      // quote — only the letterhead and footer differ. Reference AEQ 0046
      // keeps the recipient block off this page, so the Quotation title and
      // REF/Date sit straight under the letterhead.
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pageTheme,
          header: atsHeader,
          footer: atsFooter,
          build: (context) {
            return [
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'Quotation',
                  style: atsText(size: 13.5, bold: true),
                ),
              ),
              pw.SizedBox(height: 8),
              atsRefDateRow(),
              pw.SizedBox(height: 14),
              pw.Text('Dear Customer,', style: atsText()),
              pw.SizedBox(height: 8),
              pw.Text(
                '${_quoteIntroLine(quote)} As discussed, we are glad to extend our quotation for ${_quoteIntroSubject(quote, firstProduct)}.',
                style: atsText(),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Please find enclosed the following:-', style: atsText()),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 16, top: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildBulletPoint(
                      'Introduction',
                      atsSerif,
                      11,
                      color: PdfColors.black,
                    ),
                    _buildBulletPoint(
                      'Techno-Commercial Offer',
                      atsSerif,
                      11,
                      color: PdfColors.black,
                    ),
                    _buildBulletPoint(
                      'Product Catalogue',
                      atsSerif,
                      11,
                      color: PdfColors.black,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'We have reviewed your requirement and we trust that our offer meet your technical specifications, we are waiting for your approval and look forward to a long and successful association with your Organization.',
                style: atsText(),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'We use emerging technologies and customized cutting edge solutions to best fit the instrument to the application. With qualified and experienced electronics and instrumentation engineers we are committed to R&D and innovation in our products to cater to the clients need.',
                style: atsText(),
              ),
              pw.SizedBox(height: 10),
              _buildOverviewTable(atsSerif, atsSerifBold, ats: true),
              pw.SizedBox(height: 10),
              pw.Text(
                'May you need any additional information or clarifications, please feel free to contact us.\nThanking you in anticipation.\nRegards,',
                style: atsText(),
              ),
              pw.SizedBox(height: 2),
              pw.Text('Applied Techno Systems', style: atsText()),
              pw.SizedBox(height: 2),
              pw.Image(
                signature,
                width: _atsIntroStampWidth,
                height: _atsIntroStampWidth / _atsStampAspect,
              ),
              pw.SizedBox(height: 2),
              pw.Text('Authorized Signatory', style: atsText()),
            ];
          },
        ),
      );

      // Page 2+: techno-commercial offer. MultiPage flows the item table (with
      // its per-item technical details) across as many pages as it needs.
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pageTheme,
          header: atsHeader,
          footer: atsFooter,
          build: (context) {
            return [
              pw.SizedBox(height: 12),
              atsRefDateRow(),
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
              // Terms continue straight after the totals row; a separate
              // addPage() here used to force them onto a fresh sheet.
              pw.SizedBox(height: 16),
              pw.Text(
                'TERMS & CONDITIONS',
                style: pw.TextStyle(
                  font: atsSerifBold,
                  fontSize: 12,
                  color: PdfColors.black,
                  decoration: pw.TextDecoration.underline,
                ),
              ),
              pw.SizedBox(height: 10),
              _buildAtsTermsBox(quote, atsSerif, atsSerifBold),
              pw.SizedBox(height: 16),
              pw.Text(
                'Hope the above meets with your requirement; meanwhile should you require any further information or any clarification please feel free to contact the undersigned. We will be more than pleased to provide any help required.',
                style: atsText(),
              ),
              pw.SizedBox(height: 14),
              pw.Text('Yours faithfully', style: atsText()),
              pw.Text('For Applied Techno Systems', style: atsText(bold: true)),
              pw.SizedBox(height: 4),
              pw.Image(
                signature,
                width: _atsClosingStampWidth,
                height: _atsClosingStampWidth / _atsStampAspect,
              ),
              pw.SizedBox(height: 4),
              pw.Text(empName, style: atsText()),
              pw.Text('$empMobile/8652226750', style: atsText()),
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
            ateplHeaderLetterhead: ateplHeaderLetterhead,
          ),
          footer: (context) => _buildFooterBanner(
            baseFont,
            boldFont,
            quote.companyType,
            ateplFooterBanner: ateplFooterBanner,
          ),
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
                '${_quoteIntroLine(quote)} As discussed, we are glad to extend our quotation for ${_quoteIntroSubject(quote, firstProduct)}.',
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
              // ~1.4" — typical round company rubber-stamp diameter on A4.
              pw.Image(
                signature,
                width: _ateplStampSize,
                height: _ateplStampSize,
              ),
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
            ateplHeaderLetterhead: ateplHeaderLetterhead,
          ),
          footer: (context) => _buildFooterBanner(
            baseFont,
            boldFont,
            quote.companyType,
            ateplFooterBanner: ateplFooterBanner,
          ),
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
              // Terms continue straight after the totals row. They used to live
              // in a THIRD addPage(), and since every addPage starts a new
              // physical sheet that left the rest of the page blank.
              pw.SizedBox(height: 14),
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
              pw.Image(
                signature,
                width: _ateplStampSize,
                height: _ateplStampSize,
              ),
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

  /// ATS commercial terms — full-width numbered box on its own page, the way
  /// reference AEQ 0046 sets them out (the older side-by-side box only fitted
  /// because that quote was squeezed onto a single page).
  static pw.Widget _buildAtsTermsBox(
    QuoteRequest quote,
    pw.Font atsSerif,
    pw.Font atsSerifBold,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < quote.terms.length; i++) ...[
            _buildTermRow(
              '${i + 1}. ${quote.terms[i].key}',
              quote.terms[i].value,
              atsSerif,
              atsSerifBold,
              fontSize: 11,
              keyWidth: 90,
              color: PdfColors.black,
            ),
            if (i < quote.terms.length - 1) pw.SizedBox(height: 4),
          ],
        ],
      ),
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

  /// Round company stamp + sign size on ATEPL quotes (~1.4" / 35mm diameter,
  /// typical physical rubber-stamp size on A4 letterhead).
  static const double _ateplStampSize = 100;

  /// ATS round seal + signature, cropped out of reference AEQ 0046 (the same
  /// artwork is stamped on its page 1 and page 3). Near-white is transparent so
  /// the ATS watermark shows through instead of a white patch.
  static const String _atsStampAsset = 'Assets/Logo/ats_stamp_signature.png';

  /// ATEPL round stamp + signature. A 200x200 baseline JPEG, so it has no
  /// alpha of its own — [_loadStampImage] knocks the white out at runtime.
  static const String _ateplStampAsset = 'Assets/digital_signature.jpeg';
  static const double _atsStampAspect = 153 / 129;

  /// Same size on the intro page and the closing terms page — the reference
  /// stamps the intro smaller, but at that scale it reads as a smudge.
  static const double _atsIntroStampWidth = 98;
  static const double _atsClosingStampWidth = 98;

  /// ATEPL letterhead header — full crop from reference AEQ 0302 (logo + name
  /// + address/contact + GST/CIN + red rule). Pixel size 1787×363 @ 3× render.
  static const String _ateplHeaderLetterheadAsset =
      'Assets/Logo/atepl_header_letterhead.png';
  static const double _ateplHeaderLetterheadWidth = 531;
  static const double _ateplHeaderLetterheadAspect = 1787 / 363;
  static const double _ateplHeaderLetterheadHeight =
      _ateplHeaderLetterheadWidth / _ateplHeaderLetterheadAspect;

  /// ATEPL footer banner — crop from the same reference (diagonal cuts +
  /// orange bar + website). Pixel size 1787×81 @ 3× render.
  static const String _ateplFooterBannerAsset =
      'Assets/Logo/atepl_footer_banner.png';
  static const double _ateplFooterBannerWidth = 531;
  static const double _ateplFooterBannerAspect = 1787 / 81;
  static const double _ateplFooterBannerHeight =
      _ateplFooterBannerWidth / _ateplFooterBannerAspect;

  /// header on every page (MultiPage repeats this automatically on overflow).
  static pw.Widget _buildTopHeader(
    pw.ImageProvider logo,
    pw.Font baseFont,
    pw.Font boldFont,
    String companyType, {
    pw.Font? atsMonoBold,
    pw.ImageProvider? ateplHeaderLetterhead,
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
    return _buildPageHeader(
      logo,
      baseFont,
      boldFont,
      companyType,
      ateplHeaderLetterhead: ateplHeaderLetterhead,
    );
  }

  static pw.Widget _buildPageHeader(
    pw.ImageProvider logo,
    pw.Font baseFont,
    pw.Font boldFont,
    String companyType, {
    pw.Font? atsMonoBold,
    pw.ImageProvider? ateplHeaderLetterhead,
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
          // Breathing room for MultiPage overflow pages, where the body picks
          // up straight under the letterhead with no leading spacer of its own.
          pw.SizedBox(height: 8),
        ],
      );
    }

    // ATEPL: embed the cropped letterhead header image so fonts/colours/icons
    // match AEQ 0302 exactly. Fallback keeps a minimal drawn header if the
    // asset is missing (e.g. session not restarted after pubspec change).
    if (ateplHeaderLetterhead != null) {
      return pw.Image(
        ateplHeaderLetterhead,
        width: _ateplHeaderLetterheadWidth,
        height: _ateplHeaderLetterheadHeight,
        fit: pw.BoxFit.fill,
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Image(logo, width: 78, height: 78, fit: pw.BoxFit.contain),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Applied Techno Engineers Pvt. Ltd.',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 20,
                  color: PdfColor.fromHex('#EE4724'),
                ),
                textAlign: pw.TextAlign.right,
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'A/104, Delta Industrial Estate, Building No.1, Bhoidapada, Sativali Road,\nVasai East (Thane), Dist-Palghar, Maharashtra. Pincode: 401208.',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 8,
                  color: PdfColors.blueGrey900,
                ),
                textAlign: pw.TextAlign.right,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'info@at-epl.com  |  sales@at-epl.com',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 8,
                  color: PdfColors.blueGrey900,
                ),
                textAlign: pw.TextAlign.right,
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                '+91 8652226750  |  7767048603',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 8,
                  color: PdfColors.blueGrey900,
                ),
                textAlign: pw.TextAlign.right,
              ),
              pw.SizedBox(height: 4),
              pw.Container(height: 0.7, color: PdfColor.fromHex('#EE4724')),
              pw.SizedBox(height: 2),
              pw.Text(
                'GST NO. 27AAVCA1127G1ZN | CIN : U29309MH2021PTC359067',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 8,
                  color: PdfColors.blueGrey800,
                ),
                textAlign: pw.TextAlign.right,
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
    bool ats = false,
  }) {
    final headerPadding = ats
        ? const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 4)
        : compact
        ? const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 3)
        : const pw.EdgeInsets.all(5);
    final headerFontSize = ats
        ? 10.0
        : compact
        ? 7.2
        : 8.5;
    return pw.Table(
      border: pw.TableBorder.all(
        color: ats ? PdfColors.black : PdfColors.grey400,
        width: ats ? 0.8 : 0.5,
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1.2),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: ats
              ? null
              : const pw.BoxDecoration(color: PdfColors.grey100),
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
          ats: ats,
        ),
        _buildOverviewRow(
          'GAS Analyzers',
          'Chemical & Pharmaceutical',
          'Industrial Hygiene & Safety',
          baseFont,
          compact: compact,
          ats: ats,
        ),
        _buildOverviewRow(
          'Flue/Stack Gas Analyser',
          'Power Plants',
          'Stack Emission/ Source Emission',
          baseFont,
          compact: compact,
          ats: ats,
        ),
        _buildOverviewRow(
          'Dust Particulate Monitors',
          'Petrochemical and Oil industries',
          'Quality Control',
          baseFont,
          compact: compact,
          ats: ats,
        ),
        _buildOverviewRow(
          'Opacity Monitors',
          'Oil & Gas',
          'Research and Development',
          baseFont,
          compact: compact,
          ats: ats,
        ),
        _buildOverviewRow(
          'Dew Point/ Moisture Analyzer',
          'Defense Laboratories',
          'Flame/ Fire/ Smoke Detection',
          baseFont,
          compact: compact,
          ats: ats,
        ),
        _buildOverviewRow(
          'Dust Guard',
          'Transport & Retail Industries',
          'Moisture/ Dew-Point & Velocity',
          baseFont,
          compact: compact,
          ats: ats,
        ),
        _buildOverviewRow(
          'Solid Flow / Broken Bag Detectors',
          'Original Equipment Manufacturer',
          'Process Analysis',
          baseFont,
          compact: compact,
          ats: ats,
        ),
        _buildOverviewRow(
          'Energy Monitoring System',
          'Telecom Industries',
          '',
          baseFont,
          compact: compact,
          ats: ats,
        ),
        _buildOverviewRow(
          'Web Data Acquisition Systems',
          'Healthcare Industries',
          '',
          baseFont,
          compact: compact,
          ats: ats,
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
    bool ats = false,
  }) {
    final padding = ats
        ? const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4)
        : compact
        ? const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3)
        : const pw.EdgeInsets.all(4);
    final fontSize = ats
        ? 9.5
        : compact
        ? 6.7
        : 8.0;
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
    pw.Font boldFont, {
    bool ats = false,
  }) {
    final detailRows = <pw.TableRow>[];
    final detailWidgets = <pw.Widget>[];

    // ATS prints on black-ruled letterhead at reading size; ATEPL keeps the
    // softer blue-grey scale of its own template.
    final headingColor = ats ? PdfColors.black : PdfColors.blueGrey900;
    final bodyColor = ats ? PdfColors.black : PdfColors.blueGrey800;
    final headingSize = ats ? 11.0 : 8.5;
    final bodySize = ats ? 10.5 : 8.0;

    // 1. Header: "Item $srNo - Technical Details". The ATS reference runs the
    // specs straight under the item line with no such divider, so skip it.
    final displaySr = product.srNo.isNotEmpty ? product.srNo : '$srNo';
    if (!ats) {
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
    }

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
              fontSize: headingSize,
              decoration: pw.TextDecoration.underline,
              color: headingColor,
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
                  decoration: pw.BoxDecoration(
                    color: bodyColor,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    cleanLine,
                    style: pw.TextStyle(
                      font: baseFont,
                      fontSize: bodySize,
                      color: bodyColor,
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
              fontSize: headingSize,
              color: headingColor,
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
            ats: ats,
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
              'SR.\nNO.',
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
                ats: isAts,
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

      if (hasDetails) {
        allRows.addAll(
          _buildProductDetailRows(
            product,
            srNo,
            safeBodyFont,
            safeBodyBoldFont,
            ats: isAts,
          ),
        );
      }

      srNo++;
    }

    final orderedAdditional = [
      ...quote.additionalItems.where((item) => item.isCalibration),
      ...quote.additionalItems.where((item) => !item.isCalibration),
    ];

    for (final item in orderedAdditional) {
      if (!_hasAdditionalItemRow(item)) continue;

      final addSpecs = _buildAdditionalItemDetailWidgets(
        item,
        safeBodyFont,
        safeBodyBoldFont,
        ats: isAts,
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
                '$srNo.',
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
                _additionalItemDescriptionText(item),
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

    // Totals block. With no discount this emits exactly one row, byte-for-byte
    // as before; with one it becomes SUB TOTAL -> LESS: DISCOUNT -> TOTAL.
    pw.TableRow totalsRow(
      String label,
      String value, {
      required bool emphasise,
    }) {
      return pw.TableRow(
        decoration: pw.BoxDecoration(border: pw.Border(top: borderSide)),
        children: [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  font: safeBodyBoldFont,
                  fontSize: emphasise ? (isAts ? 10.5 : 9) : (isAts ? 10 : 8.5),
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
              value,
              style: pw.TextStyle(
                font: safeBodyBoldFont,
                fontSize: emphasise ? (isAts ? 11 : 10) : (isAts ? 10 : 9),
                color: PdfColors.black,
              ),
              textAlign: isAts ? pw.TextAlign.center : pw.TextAlign.right,
            ),
          ),
        ],
      );
    }

    if (quote.hasDiscount) {
      allRows.add(
        totalsRow(
          'SUB TOTAL (IN Rs) :',
          '${_formatPrice(quote.grossAmount)}/-',
          emphasise: false,
        ),
      );
      allRows.add(
        totalsRow(
          'LESS: DISCOUNT (${_formatDiscountPercent(quote.discountPercent)}%) :',
          '-${_formatPrice(quote.discountValue)}/-',
          emphasise: false,
        ),
      );
    }

    allRows.add(
      totalsRow(
        'TOTAL AMOUNT (IN Rs) :',
        '${_formatPrice(quote.totalAmount)}/-',
        emphasise: true,
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

  /// Calibration descriptions: each comma starts a new PDF line.
  static String _additionalItemDescriptionText(AdditionalQuoteItem item) {
    if (!item.isCalibration) return item.description;
    return item.description
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join('\n');
  }

  /// Opening line of the covering letter.
  ///
  /// Falls back to the company when no contact name was entered. It used to
  /// fall back to a hardcoded person's name, which printed a stranger's name
  /// on real customer quotations. Never emits a bare "Mr.".
  static String _quoteIntroLine(QuoteRequest quote) {
    const tail =
        'the kind courtesy extended to you during the telephonic conversation.';
    final customer = quote.customerName.trim();
    if (customer.isNotEmpty) {
      // Don't double up if the user already typed an honorific.
      final hasHonorific = RegExp(
        r'^(mr|mrs|ms|miss|dr|shri|smt)\.?\s',
        caseSensitive: false,
      ).hasMatch(customer);
      final name = hasHonorific ? customer : 'Mr. $customer';
      return 'We thank you very much for the kind courtesy extended to '
          '$name during the telephonic conversation.';
    }
    final company = quote.companyName.trim();
    if (company.isNotEmpty) {
      return 'We thank you very much for the kind courtesy extended to us by '
          '$company during the telephonic conversation.';
    }
    return 'We thank you very much for $tail';
  }

  static String _quoteIntroSubject(
    QuoteRequest quote,
    QuoteProduct firstProduct,
  ) {
    final name = _introSubjectLabel(firstProduct.productName);
    if (name.isNotEmpty) {
      final model = firstProduct.model.trim();
      // Skip the model suffix when the label already names it, otherwise the
      // sentence reads "... ATS-301D Model ATS-301D".
      if (model.isEmpty || name.toLowerCase().contains(model.toLowerCase())) {
        return name;
      }
      return '$name Model $model';
    }
    for (final item in quote.additionalItems) {
      if (!item.isCalibration) continue;
      final subject = _introSubjectLabel(item.description);
      if (subject.isNotEmpty) return subject;
    }
    return 'the enclosed items';
  }

  /// First line/segment of a description, used as the subject of the covering
  /// letter. Users type the whole block — name, model, serial no., "Charges
  /// For Calibration & Repairing.." — into one field, separated by newlines or
  /// commas. Only the opening name belongs in the sentence; everything after
  /// it already prints in full inside the item table.
  static String _introSubjectLabel(String raw) {
    final first = raw
        .split(RegExp(r'[,\n]'))
        .map((part) => part.trim())
        .firstWhere((part) => part.isNotEmpty, orElse: () => '');
    return first
        // Drop a leading "Model Name :" / "Product :" style label.
        .replaceFirst(
          RegExp(
            r'^(model\s*name|product\s*name|item\s*name|model|product|item)\s*[:\-]\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(RegExp(r'[.\s]+$'), '')
        .trim();
  }

  static pw.Widget _buildProductSummaryCell(
    QuoteProduct product,
    pw.Font baseFont,
    pw.Font boldFont,
    pw.ImageProvider? productImage, {
    bool ats = false,
  }) {
    final titleColor = ats ? PdfColors.black : PdfColors.blueGrey900;
    final lineColor = ats ? PdfColors.black : PdfColors.blueGrey800;
    final titleSize = ats ? 11.0 : 8.5;
    final lineSize = ats ? 11.0 : 8.0;
    final details = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          product.productName,
          style: pw.TextStyle(
            font: boldFont,
            fontSize: titleSize,
            color: titleColor,
          ),
        ),
        if (product.make.isNotEmpty)
          pw.Text(
            'Make: ${product.make}',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: lineSize,
              color: lineColor,
            ),
          ),
        if (product.model.isNotEmpty)
          pw.Text(
            'Model: ${product.model}',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: lineSize,
              color: lineColor,
            ),
          ),
        if (product.hsnNo.isNotEmpty)
          pw.Text(
            'HSN: ${product.hsnNo}',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: lineSize,
              color: lineColor,
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
    pw.Font boldFont, {
    bool ats = false,
  }) {
    if (item.specification.trim().isEmpty) return const [];
    return _buildBulletSection(
      'Specification:',
      item.specification,
      baseFont,
      boldFont,
      ats: ats,
    );
  }

  static List<pw.Widget> _buildBulletSection(
    String title,
    String text,
    pw.Font baseFont,
    pw.Font boldFont, {
    bool ats = false,
  }) {
    final lines = text.split('\n').where((s) => s.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const [];

    return [
      pw.SizedBox(height: 8),
      pw.Text(
        title,
        style: pw.TextStyle(
          font: boldFont,
          fontSize: ats ? 11 : 8.5,
          decoration: pw.TextDecoration.underline,
          color: ats ? PdfColors.black : PdfColors.blueGrey900,
        ),
      ),
      pw.SizedBox(height: 2),
      for (final line in lines)
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10),
          child: _buildBulletPoint(
            line,
            baseFont,
            ats ? 10.5 : 8,
            boldFont: boldFont,
            color: ats ? PdfColors.black : PdfColors.blueGrey900,
          ),
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
    PdfColor color = PdfColors.blueGrey900,
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
              color: color,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            val,
            style: pw.TextStyle(
              font: baseFont,
              fontSize: fontSize,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFooterBanner(
    pw.Font baseFont,
    pw.Font boldFont,
    String companyType, {
    pw.ImageProvider? ateplFooterBanner,
  }) {
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

    // ATEPL: embed the banner artwork (cuts + orange + website). Do not add a
    // separate text child — the URL is already painted into the PNG.
    if (ateplFooterBanner != null) {
      return pw.Image(
        ateplFooterBanner,
        width: _ateplFooterBannerWidth,
        height: _ateplFooterBannerHeight,
        fit: pw.BoxFit.fill,
      );
    }

    // Fallback if the asset failed to load — solid orange bar (no tofu icons).
    return pw.Container(
      height: _ateplFooterBannerHeight,
      color: PdfColor.fromHex('#F06322'),
      alignment: pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.symmetric(horizontal: 14),
      child: pw.Text(
        'www.at-epl.com',
        style: pw.TextStyle(
          font: boldFont,
          fontSize: 10,
          color: PdfColor.fromHex('#731212'),
        ),
      ),
    );
  }

  static pw.Widget _buildParametersTable(
    String csvData,
    pw.Font baseFont,
    pw.Font boldFont, {
    bool ats = false,
  }) {
    final lines = csvData
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final rows = <pw.TableRow>[];

    // Header Row
    rows.add(
      pw.TableRow(
        decoration: ats
            ? null
            : const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: pw.Text(
              'Gas',
              style: pw.TextStyle(font: boldFont, fontSize: ats ? 10 : 7.5),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: pw.Text(
              'Sensor',
              style: pw.TextStyle(font: boldFont, fontSize: ats ? 10 : 7.5),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: pw.Text(
              'Range',
              style: pw.TextStyle(font: boldFont, fontSize: ats ? 10 : 7.5),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: pw.Text(
              'Resolution',
              style: pw.TextStyle(font: boldFont, fontSize: ats ? 10 : 7.5),
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
                style: pw.TextStyle(font: baseFont, fontSize: ats ? 10 : 7.5),
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
                style: pw.TextStyle(font: baseFont, fontSize: ats ? 10 : 7.5),
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
                style: pw.TextStyle(font: baseFont, fontSize: ats ? 10 : 7.5),
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
                style: pw.TextStyle(font: baseFont, fontSize: ats ? 10 : 7.5),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      width: ats ? 285 : 240,
      child: pw.Table(
        border: pw.TableBorder.all(
          color: ats ? PdfColors.black : PdfColors.grey400,
          width: ats ? 0.8 : 0.5,
        ),
        columnWidths: ats
            ? const {
                0: pw.FixedColumnWidth(48),
                1: pw.FixedColumnWidth(65),
                2: pw.FixedColumnWidth(100),
                3: pw.FixedColumnWidth(72),
              }
            : const {
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
    PdfColor color = PdfColors.blueGrey900,
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
                color: color,
              ),
            ),
            pw.TextSpan(
              text: val,
              style: pw.TextStyle(font: font, fontSize: fontSize, color: color),
            ),
          ],
        ),
      );
    } else {
      textWidget = pw.Text(
        cleanText,
        style: pw.TextStyle(font: font, fontSize: fontSize, color: color),
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
            decoration: pw.BoxDecoration(
              color: color,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.Expanded(child: textWidget),
        ],
      ),
    );
  }

  /// Discount percentage for the PDF label: whole number when it is one
  /// (a clean "10%"), otherwise one decimal.
  static String _formatDiscountPercent(double percent) {
    final rounded = (percent * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }

  static String _formatPrice(double value) {
    final format = value.toStringAsFixed(0);
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String formatted = format.replaceAllMapped(reg, (Match m) => '${m[1]},');
    return formatted;
  }
}
