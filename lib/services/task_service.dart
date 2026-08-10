import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';

class TaskService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _tasksRef =>
      _db.collection('tasks');

  Future<void> addTask(TaskModel task) async {
    await _tasksRef.add(task.toFirestore());
  }

  Future<void> updateTaskStatus(String taskId, bool isCompleted) async {
    await _tasksRef.doc(taskId).update({'isCompleted': isCompleted});
  }

  Future<void> deleteTask(String taskId) async {
    await _tasksRef.doc(taskId).delete();
  }

  Stream<List<TaskModel>> getTasksStream({String? assignedTo, DateTime? dueBefore, DateTime? dueAfter}) {
    Query<Map<String, dynamic>> query = _tasksRef;

    if (assignedTo != null && assignedTo.isNotEmpty) {
      query = query.where('assignedTo', isEqualTo: assignedTo);
    }

    // Sort by dueDate in memory. Combining where(assignedTo) + orderBy(dueDate)
    // requires a composite Firestore index and fails on employee dashboards.
    return query.snapshots().map((snapshot) {
      var tasks = snapshot.docs.map(TaskModel.fromFirestore).toList();
      tasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));

      if (dueBefore != null) {
        tasks = tasks.where((t) => t.dueDate.isBefore(dueBefore)).toList();
      }
      if (dueAfter != null) {
        tasks = tasks.where((t) => t.dueDate.isAfter(dueAfter)).toList();
      }

      return tasks;
    });
  }
}
