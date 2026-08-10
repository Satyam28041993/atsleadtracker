import 'dart:io';

void main() {
  final file = File('lib/services/analytics_service.dart');
  String content = file.readAsStringSync();

  final startStr = '  Future<({List<DailyWorkReport> employeeReports, GlobalDailySummary summary})> getDailyWorkReport({DateTime? targetDate}) async {';
  
  final endStr = '    return (employeeReports: employeeReports, summary: summary);\n  }';
  
  final startIndex = content.indexOf(startStr);
  final endIndex = content.indexOf(endStr, startIndex);
  
  if (startIndex == -1 || endIndex == -1) {
    print('Could not find getDailyWorkReport');
    return;
  }

  final newMethod = '''
  Future<({List<DailyWorkReport> employeeReports, GlobalDailySummary summary})> getDailyWorkReport({
    DateTime? targetDate,
    String? forEmployeeUid,
  }) async {
    final date = targetDate ?? DateTime.now();
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    Query leadsQuery = _firestore.collection('leads');
    if (forEmployeeUid != null) {
      leadsQuery = leadsQuery.where('assignedTo', isEqualTo: forEmployeeUid);
    }
    final leadsSnap = await leadsQuery.get();
    final leads = leadsSnap.docs.map(Lead.fromFirestore).toList();

    List<AppUser> employees = [];
    if (forEmployeeUid != null) {
      final userDoc = await _firestore.collection('users').doc(forEmployeeUid).get();
      if (userDoc.exists) {
        employees = [AppUser.fromFirestore(userDoc)];
      }
    } else {
      final usersSnap = await _firestore.collection('users').get();
      employees = usersSnap.docs
          .map(AppUser.fromFirestore)
          .where((u) => u.role == 'employee')
          .toList();
    }

    final allEventsDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    if (forEmployeeUid != null) {
      // Employees cannot use collectionGroup due to firestore rules.
      for (final l in leads) {
        try {
          final evSnap = await _firestore
              .collection('leads')
              .doc(l.id)
              .collection('events')
              .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
              .where('timestamp', isLessThanOrEqualTo: endOfDay)
              .get();
          allEventsDocs.addAll(evSnap.docs);
        } catch (_) {}
      }
    } else {
      try {
        final eventsSnap = await _firestore
            .collectionGroup('events')
            .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
            .where('timestamp', isLessThanOrEqualTo: endOfDay)
            .get();
        allEventsDocs.addAll(eventsSnap.docs);
      } catch (e) {
        // Fallback if collectionGroup fails (e.g. index missing or permissions)
        for (final l in leads) {
          try {
            final evSnap = await _firestore
                .collection('leads')
                .doc(l.id)
                .collection('events')
                .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
                .where('timestamp', isLessThanOrEqualTo: endOfDay)
                .get();
            allEventsDocs.addAll(evSnap.docs);
          } catch (_) {}
        }
      }
    }

    Query quotesQuery = _firestore.collection('quotations')
        .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
        .where('createdAt', isLessThanOrEqualTo: endOfDay);
        
    if (forEmployeeUid != null) {
      quotesQuery = quotesQuery.where('employeeId', isEqualTo: forEmployeeUid);
    }
    
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allQuotations = [];
    try {
      final quotationsSnap = await quotesQuery.get();
      allQuotations = quotationsSnap.docs as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    } catch (_) {
      // In case quotations fail for any reason, we just treat it as 0 quotes.
    }

    int gTotalLeadsAdded = 0;
    int gTotalFollowUpsDone = 0;
    int gTotalQuotesMade = 0;
    int gTotalDealsWon = 0;
    double gTotalValueWon = 0;

    final employeeReports = <DailyWorkReport>[];

    for (final emp in employees) {
      final String uid = emp.uid;
      final String name = emp.name.isNotEmpty ? emp.name : emp.uid;

      final addedIds = <String>{};
      final followUpIds = <String>{};
      final pendingFollowUpIds = <String>{};
      final statusChangeIds = <String>{};
      final quoteIds = <String>{};
      final wonIds = <String>{};
      double wonValue = 0;

      for (final lead in leads) {
        if (lead.assignedTo == uid) {
          if (lead.leadDate.year == date.year && lead.leadDate.month == date.month && lead.leadDate.day == date.day) {
            addedIds.add(lead.id);
            gTotalLeadsAdded++;
          }
          if (lead.nextFollowUpDate != null && 
              lead.nextFollowUpDate!.year == date.year && 
              lead.nextFollowUpDate!.month == date.month && 
              lead.nextFollowUpDate!.day == date.day &&
              lead.status != 'Won' && lead.status != 'Lost' && lead.status != 'Loss') {
            pendingFollowUpIds.add(lead.id);
          }
        }
      }

      for (final doc in allEventsDocs) {
        final data = doc.data();
        final eventUserId = data['userId'] as String?;
        final eventLeadId = data['leadId'] as String?;
        if (eventUserId == uid && eventLeadId != null) {
          final type = data['type'] as String?;
          if (type == 'follow_up' || type == 'contact') {
            followUpIds.add(eventLeadId);
            gTotalFollowUpsDone++;
          } else if (type == 'status_change') {
            statusChangeIds.add(eventLeadId);
            final newStatus = data['newStatus'] as String?;
            if (newStatus == 'Won') {
              wonIds.add(eventLeadId);
              final l = leads.where((l) => l.id == eventLeadId).firstOrNull;
              if (l != null) {
                wonValue += l.totalAmount;
                gTotalValueWon += l.totalAmount;
              }
              gTotalDealsWon++;
            }
          }
        }
      }

      for (final doc in allQuotations) {
        final data = doc.data();
        final quoteEmpId = data['employeeId'] as String?;
        final quoteLeadId = data['leadId'] as String?;
        if (quoteEmpId == uid && quoteLeadId != null) {
          quoteIds.add(quoteLeadId);
          gTotalQuotesMade++;
        }
      }

      employeeReports.add(DailyWorkReport(
        employeeUid: uid,
        employeeName: name,
        leadsAdded: addedIds.length,
        followUpsDone: followUpIds.length,
        followUpsPending: pendingFollowUpIds.length,
        statusChanges: statusChangeIds.length,
        quotesMade: quoteIds.length,
        dealsWon: wonIds.length,
        dealsWonValue: wonValue,
        addedLeadIds: addedIds.toList(),
        followUpLeadIds: followUpIds.toList(),
        pendingFollowUpLeadIds: pendingFollowUpIds.toList(),
        statusChangeLeadIds: statusChangeIds.toList(),
        quotedLeadIds: quoteIds.toList(),
        wonLeadIds: wonIds.toList(),
      ));
    }

    final summary = GlobalDailySummary(
      totalLeadsAdded: gTotalLeadsAdded,
      totalFollowUpsDone: gTotalFollowUpsDone,
      totalQuotesMade: gTotalQuotesMade,
      totalDealsWon: gTotalDealsWon,
      totalValueWon: gTotalValueWon,
    );

''';

  content = content.replaceRange(startIndex, endIndex, newMethod);
  file.writeAsStringSync(content);
  print('Replaced getDailyWorkReport');
}
