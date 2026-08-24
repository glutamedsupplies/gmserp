import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/company_id.dart';
import '../core/utils/password_hasher.dart';
import '../models/company_job_role.dart';
import '../models/company_model.dart';
import '../models/company_task.dart';
import '../models/employee_time_card_profile.dart';
import '../models/staff_assignment.dart';
import '../models/user_model.dart';

class CompanyRepository {
  CompanyRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'companies';

  CollectionReference<Map<String, dynamic>> get _companies =>
      _firestore.collection(collectionName);

  Future<List<CompanyModel>> listCompaniesForMember({
    required String userId,
    String? email,
  }) async {
    final all = await listCompanies();
    final matches = <CompanyModel>[];
    for (final company in all) {
      try {
        final assignment = await getAssignment(
          companyId: company.id,
          userId: userId,
          email: email,
        );
        if (assignment != null) matches.add(company);
      } catch (_) {}
    }
    return matches;
  }

  Future<bool> isCompanyMember({
    required String companyId,
    required String userId,
    String? email,
  }) async {
    final assignment = await getAssignment(
      companyId: companyId,
      userId: userId,
      email: email,
    );
    return assignment != null;
  }

  Future<List<CompanyModel>> listCompanies() async {
    final snapshot = await _companies.get();
    final companies = snapshot.docs
        .map((doc) => CompanyModel.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    companies.sort((a, b) => a.name.compareTo(b.name));
    return companies;
  }

  Future<CompanyModel> getCompanyById(String companyId) async {
    final raw = companyId.trim();
    final id = CompanyId.normalize(raw);

    for (final key in {id, raw, companyId}) {
      if (key.isEmpty) continue;
      final snapshot = await _companies.doc(key).get();
      if (snapshot.exists && snapshot.data() != null) {
        return CompanyModel.fromFirestore(
          id: snapshot.id,
          data: snapshot.data()!,
        );
      }
    }

    if (id.isNotEmpty) {
      final matches = await _companies
          .where('companyId', isEqualTo: id)
          .limit(1)
          .get();
      if (matches.docs.isNotEmpty) {
        final doc = matches.docs.first;
        return CompanyModel.fromFirestore(id: doc.id, data: doc.data());
      }
    }

    throw StateError('Company not found.');
  }

  Future<CompanyModel> createCompany({
    required String companyId,
    required String name,
    required String password,
    required String staffPassword,
    required String createdBy,
  }) async {
    final id = CompanyId.normalize(companyId);
    final existing = await _companies.doc(id).get();
    if (existing.exists) {
      throw StateError('That company ID is already in use.');
    }

    final founderHash = PasswordHasher.hash(password.trim());
    final staffHash = PasswordHasher.hash(staffPassword.trim());
    await _companies.doc(id).set({
      'companyId': id,
      'name': name.trim(),
      'passwordHash': founderHash,
      'staffPasswordHash': staffHash,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final now = DateTime.now();
    return CompanyModel(
      id: id,
      name: name.trim(),
      passwordHash: founderHash,
      staffPasswordHash: staffHash,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> updateCompany({
    required String id,
    required String name,
    String? newPassword,
    String? newStaffPassword,
  }) async {
    final data = <String, dynamic>{
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (newPassword != null && newPassword.isNotEmpty) {
      data['passwordHash'] = PasswordHasher.hash(newPassword.trim());
    }
    if (newStaffPassword != null && newStaffPassword.isNotEmpty) {
      data['staffPasswordHash'] = PasswordHasher.hash(newStaffPassword.trim());
    }
    await _companies.doc(id).set(data, SetOptions(merge: true));
  }

  bool matchesFounderPassword({
    required CompanyModel company,
    required String password,
  }) {
    return PasswordHasher.matches(
      plainText: password,
      hash: company.passwordHash,
    );
  }

  bool matchesStaffCode({
    required CompanyModel company,
    required String code,
  }) {
    final plain = code.trim();
    if (plain.isEmpty || company.staffPasswordHash.isEmpty) return false;
    return PasswordHasher.matches(
      plainText: plain,
      hash: company.staffPasswordHash,
    );
  }

  /// Opens a company for employees/admins using the shared company code only.
  bool unlockCompany({
    required CompanyModel company,
    required String password,
  }) {
    return matchesStaffCode(company: company, code: password);
  }

  Future<void> deleteCompany({
    required CompanyModel company,
    required String password,
  }) async {
    if (!matchesFounderPassword(company: company, password: password)) {
      throw StateError('Incorrect company password.');
    }

    final staff = await _staff(company.id).get();
    final batch = _firestore.batch();
    for (final doc in staff.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_companies.doc(company.id));
    await batch.commit();
  }

  CollectionReference<Map<String, dynamic>> _staff(String companyId) =>
      _companies.doc(companyId).collection('staff');

  Future<List<StaffAssignment>> listStaff(String companyId) async {
    final docId = await _resolveCompanyDocId(companyId);
    return listStaffByDocumentId(docId);
  }

  Future<List<StaffAssignment>> listStaffByDocumentId(String documentId) async {
    final snapshot = await _staff(documentId).get();
    return snapshot.docs
        .map(
          (doc) => StaffAssignment.fromFirestore(id: doc.id, data: doc.data()),
        )
        .toList();
  }

  Future<List<StaffMembershipListing>> listAllStaffMemberships() async {
    final snapshot = await _companies.get();
    final listings = <StaffMembershipListing>[];
    for (final doc in snapshot.docs) {
      try {
        final company = CompanyModel.fromFirestore(id: doc.id, data: doc.data());
        final members = await listStaffByDocumentId(doc.id);
        for (final assignment in members) {
          listings.add(
            StaffMembershipListing(
              companyDocumentId: doc.id,
              company: company,
              assignment: assignment,
            ),
          );
        }
      } catch (_) {}
    }
    return listings;
  }

  Future<StaffAssignment?> getAssignment({
    required String companyId,
    required String userId,
    String? email,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    try {
      final snapshot = await _staff(docId).doc(userId).get();
      if (snapshot.exists && snapshot.data() != null) {
        return StaffAssignment.fromFirestore(
          id: snapshot.id,
          data: snapshot.data()!,
        );
      }
    } catch (_) {}

    try {
      final staff = await listStaff(docId);
      final needle = email?.trim().toLowerCase();
      for (final member in staff) {
        if (member.userId == userId) return member;
        if (needle != null &&
            needle.isNotEmpty &&
            member.email.trim().toLowerCase() == needle) {
          return member;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> assignStaff({
    required String companyId,
    required StaffAssignment assignment,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    await _staff(docId).doc(assignment.userId).set({
      ...assignment.toFirestore(),
      'userId': assignment.userId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Saves daily rate + weekly time in/out schedule for one staff member.
  Future<void> saveStaffTimeCardProfile({
    required String companyId,
    required String userId,
    required EmployeeTimeCardProfile profile,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    await _staff(docId).doc(userId).set({
      ...profile.toStaffFields(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> ensureStaffMember({
    required String companyId,
    required UserModel user,
  }) async {
    final existing = await getAssignment(
      companyId: companyId,
      userId: user.id,
    );
    await assignStaff(
      companyId: companyId,
      assignment: StaffAssignment(
        userId: user.id,
        username: user.username,
        email: user.email,
        roleId: existing?.roleId ?? '',
        jobRole: existing?.jobRole ?? '',
        tasks: existing?.tasks ?? const [],
      ),
    );
  }

  Future<void> removeStaff({
    required String companyId,
    required String userId,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    await _staff(docId).doc(userId).delete();
  }

  /// Removes a user from every company's staff subcollection (tasks + assignments).
  Future<void> removeUserFromAllCompanies({required String userId}) async {
    final snapshot = await _companies.get();
    for (final doc in snapshot.docs) {
      try {
        final staffRef = _staff(doc.id).doc(userId);
        final existing = await staffRef.get();
        if (existing.exists) {
          await staffRef.delete();
        }
      } catch (_) {}
    }
  }

  Future<List<CompanyTaskListing>> listAllTasks() async {
    final snapshot = await _companies.get();
    final listings = <CompanyTaskListing>[];
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        final company = CompanyModel.fromFirestore(id: doc.id, data: data);
        final tasks = [
          ..._tasksFromCompany(data),
          ...await _folderTasks(doc.id),
        ];
        final seen = <String>{};
        for (final task in tasks) {
          if (!seen.add(task.id)) continue;
          listings.add(CompanyTaskListing(company: company, task: task));
        }
      } catch (_) {}
    }
    listings.sort((a, b) {
      final aDate = a.task.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.task.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;
      return a.task.title.toLowerCase().compareTo(b.task.title.toLowerCase());
    });
    return listings;
  }

  Future<List<CompanyRoleListing>> listAllRoles() async {
    final snapshot = await _companies.get();
    final listings = <CompanyRoleListing>[];
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        final company = CompanyModel.fromFirestore(id: doc.id, data: data);
        final roles = _rolesFromCompany(data);
        for (final role in roles) {
          listings.add(CompanyRoleListing(company: company, role: role));
        }
      } catch (_) {}
    }
    listings.sort((a, b) {
      final byName =
          a.role.name.toLowerCase().compareTo(b.role.name.toLowerCase());
      if (byName != 0) return byName;
      return a.company.name.toLowerCase().compareTo(b.company.name.toLowerCase());
    });
    return listings;
  }

  Future<List<CompanyJobRole>> listRoles(String companyId) async {
    final docId = await _resolveCompanyDocId(companyId);
    final company = await _companies.doc(docId).get();
    final roles = _rolesFromCompany(company.data());
    roles.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return roles;
  }

  Future<CompanyJobRole> addRole({
    required String companyId,
    required String name,
    String description = '',
  }) async {
    final role = CompanyJobRole(
      id: _companies.doc().id,
      name: name.trim(),
      description: description.trim(),
    );
    final docId = await _resolveCompanyDocId(companyId);
    try {
      await _companies.doc(docId).update({
        'roles.${role.id}': role.toFirestore(),
      });
    } on FirebaseException {
      await _companies.doc(docId).set({
        'roles': {role.id: role.toFirestore()},
      }, SetOptions(merge: true));
    }
    return role;
  }

  Future<CompanyJobRole> updateRole({
    required String companyId,
    required CompanyJobRole role,
    required String name,
    String description = '',
  }) async {
    final updated = role.copyWith(
      name: name.trim(),
      description: description.trim(),
    );
    final docId = await _resolveCompanyDocId(companyId);
    final payload = updated.toFirestore();
    try {
      await _companies.doc(docId).update({
        'roles.${role.id}': payload,
      });
    } on FirebaseException {
      await _companies.doc(docId).set({
        'roles': {role.id: payload},
      }, SetOptions(merge: true));
    }

    // Keep task role labels in sync when the role is renamed.
    if (updated.name != role.name) {
      final companyTasks = await listTasks(docId);
      for (final task in companyTasks) {
        if (task.roleId != role.id) continue;
        try {
          await updateTask(
            companyId: docId,
            task: task,
            title: task.title,
            description: task.description,
            roleId: task.roleId,
            roleName: updated.name,
          );
        } catch (_) {}
      }

      try {
        final members = await listStaff(docId);
        for (final member in members) {
          if (member.roleId != role.id) continue;
          await assignStaff(
            companyId: docId,
            assignment: StaffAssignment(
              userId: member.userId,
              username: member.username,
              email: member.email,
              roleId: member.roleId,
              jobRole: updated.name,
              tasks: member.tasks,
            ),
          );
        }
      } catch (_) {}
    }

    return updated;
  }

  Future<void> deleteRole({
    required String companyId,
    required String roleId,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    try {
      await _companies.doc(docId).update({
        'roles.$roleId': FieldValue.delete(),
      });
    } catch (_) {}
    try {
      await _companies.doc(docId).update({
        FieldPath(['roles.$roleId']): FieldValue.delete(),
      });
    } catch (_) {}
  }

  Future<List<CompanyTask>> listTasks(String companyId) async {
    final company = await _companies.doc(companyId).get();
    final tasks = [
      ..._tasksFromCompany(company.data()),
      ...await _folderTasks(companyId),
    ];
    final seen = <String>{};
    final unique = [
      for (final task in tasks)
        if (seen.add(task.id)) task,
    ];
    unique.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return unique;
  }

  Future<CompanyTask> addTask({
    required String companyId,
    required String title,
    String description = '',
    String roleId = '',
    String roleName = '',
  }) async {
    final now = DateTime.now();
    final task = CompanyTask(
      id: _companies.doc().id,
      title: title.trim(),
      description: description.trim(),
      roleId: roleId.trim(),
      roleName: roleName.trim(),
      createdAt: now,
    );
    final payload = {
      ...task.toFirestore(),
      'createdAt': now.toIso8601String(),
    };
    final docId = await _resolveCompanyDocId(companyId);
    try {
      await _companies.doc(docId).update({
        'tasks.${task.id}': payload,
      });
    } on FirebaseException {
      await _companies.doc(docId).set({
        'tasks': {task.id: payload},
      }, SetOptions(merge: true));
    }
    return task;
  }

  Future<CompanyTask> updateTask({
    required String companyId,
    required CompanyTask task,
    required String title,
    String description = '',
    String? roleId,
    String? roleName,
  }) async {
    final updated = task.copyWith(
      title: title.trim(),
      description: description.trim(),
      roleId: roleId ?? task.roleId,
      roleName: roleName ?? task.roleName,
      updatedAt: DateTime.now(),
    );
    final payload = {
      ...updated.toFirestore(),
      if (updated.createdAt != null)
        'createdAt': updated.createdAt!.toIso8601String(),
      'updatedAt': updated.updatedAt!.toIso8601String(),
    };
    final docId = await _resolveCompanyDocId(companyId);
    try {
      await _companies.doc(docId).update({
        'tasks.${task.id}': payload,
        FieldPath(['tasks.${task.id}']): payload,
      });
    } on FirebaseException {
      await _companies.doc(docId).set({
        'tasks': {task.id: payload},
      }, SetOptions(merge: true));
    }
    try {
      await _companies.doc(docId).collection('tasks').doc(task.id).set(
            payload,
            SetOptions(merge: true),
          );
    } catch (_) {}
    return updated;
  }

  Future<void> deleteTask({
    required String companyId,
    required String taskId,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    try {
      await _companies.doc(docId).update({
        'tasks.$taskId': FieldValue.delete(),
      });
    } catch (_) {}
    try {
      await _companies.doc(docId).update({
        FieldPath(['tasks.$taskId']): FieldValue.delete(),
      });
    } catch (_) {}
    try {
      await _companies.doc(docId).collection('tasks').doc(taskId).delete();
    } catch (_) {}
  }

  Future<String> _resolveCompanyDocId(String companyId) async {
    final raw = companyId.trim();
    final id = CompanyId.normalize(raw);
    for (final key in {id, raw, companyId}) {
      if (key.isEmpty) continue;
      final snapshot = await _companies.doc(key).get();
      if (snapshot.exists) return snapshot.id;
    }
    if (id.isNotEmpty) {
      final matches = await _companies
          .where('companyId', isEqualTo: id)
          .limit(1)
          .get();
      if (matches.docs.isNotEmpty) return matches.docs.first.id;
    }
    final snapshot = await _companies.get();
    final needle = raw.toLowerCase();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final name = data['name']?.toString().trim().toLowerCase() ?? '';
      final stored = CompanyId.normalize(data['companyId']?.toString() ?? '');
      if (name == needle || (id.isNotEmpty && stored == id)) {
        return doc.id;
      }
    }
    return id.isNotEmpty ? id : raw;
  }

  Future<List<CompanyTask>> _folderTasks(String companyId) async {
    try {
      final folder = await _companies.doc(companyId).collection('tasks').get();
      return folder.docs
          .map(
            (doc) => CompanyTask.fromFirestore(id: doc.id, data: doc.data()),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<CompanyTask> _tasksFromCompany(Map<String, dynamic>? data) {
    if (data == null) return [];
    final tasks = <String, CompanyTask>{};

    void add(String id, dynamic value) {
      final taskId = id.trim();
      if (taskId.isEmpty || value is! Map) return;
      tasks[taskId] = CompanyTask.fromFirestore(
        id: taskId,
        data: Map<String, dynamic>.from(value),
      );
    }

    final nested = data['tasks'];
    if (nested is Map) {
      for (final entry in nested.entries) {
        add(entry.key.toString(), entry.value);
      }
    }

    for (final entry in data.entries) {
      final key = entry.key.toString();
      if (key.startsWith('tasks.') && key.length > 6) {
        add(key.substring(6), entry.value);
      }
    }

    return tasks.values.toList();
  }

  List<CompanyJobRole> _rolesFromCompany(Map<String, dynamic>? data) {
    if (data == null) return [];
    final roles = <String, CompanyJobRole>{};

    void add(String id, dynamic value) {
      final roleId = id.trim();
      if (roleId.isEmpty || value is! Map) return;
      roles[roleId] = CompanyJobRole.fromFirestore(
        id: roleId,
        data: Map<String, dynamic>.from(value),
      );
    }

    final nested = data['roles'];
    if (nested is Map) {
      for (final entry in nested.entries) {
        add(entry.key.toString(), entry.value);
      }
    }

    for (final entry in data.entries) {
      final key = entry.key.toString();
      if (key.startsWith('roles.') && key.length > 6) {
        add(key.substring(6), entry.value);
      }
    }

    return roles.values.toList();
  }
}
