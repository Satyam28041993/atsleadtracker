import 'package:atsleadtracker/models/lead_model.dart';
import 'package:atsleadtracker/models/lead_product_line.dart';
import 'package:atsleadtracker/screens/widgets/quote_builder_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Lead _lead() {
  final now = DateTime(2026, 9, 9);
  return Lead(
    id: 'lead-1',
    name: 'Rajnish Kumar',
    phone: '9661072692',
    email: 'rajnish9661072692@gmail.com',
    company: 'Applied Techno Systems',
    status: 'New',
    assignedTo: 'uid-emp',
    createdAt: now,
    remark: '',
    location: '528, Ram Datta Enclave, New Delhi',
    website: '',
    lastModified: now,
    productLines: const [
      LeadProductLine(requirement: 'Automotive Exhaust Gas Analyzers'),
    ],
  );
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required Size size,
  String companyType = 'ATEPL',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: QuoteBuilderDialog(
          lead: _lead(),
          initialCompanyType: companyType,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // The dialog used to be pinned to 720x620 whatever the screen, so a desktop
  // showed a handful of fields at a time. These check the responsive layout
  // renders without overflowing at either extreme — the usual failure mode
  // when fields are moved into a multi-column grid.

  testWidgets('renders on a desktop screen without overflow', (tester) async {
    await _pumpDialog(tester, size: const Size(1920, 1080));

    expect(find.text('Generate Professional Quotation'), findsOneWidget);
    expect(find.text('Quotation reference'), findsOneWidget);
    expect(find.text('Who this quotation is for'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses more than the old 720pt width on a desktop', (
    tester,
  ) async {
    await _pumpDialog(tester, size: const Size(1920, 1080));

    final box = tester.getSize(
      find.ancestor(
        of: find.text('Generate Professional Quotation'),
        matching: find.byType(ConstrainedBox),
      ).first,
    );
    expect(box.width, greaterThan(720));
  });

  testWidgets('renders on a phone-sized screen without overflow', (
    tester,
  ) async {
    await _pumpDialog(tester, size: const Size(400, 800));

    expect(find.text('Generate Professional Quotation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the product tab fields at desktop width', (
    tester,
  ) async {
    await _pumpDialog(tester, size: const Size(1920, 1080));

    await tester.tap(find.text('Product Details'));
    await tester.pumpAndSettle();

    expect(find.text('Pricing'), findsOneWidget);
    expect(find.text('Technical content'), findsOneWidget);
    expect(find.text('Quantity *'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the product tab on a phone', (tester) async {
    await _pumpDialog(tester, size: const Size(400, 800));

    await tester.tap(find.text('Product Details'));
    await tester.pumpAndSettle();

    expect(find.text('Pricing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ATS format renders the same layout', (tester) async {
    await _pumpDialog(
      tester,
      size: const Size(1920, 1080),
      companyType: 'ATS',
    );

    expect(find.text('Quotation reference'), findsOneWidget);

    await tester.tap(find.text('Product Details'));
    await tester.pumpAndSettle();

    expect(find.text('Technical content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tab renders at both extremes', (tester) async {
    for (final size in [const Size(1920, 1080), const Size(400, 800)]) {
      await _pumpDialog(tester, size: size);
      for (final tab in [
        'Client & Ref',
        'Product Details',
        'Additional Items',
        'Terms',
      ]) {
        // The tab bar scrolls on a narrow screen, so a later tab can start
        // off-screen and a plain tap would silently miss it.
        await tester.ensureVisible(find.text(tab));
        await tester.pumpAndSettle();
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab at $size');
      }
    }
  });

  testWidgets('the discount fields sit above the total', (tester) async {
    await _pumpDialog(tester, size: const Size(1920, 1080));

    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('Total Quoted Amount (IN Rs)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
