import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/task_model.dart';
import '../../services/task_service.dart';

class TasksOverviewPanel extends StatelessWidget {
  final String? employeeUid;
  final bool isAdmin;

  const TasksOverviewPanel({
    super.key,
    this.employeeUid,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    // Determine the start and end of "today"
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.task_alt, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  'Tasks Due Today',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<TaskModel>>(
              stream: TaskService().getTasksStream(
                assignedTo: isAdmin ? null : employeeUid,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final err = snapshot.error.toString();
                  final isIndexError = err.contains('failed-precondition') &&
                      err.contains('index');
                  return Text(
                    isIndexError
                        ? 'Tasks could not load. Ask admin to create the Firestore index from the error link in Firebase Console, or redeploy the latest app build.'
                        : 'Error: $err',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  );
                }

                final tasks = snapshot.data ?? [];
                // Filter for tasks due today and not completed
                final dueTodayTasks = tasks.where((t) {
                  return !t.isCompleted &&
                         t.dueDate.isAfter(startOfToday.subtract(const Duration(seconds: 1))) &&
                         t.dueDate.isBefore(endOfToday.add(const Duration(seconds: 1)));
                }).toList();

                if (dueTodayTasks.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No tasks due today.', style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: dueTodayTasks.length,
                  itemBuilder: (context, index) {
                    final task = dueTodayTasks[index];
                    return FutureBuilder<DocumentSnapshot>(
                      // Lookup employee name if Admin is viewing
                      future: isAdmin ? FirebaseFirestore.instance.collection('users').doc(task.assignedTo).get() : null,
                      builder: (context, userSnap) {
                        String subtitle = task.description;
                        if (isAdmin && userSnap.hasData && userSnap.data != null && userSnap.data!.exists) {
                          final data = userSnap.data!.data() as Map<String, dynamic>;
                          final name = data['name'] ?? 'Unknown Employee';
                          subtitle = 'Assigned to: $name\n$subtitle';
                        }
                        
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: isAdmin 
                            ? null
                            : Checkbox(
                                value: task.isCompleted,
                                onChanged: (val) {
                                  if (val == true) {
                                    TaskService().updateTaskStatus(task.id, true);
                                  }
                                },
                              ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
