import '../core/utils/company_id.dart';
import '../core/utils/firebase_data.dart';
import '../core/utils/password_hasher.dart';
import '../models/company_job_role.dart';
import '../models/company_model.dart';
import '../models/company_task.dart';
import '../models/employee_time_card_profile.dart';
import '../models/staff_assignment.dart';
import '../models/time_card_profile_change.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';
import 'time_card_profile_change_repository.dart';

class CompanyRepository {
  CompanyRepository({
    RtdbService? rtdb,
    TimeCardProfileChangeRepository? profileChanges,
  })  : _rtdb = rtdb ?? RtdbService(),
        _profileChanges =
            profileChanges ?? TimeCardProfileChangeRepository();

  final RtdbService _rtdb;
  final TimeCardProfileChangeRepository _profileChanges;

  static const String collectionName = RtdbPaths.companies;

  String _companyPath(String companyId) => '${RtdbPaths.companies}/$companyId';

  String _staffPath(String companyDocId, String userId) =>
      '${_companyPath(companyDocId)}/staff/$userId';

  String _taskFolderPath(String companyDocId, String taskId) =>
      '${_companyPath(companyDocId)}/tasks/$taskId';

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
    final children = await _rtdb.getChildren(RtdbPaths.companies);
    final companies = children.entries
        .map(
          (entry) =>
              CompanyModel.fromFirestore(id: entry.key, data: entry.value),
        )
        .toList();
    companies.sort((a, b) => a.name.compareTo(b.name));
    return companies;
  }

  Future<CompanyModel> getCompanyById(String companyId) async {
    final raw = companyId.trim();
    final id = CompanyId.normalize(raw);

    for (final key in {id, raw, companyId}) {
      if (key.isEmpty) continue;
      final data = await _rtdb.getMap(_companyPath(key));
      if (data != null) {
        return CompanyModel.fromFirestore(id: key, data: data);
      }
    }

    if (id.isNotEmpty) {
      final all = await listCompanies();
      for (final company in all) {
        if (company.id == id) return company;
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
    final existing = await _rtdb.getMap(_companyPath(id));
    if (existing != null) {
      throw StateError('That company ID is already in use.');
    }

    final founderHash = PasswordHasher.hash(password.trim());
    final staffHash = PasswordHasher.hash(staffPassword.trim());
    await _rtdb.set(_companyPath(id), {
      'companyId': id,
      'name': name.trim(),
      'passwordHash': founderHash,
      'staffPasswordHash': staffHash,
      'createdBy': createdBy,
      'createdAt': serverTimestamp(),
      'updatedAt': serverTimestamp(),
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
    final docId = await _resolveCompanyDocId(id);
    final data = <String, dynamic>{
      'name': name.trim(),
      'updatedAt': serverTimestamp(),
    };
    if (newPassword != null && newPassword.isNotEmpty) {
      data['passwordHash'] = PasswordHasher.hash(newPassword.trim());
    }
    if (newStaffPassword != null && newStaffPassword.isNotEmpty) {
      data['staffPasswordHash'] = PasswordHasher.hash(newStaffPassword.trim());
    }
    await _rtdb.merge(_companyPath(docId), data);
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

    final docId = await _resolveCompanyDocId(company.id);
    final staff = await _rtdb.getChildren('${_companyPath(docId)}/staff');
    for (final userId in staff.keys) {
      await _rtdb.remove(_staffPath(docId, userId));
    }
    await _rtdb.remove(_companyPath(docId));
  }

  Future<List<StaffAssignment>> listStaff(String companyId) async {
    final docId = await _resolveCompanyDocId(companyId);
    return listStaffByDocumentId(docId);
  }

  Future<List<StaffAssignment>> listStaffByDocumentId(String documentId) async {
    final snapshot = await _rtdb.getChildren('${_companyPath(documentId)}/staff');
    return snapshot.entries
        .map(
          (entry) =>
              StaffAssignment.fromFirestore(id: entry.key, data: entry.value),
        )
        .toList();
  }

  Future<List<StaffMembershipListing>> listAllStaffMemberships() async {
    final children = await _rtdb.getChildren(RtdbPaths.companies);
    final listings = <StaffMembershipListing>[];
    for (final entry in children.entries) {
      try {
        final company =
            CompanyModel.fromFirestore(id: entry.key, data: entry.value);
        final members = await listStaffByDocumentId(entry.key);
        for (final assignment in members) {
          listings.add(
            StaffMembershipListing(
              companyDocumentId: entry.key,
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
      final data = await _rtdb.getMap(_staffPath(docId, userId));
      if (data != null) {
        return StaffAssignment.fromFirestore(id: userId, data: data);
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
    await _rtdb.merge(_staffPath(docId, assignment.userId), {
      ...assignment.toFirestore(),
      'userId': assignment.userId,
      'updatedAt': serverTimestamp(),
    });
  }

  /// Replaces [timeCardWeek] entirely (non-numeric `d1`…`d7` keys) so RTDB
  /// does not coerce weekday maps into arrays and wipe Saturday/Sunday.
  ///
  /// When [actor] is set and the profile changed, writes an audit row to
  /// [RtdbPaths.timeCardProfileChanges] for the Activity / Notifications page.
  Future<TimeCardProfileChange?> saveStaffTimeCardProfile({
    required String companyId,
    required String userId,
    required EmployeeTimeCardProfile profile,
    String? companyDocumentId,
    String companyName = '',
    String employeeName = '',
    String employeeEmail = '',
    String? actorId,
    String actorName = '',
    List<String> recipientIds = const [],
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    final existing = await getAssignment(companyId: companyId, userId: userId);
    final previousProfile =
        existing?.timeCardProfile ?? EmployeeTimeCardProfile.defaults();

    final staffPath = _staffPath(docId, userId);
    await _rtdb.merge(staffPath, {
      'timeCardDailyRate': profile.dailyRate,
      'updatedAt': serverTimestamp(),
    });
    await _rtdb.set(
      '$staffPath/timeCardWeek',
      profile.weeklySchedule.toFirestore(),
    );

    final actor = actorId?.trim() ?? '';
    if (actor.isEmpty ||
        TimeCardProfileChange.profilesEqual(previousProfile, profile)) {
      return null;
    }

    final recipients = recipientIds.toSet()..add(userId)..add(actor);
    return _profileChanges.create(
      companyId: companyId,
      companyDocumentId: companyDocumentId ?? docId,
      companyName: companyName,
      employeeId: userId,
      employeeName: employeeName.isNotEmpty
          ? employeeName
          : (existing?.username ?? 'Employee'),
      employeeEmail:
          employeeEmail.isNotEmpty ? employeeEmail : (existing?.email ?? ''),
      actorId: actor,
      actorName: actorName.isNotEmpty ? actorName : 'Admin',
      previousRate: previousProfile.dailyRate,
      newRate: profile.dailyRate,
      previousScheduleSummary: previousProfile.weeklySchedule.summaryLabel,
      newScheduleSummary: profile.weeklySchedule.summaryLabel,
      recipientIds: recipients.toList(),
    );
  }

  Future<int> getClockDeclineCount({
    required String companyId,
    required String userId,
  }) async {
    final assignment = await getAssignment(companyId: companyId, userId: userId);
    return assignment?.clockDeclineCount ?? 0;
  }

  Future<void> incrementClockDeclineCount({
    required String companyId,
    required String userId,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    await _rtdb.merge(_staffPath(docId, userId), {
      'clockDeclineCount': increment(1),
      'updatedAt': serverTimestamp(),
    });
  }

  Future<void> resetClockDeclineCount({
    required String companyId,
    required String userId,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    await _rtdb.merge(_staffPath(docId, userId), {
      'clockDeclineCount': 0,
      'updatedAt': serverTimestamp(),
    });
  }

  Future<void> ensureStaffMember({
    required String companyId,
    required UserModel user,
    UserRole accessLevel = UserRole.employee,
    bool overwriteAccessLevel = false,
  }) async {
    final existing = await getAssignment(
      companyId: companyId,
      userId: user.id,
    );
    final level = accessLevel == UserRole.admin
        ? UserRole.admin
        : UserRole.employee;
    final resolvedAccess = (!overwriteAccessLevel &&
            existing != null &&
            existing.accessLevel.trim().isNotEmpty)
        ? existing.accessLevel
        : level.storageValue;
    await assignStaff(
      companyId: companyId,
      assignment: StaffAssignment(
        userId: user.id,
        username: user.username,
        email: user.email,
        roleId: existing?.roleId ?? '',
        jobRole: existing?.jobRole ?? '',
        tasks: existing?.tasks ?? const [],
        accessLevel: resolvedAccess,
        clockDeclineCount: existing?.clockDeclineCount ?? 0,
        timeCardProfile: existing?.timeCardProfile,
      ),
    );
  }

  Future<void> setStaffAccessLevel({
    required String companyId,
    required String userId,
    required UserRole accessLevel,
  }) async {
    final existing = await getAssignment(companyId: companyId, userId: userId);
    if (existing == null) return;
    final level = accessLevel == UserRole.admin
        ? UserRole.admin
        : UserRole.employee;
    await assignStaff(
      companyId: companyId,
      assignment: existing.copyWith(accessLevel: level.storageValue),
    );
  }

  Future<void> removeStaff({
    required String companyId,
    required String userId,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    await _rtdb.remove(_staffPath(docId, userId));
  }

  Future<void> removeUserFromAllCompanies({required String userId}) async {
    final children = await _rtdb.getChildren(RtdbPaths.companies);
    for (final companyId in children.keys) {
      try {
        final path = _staffPath(companyId, userId);
        final existing = await _rtdb.getMap(path);
        if (existing != null) {
          await _rtdb.remove(path);
        }
      } catch (_) {}
    }
  }

  Future<List<CompanyTaskListing>> listAllTasks() async {
    final children = await _rtdb.getChildren(RtdbPaths.companies);
    final listings = <CompanyTaskListing>[];
    for (final entry in children.entries) {
      try {
        final company =
            CompanyModel.fromFirestore(id: entry.key, data: entry.value);
        final tasks = [
          ..._tasksFromCompany(entry.value),
          ...await _folderTasks(entry.key),
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
    final children = await _rtdb.getChildren(RtdbPaths.companies);
    final listings = <CompanyRoleListing>[];
    for (final entry in children.entries) {
      try {
        final company =
            CompanyModel.fromFirestore(id: entry.key, data: entry.value);
        final roles = _rolesFromCompany(entry.value);
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
    final data = await _rtdb.getMap(_companyPath(docId));
    final roles = _rolesFromCompany(data);
    roles.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return roles;
  }

  Future<CompanyJobRole> addRole({
    required String companyId,
    required String name,
    String description = '',
  }) async {
    final role = CompanyJobRole(
      id: _rtdb.newKey(RtdbPaths.companies),
      name: name.trim(),
      description: description.trim(),
    );
    final docId = await _resolveCompanyDocId(companyId);
    await _rtdb.merge(_companyPath(docId), {
      'roles/${role.id}': role.toFirestore(),
    });
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
    await _rtdb.merge(_companyPath(docId), {
      'roles/${role.id}': payload,
    });

    if (updated.name != role.name) {
      final fanOutErrors = <Object>[];
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
        } catch (error) {
          fanOutErrors.add(error);
        }
      }

      try {
        final members = await listStaff(docId);
        for (final member in members) {
          if (member.roleId != role.id) continue;
          await assignStaff(
            companyId: docId,
            assignment: member.copyWith(jobRole: updated.name),
          );
        }
      } catch (error) {
        fanOutErrors.add(error);
      }

      if (fanOutErrors.isNotEmpty) {
        throw StateError(
          'Role saved, but ${fanOutErrors.length} linked staff/task '
          'update(s) failed.',
        );
      }
    }

    return updated;
  }

  Future<void> deleteRole({
    required String companyId,
    required String roleId,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    await _rtdb.remove('${_companyPath(docId)}/roles/$roleId');
  }

  Future<List<CompanyTask>> listTasks(String companyId) async {
    final docId = await _resolveCompanyDocId(companyId);
    final data = await _rtdb.getMap(_companyPath(docId));
    final tasks = [
      ..._tasksFromCompany(data),
      ...await _folderTasks(docId),
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
      id: _rtdb.newKey(RtdbPaths.companies),
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
    await _rtdb.merge(_companyPath(docId), {
      'tasks/${task.id}': payload,
    });
    await _rtdb.merge(_taskFolderPath(docId, task.id), payload);
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
    await _rtdb.merge(_companyPath(docId), {
      'tasks/${task.id}': payload,
    });
    await _rtdb.merge(_taskFolderPath(docId, task.id), payload);
    return updated;
  }

  Future<void> deleteTask({
    required String companyId,
    required String taskId,
  }) async {
    final docId = await _resolveCompanyDocId(companyId);
    await _rtdb.remove('${_companyPath(docId)}/tasks/$taskId');
    try {
      await _rtdb.remove(_taskFolderPath(docId, taskId));
    } catch (_) {}
  }

  Future<String> _resolveCompanyDocId(String companyId) async {
    final raw = companyId.trim();
    final id = CompanyId.normalize(raw);
    for (final key in {id, raw, companyId}) {
      if (key.isEmpty) continue;
      final data = await _rtdb.getMap(_companyPath(key));
      if (data != null) return key;
    }
    if (id.isNotEmpty) {
      final all = await listCompanies();
      for (final company in all) {
        if (company.id == id) {
          return company.firestoreId;
        }
      }
    }
    final children = await _rtdb.getChildren(RtdbPaths.companies);
    final needle = raw.toLowerCase();
    for (final entry in children.entries) {
      final data = entry.value;
      final name = data['name']?.toString().trim().toLowerCase() ?? '';
      final stored = CompanyId.normalize(data['companyId']?.toString() ?? '');
      if (name == needle || (id.isNotEmpty && stored == id)) {
        return entry.key;
      }
    }
    return id.isNotEmpty ? id : raw;
  }

  Future<List<CompanyTask>> _folderTasks(String companyId) async {
    try {
      final folder = await _rtdb.getChildren('${_companyPath(companyId)}/tasks');
      return folder.entries
          .map(
            (entry) =>
                CompanyTask.fromFirestore(id: entry.key, data: entry.value),
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

    for (final entry in mapOrListChildren(data['tasks']).entries) {
      add(entry.key, entry.value);
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

    for (final entry in mapOrListChildren(data['roles']).entries) {
      add(entry.key, entry.value);
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
