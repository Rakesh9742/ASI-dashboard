import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/qms_service.dart';

class ChecklistUploadDialog extends ConsumerStatefulWidget {
  final int blockId;
  final VoidCallback onSuccess;

  const ChecklistUploadDialog({
    super.key,
    required this.blockId,
    required this.onSuccess,
  });

  @override
  ConsumerState<ChecklistUploadDialog> createState() => _ChecklistUploadDialogState();
}

class _ChecklistUploadDialogState extends ConsumerState<ChecklistUploadDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _qmsService = QmsService();
  
  PlatformFile? _selectedFile;
  bool _isUploading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        // On web, we need to ensure we get bytes
        withData: true, 
      );

      if (result != null) {
        setState(() {
          _selectedFile = result.files.first;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file'), backgroundColor: Colors.red),
      );
      return;
    }

    final authState = ref.read(authProvider);
    final token = authState.token;
    if (token == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      await _qmsService.uploadChecklistTemplate(
        blockId: widget.blockId,
        name: _nameController.text.trim(),
        file: _selectedFile!,
        token: token,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checklist created successfully'), backgroundColor: Colors.green),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Checklist Template'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Checklist Name',
                  hintText: 'e.g., Block 1 Design Review',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text('Excel Template File (*.xlsx)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickFile,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.grey.shade50,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedFile?.name ?? 'Tap to select file',
                          style: TextStyle(
                            color: _selectedFile != null ? Colors.black : Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_selectedFile != null)
                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    ],
                  ),
                ),
              ),
              if (_selectedFile == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Ensure file has columns: Check ID, Category, Check Description',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _upload,
          child: _isUploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Upload'),
        ),
      ],
    );
  }
}
