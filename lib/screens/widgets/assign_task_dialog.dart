import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../models/task_model.dart';
import '../../services/task_service.dart';

class AssignTaskDialog extends StatefulWidget {
  const AssignTaskDialog({super.key});

  @override
  State<AssignTaskDialog> createState() => _AssignTaskDialogState();
}

class _AssignTaskDialogState extends State<AssignTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  String? _selectedEmployeeId;
  bool _isLoading = true;
  bool _isSaving = false;

  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      // Admins might want to assign to anyone, but let's filter to just show users (or maybe everyone)
      final List<Map<String, dynamic>> emps = [];
      for (var doc in snap.docs) {
        final data = doc.data();
        emps.add({
          'uid': doc.id,
          'name': data['name'] ?? data['email'] ?? 'Unknown',
          'role': data['role'] ?? 'Employee',
        });
      }
      setState(() {
        _employees = emps;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2050),
    );
    if (date != null && mounted) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _assignTask() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an employee')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final admin = FirebaseAuth.instance.currentUser;
      if (admin == null) return;

      final task = TaskModel(
        id: '',
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        assignedBy: admin.uid,
        assignedTo: _selectedEmployeeId!,
        dueDate: _selectedDate,
        createdAt: DateTime.now(),
        isCompleted: false,
      );

      await TaskService().addTask(task);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task assigned successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning task: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Assign Task'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task Title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) =>
                      val == null || val.isEmpty ? 'Enter a title' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Task Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (val) =>
                      val == null || val.isEmpty ? 'Enter a description' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Assign To',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedEmployeeId,
                  items: _employees.map((e) {
                    return DropdownMenuItem<String>(
                      value: e['uid'],
                      child: Text('${e['name']} (${e['role']})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() => _selectedEmployeeId = val);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Due Date: ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _pickDate,
                      child: const Text('Change Date'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _assignTask,
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Assign'),
        ),
      ],
    );
  }
}
