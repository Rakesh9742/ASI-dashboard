import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class QmsService {
  final ApiService _apiService = ApiService();

  // Helper method to get headers with token
  Map<String, String> _getHeaders({String? token}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // Get filter options (projects, domains, milestones, blocks)
  Future<Map<String, dynamic>> getFilterOptions({String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/qms/filters'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to load filter options');
      }
    } catch (e) {
      throw Exception('Error getting filter options: $e');
    }
  }

  // Get all checklists for a block
  Future<List<dynamic>> getChecklistsForBlock(int blockId, {String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/qms/blocks/$blockId/checklists'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data is List ? data : [];
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to load checklists');
      }
    } catch (e) {
      throw Exception('Error getting checklists: $e');
    }
  }

  // Get checklist with all check items
  Future<Map<String, dynamic>> getChecklistWithItems(int checklistId, {String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/qms/checklists/$checklistId'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to load checklist');
      }
    } catch (e) {
      throw Exception('Error getting checklist: $e');
    }
  }

  // Get check item details with report data
  Future<Map<String, dynamic>> getCheckItem(int checkItemId, {String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/qms/check-items/$checkItemId'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to load check item');
      }
    } catch (e) {
      throw Exception('Error getting check item: $e');
    }
  }

  // Execute Fill Action (fetch CSV report)
  Future<Map<String, dynamic>> executeFillAction(
    int checkItemId,
    String reportPath, {
    String? token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/qms/check-items/$checkItemId/fill-action'),
        headers: _getHeaders(token: token),
        body: json.encode({'report_path': reportPath}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to execute fill action');
      }
    } catch (e) {
      throw Exception('Error executing fill action: $e');
    }
  }

  // Update check item (engineer: fix details, comments)
  Future<Map<String, dynamic>> updateCheckItem(
    int checkItemId, {
    String? fixDetails,
    String? engineerComments,
    String? description,
    String? token,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (fixDetails != null) body['fix_details'] = fixDetails;
      if (engineerComments != null) body['engineer_comments'] = engineerComments;
      if (description != null) body['description'] = description;

      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/qms/check-items/$checkItemId'),
        headers: _getHeaders(token: token),
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to update check item');
      }
    } catch (e) {
      throw Exception('Error updating check item: $e');
    }
  }

  // Submit check item for approval
  Future<Map<String, dynamic>> submitCheckItemForApproval(
    int checkItemId, {
    String? token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/qms/check-items/$checkItemId/submit'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to submit check item');
      }
    } catch (e) {
      throw Exception('Error submitting check item: $e');
    }
  }

  // Approve/Reject check item (approver)
  Future<Map<String, dynamic>> approveCheckItem(
    int checkItemId,
    bool approved, {
    String? comments,
    String? token,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/qms/check-items/$checkItemId/approve'),
        headers: _getHeaders(token: token),
        body: json.encode({
          'approved': approved,
          'comments': comments,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to approve/reject check item');
      }
    } catch (e) {
      throw Exception('Error approving check item: $e');
    }
  }

  // Assign approver to check item (lead only)
  Future<Map<String, dynamic>> assignApprover(
    int checkItemId,
    int approverId, {
    String? token,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/qms/check-items/$checkItemId/assign-approver'),
        headers: _getHeaders(token: token),
        body: json.encode({'approver_id': approverId}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to assign approver');
      }
    } catch (e) {
      throw Exception('Error assigning approver: $e');
    }
  }

  // Get audit trail for check item
  Future<List<dynamic>> getCheckItemHistory(int checkItemId, {String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/qms/check-items/$checkItemId/history'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data is List ? data : [];
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to load history');
      }
    } catch (e) {
      throw Exception('Error getting check item history: $e');
    }
  }

  // Submit entire checklist
  Future<Map<String, dynamic>> submitChecklist(
    int checklistId, {
    String? engineerComments,
    String? token,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (engineerComments != null && engineerComments.isNotEmpty) {
        body['engineer_comments'] = engineerComments;
      }

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/qms/checklists/$checklistId/submit'),
        headers: _getHeaders(token: token),
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to submit checklist');
      }
    } catch (e) {
      throw Exception('Error submitting checklist: $e');
    }
  }

  // Get block submission status
  Future<Map<String, dynamic>> getBlockStatus(int blockId, {String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/qms/blocks/$blockId/status'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to load block status');
      }
    } catch (e) {
      throw Exception('Error getting block status: $e');
    }
  }

  // Assign approver to all check items in a checklist (lead only)
  Future<Map<String, dynamic>> assignApproverToChecklist(
    int checklistId,
    int approverId, {
    String? token,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/qms/checklists/$checklistId/assign-approver'),
        headers: _getHeaders(token: token),
        body: json.encode({'approver_id': approverId}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to assign approver');
      }
    } catch (e) {
      throw Exception('Error assigning approver to checklist: $e');
    }
  }

  // Batch approve or reject multiple check items
  Future<Map<String, dynamic>> batchApproveRejectCheckItems(
    List<int> checkItemIds,
    bool approved, {
    String? comments,
    String? token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/qms/check-items/batch-approve-reject'),
        headers: _getHeaders(token: token),
        body: json.encode({
          'check_item_ids': checkItemIds,
          'approved': approved,
          'comments': comments,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to batch approve/reject check items');
      }
    } catch (e) {
      throw Exception('Error batch approving/rejecting check items: $e');
    }
  }

  // Update checklist (name)
  Future<Map<String, dynamic>> updateChecklist(
    int checklistId,
    String name, {
    String? token,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/qms/checklists/$checklistId'),
        headers: _getHeaders(token: token),
        body: json.encode({'name': name}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to update checklist');
      }
    } catch (e) {
      throw Exception('Error updating checklist: $e');
    }
  }

  // Delete checklist
  Future<void> deleteChecklist(int checklistId, {String? token}) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/qms/checklists/$checklistId'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode != 200) {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to delete checklist');
      }
    } catch (e) {
      throw Exception('Error deleting checklist: $e');
    }
  }

  // Get available approvers for a checklist (excluding submitting engineer)
  Future<List<dynamic>> getApproversForChecklist(int checklistId, {String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/qms/checklists/$checklistId/approvers'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data is List ? data : [];
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to load approvers');
      }
    } catch (e) {
      throw Exception('Error getting approvers for checklist: $e');
    }
  }

  // Upload Excel template
  Future<Map<String, dynamic>> uploadTemplate(
    int blockId,
    List<int> fileBytes,
    String fileName, {
    String? checklistName,
    int? milestoneId,
    String? stage,
    String? token,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiService.baseUrl}/qms/blocks/$blockId/upload-template'),
      );

      request.headers.addAll(_getHeaders(token: token));
      request.files.add(
        http.MultipartFile.fromBytes(
          'template',
          fileBytes,
          filename: fileName,
        ),
      );

      if (checklistName != null) {
        request.fields['checklist_name'] = checklistName;
      }
      if (milestoneId != null) {
        request.fields['milestone_id'] = milestoneId.toString();
      }
      if (stage != null) {
        request.fields['stage'] = stage;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to upload template');
      }
    } catch (e) {
      throw Exception('Error uploading template: $e');
    }
  }

  // Get checklist version history (snapshots)
  Future<List<dynamic>> getChecklistHistory(int checklistId, {String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/qms/checklists/$checklistId/history'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data is List ? data : [];
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to load checklist history');
      }
    } catch (e) {
      throw Exception('Error getting checklist history: $e');
    }
  }

  // Get a specific checklist version snapshot
  Future<Map<String, dynamic>> getChecklistVersion(int versionId, {String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/qms/versions/$versionId'),
        headers: _getHeaders(token: token),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to load checklist version');
      }
    } catch (e) {
      throw Exception('Error getting checklist version: $e');
    }
  }
}

