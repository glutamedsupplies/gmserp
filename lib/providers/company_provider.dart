import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../models/company_job_role.dart';
import '../models/company_model.dart';
import '../models/company_task.dart';
import '../models/employee_time_card_profile.dart';
import '../models/staff_assignment.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/company_repository.dart';
import '../services/local_avatar_factory.dart';
import '../services/local_avatar_store.dart';
import '../services/user_repository.dart';

class CompanyProvider extends ChangeNotifier {
  CompanyProvider({
    CompanyRepository? companyRepository,
    UserRepository? userRepository,
    LocalAvatarStore? logoStore,
  })  : _companies = companyRepository ?? CompanyRepository(),
        _users = userRepository ?? UserRepository(),
        _logos = logoStore ?? createLocalAvatarStore();

  final CompanyRepository _companies;
  final UserRepository _users;
  final LocalAvatarStore _logos;

  bool isLoading = false;
  String? errorMessage;
  List<CompanyModel> companies = [];
  List<CompanyModel> memberCompanies = [];
  List<UserModel> users = [];
  List<StaffAssignment> staff = [];
  List<CompanyTask> tasks = [];
  List<CompanyJobRole> roles = [];
  List<CompanyTaskListing> allTasks = [];
  List<CompanyRoleListing> allRoles = [];
  List<StaffMembershipListing> allStaffMemberships = [];
  final Map<String, List<StaffAssignment>> _staffByCompanyDoc = {};
  CompanyModel? selectedCompany;
  bool isPickingCompany = false;
  /// True only after a successful company code entry that has not expired.
  bool companyCodeUnlocked = false;
  /// Snapshot used so canceling "Switch company" can restore a still-valid unlock.
  bool _unlockedBeforePick = false;
  StaffAssignment? myAssignment;
  final Map<String, Uint8List> logos = {};
  int logoRevision = 0;

  static const _selectedCompanyKey = 'selected_company_id';
  static const _unlockExpiresKey = 'company_unlock_expires_ms';

  /// True when an employee/admin may cancel company pick and return to the dashboard.
  bool get canCancelCompanyPick =>
      _unlockedBeforePick && selectedCompany != null;

  /// Employee/admin must have a non-expired company-code unlock to use company data.
  bool get hasActiveCompanySession =>
      selectedCompany != null && companyCodeUnlocked && !isPickingCompany;

  String _logoKey(String companyId) => 'company_$companyId';

  Uint8List? logoFor(String companyId) => logos[companyId];

  /// Employee/admin notifications stay off until company code unlock succeeds.
  bool notificationsAllowedFor(UserRole? role) {
    if (role == UserRole.superAdmin) return true;
    if (role == UserRole.employee || role == UserRole.admin) {
      return companyCodeUnlocked &&
          selectedCompany != null &&
          !isPickingCompany;
    }
    return false;
  }

  Future<void> loadCompaniesForMember(UserModel user) async {
    isLoading = true;
    errorMessage = null;
    memberCompanies = [];
    notifyListeners();
    try {
      memberCompanies = await _companies.listCompaniesForMember(
        userId: user.id,
        email: user.email,
      );
      await _loadLogosFor(memberCompanies);
      if (selectedCompany != null &&
          !memberCompanies.any((item) => item.id == selectedCompany!.id)) {
        selectedCompany = null;
        myAssignment = null;
        isPickingCompany = false;
        companyCodeUnlocked = false;
        await _persistSelection(null);
      }
    } catch (_) {
      errorMessage = 'Unable to load companies.';
      memberCompanies = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> isCompanyMember({
    required String companyId,
    required String userId,
    String? email,
  }) {
    return _companies.isCompanyMember(
      companyId: companyId,
      userId: userId,
      email: email,
    );
  }

  Future<void> loadCompanies({bool force = true}) async {
    if (!force && companies.isNotEmpty) {
      return;
    }
    isLoading = companies.isEmpty;
    errorMessage = null;
    if (isLoading) notifyListeners();
    try {
      companies = await _companies.listCompanies();
      await _loadLogos();
    } catch (_) {
      errorMessage = 'Unable to load companies.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadLogos() async {
    await _loadLogosFor(companies);
  }

  Future<void> _loadLogosFor(List<CompanyModel> items) async {
    final next = <String, Uint8List>{};
    for (final company in items) {
      try {
        final bytes = await _logos.read(_logoKey(company.id));
        if (bytes != null && bytes.isNotEmpty) {
          next[company.id] = bytes;
        }
      } catch (_) {}
    }
    logos
      ..clear()
      ..addAll(next);
    logoRevision++;
  }

  Future<bool> saveCompanyLogo(String companyId, List<int> bytes) async {
    try {
      await _logos.write(_logoKey(companyId), bytes);
      logos[companyId] = Uint8List.fromList(bytes);
      logoRevision++;
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not save the company photo.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeCompanyLogo(String companyId) async {
    try {
      await _logos.delete(_logoKey(companyId));
      logos.remove(companyId);
      logoRevision++;
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not remove the company photo.';
      notifyListeners();
      return false;
    }
  }

  Future<void> loadUsers() async {
    try {
      users = await _users.listUsers();
      notifyListeners();
    } catch (_) {
      errorMessage = 'Unable to load users.';
      notifyListeners();
    }
  }

  Future<void> loadUsersPage() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      users = await _users.listUsers();
    } catch (_) {
      users = [];
      errorMessage = 'Unable to load users.';
    }
    try {
      companies = await _companies.listCompanies();
      try {
        await _loadLogos();
      } catch (_) {}
    } catch (_) {
      companies = [];
    }
    try {
      allStaffMemberships = await _companies.listAllStaffMemberships();
      _staffByCompanyDoc.clear();
      for (final membership in allStaffMemberships) {
        _staffByCompanyDoc
            .putIfAbsent(membership.firestoreCompanyId, () => [])
            .add(membership.assignment);
      }
    } catch (_) {
      allStaffMemberships = [];
      _staffByCompanyDoc.clear();
    }
    isLoading = false;
    notifyListeners();
  }

  List<StaffAssignment> cachedStaffForCompany(String documentId) {
    return _staffByCompanyDoc[documentId] ?? const [];
  }

  Future<List<StaffAssignment>> loadStaffForCompany(CompanyModel company) async {
    final key = company.firestoreId;
    final cached = _staffByCompanyDoc[key];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final loaded = await _companies.listStaffByDocumentId(key);
    _staffByCompanyDoc[key] = loaded;
    notifyListeners();
    return loaded;
  }

  Future<void> loadStaff(String companyId) async {
    try {
      staff = await _companies.listStaff(companyId);
      _cacheStaff(companyId, staff);
      notifyListeners();
    } catch (_) {
      staff = [];
      notifyListeners();
    }
  }

  Future<void> loadAllTasks() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      allTasks = await _companies.listAllTasks();
      try {
        companies = await _companies.listCompanies();
        await _loadLogos();
      } catch (_) {}
    } catch (_) {
      errorMessage = 'Unable to load tasks.';
      allTasks = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAllRoles() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      allRoles = await _companies.listAllRoles();
      try {
        allTasks = await _companies.listAllTasks();
      } catch (_) {}
      try {
        companies = await _companies.listCompanies();
        await _loadLogos();
      } catch (_) {}
    } catch (_) {
      errorMessage = 'Unable to load roles.';
      allRoles = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<List<StaffAssignment>> fetchStaffForCompany(String companyId) async {
    final loaded = await _companies.listStaff(companyId);
    staff = loaded;
    _cacheStaff(companyId, loaded);
    notifyListeners();
    return loaded;
  }

  Future<void> loadCompanyUsers(String companyId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _users.listUsers(),
        _companies.listStaff(companyId),
        _companies.listTasks(companyId),
        _companies.listRoles(companyId),
      ]);
      users = results[0] as List<UserModel>;
      staff = results[1] as List<StaffAssignment>;
      tasks = results[2] as List<CompanyTask>;
      roles = results[3] as List<CompanyJobRole>;
      _cacheStaff(companyId, staff);
    } catch (_) {
      errorMessage = 'Unable to load company users.';
      staff = [];
      tasks = [];
      roles = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _cacheStaff(String companyKey, List<StaffAssignment> members) {
    for (final company in companies) {
      if (company.id == companyKey ||
          company.firestoreId == companyKey) {
        _staffByCompanyDoc[company.firestoreId] = members;
        return;
      }
    }
    _staffByCompanyDoc[companyKey] = members;
  }

  UserModel? userById(String userId) {
    for (final user in users) {
      if (user.id == userId) return user;
    }
    return null;
  }

  List<UserModel> usersNotInCompany() {
    final memberIds = staff.map((item) => item.userId).toSet();
    return users
        .where(
          (user) =>
              !memberIds.contains(user.id) &&
              !RolePolicy.isSuperAdminEmail(user.email),
        )
        .toList();
  }

  Future<void> loadMyAssignment({
    required String companyId,
    required String userId,
  }) async {
    myAssignment = await _companies.getAssignment(
      companyId: companyId,
      userId: userId,
    );
    notifyListeners();
  }

  Future<bool> createCompany({
    required String companyId,
    required String name,
    required String password,
    required String staffPassword,
    required String createdBy,
    List<int>? logoBytes,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _companies.createCompany(
        companyId: companyId,
        name: name,
        password: password,
        staffPassword: staffPassword,
        createdBy: createdBy,
      );
      if (logoBytes != null && logoBytes.isNotEmpty) {
        await _logos.write(_logoKey(companyId), logoBytes);
      }
      await loadCompanies();
      return true;
    } catch (error) {
      errorMessage = error is StateError
          ? error.message
          : 'Could not save the company. Check Realtime Database rules and try again.';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateCompany({
    required String id,
    required String name,
    String? newPassword,
    String? newStaffPassword,
  }) async {
    errorMessage = null;
    notifyListeners();
    try {
      await _companies.updateCompany(
        id: id,
        name: name,
        newPassword: newPassword,
        newStaffPassword: newStaffPassword,
      );
      await loadCompanies();
      return true;
    } catch (_) {
      errorMessage = 'Could not update the company.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCompany({
    required CompanyModel company,
    required String password,
  }) async {
    errorMessage = null;
    notifyListeners();
    try {
      await _companies.deleteCompany(
        company: company,
        password: password,
      );
      await _logos.delete(_logoKey(company.id));
      logos.remove(company.id);
      if (selectedCompany?.id == company.id) {
        selectedCompany = null;
        myAssignment = null;
        staff = [];
        tasks = [];
        roles = [];
      }
      await loadCompanies();
      return true;
    } catch (error) {
      errorMessage = error is StateError
          ? error.message
          : 'Could not delete the company.';
      notifyListeners();
      return false;
    }
  }

  Future<CompanyModel?> findCompany(String companyId) async {
    try {
      return await _companies.getCompanyById(companyId);
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateUserRole({
    required String userId,
    required UserRole role,
    UserRole? previousRole,
  }) async {
    errorMessage = null;
    try {
      UserRole previous = previousRole ?? UserRole.user;
      for (final user in users) {
        if (user.id == userId) {
          previous = user.role;
          break;
        }
      }

      await _users.updateUserRole(userId: userId, role: role);

      if (RolePolicy.clearsCompanyMembership(previous: previous, next: role)) {
        await _companies.removeUserFromAllCompanies(userId: userId);
        staff.removeWhere((member) => member.userId == userId);
        allStaffMemberships.removeWhere(
          (item) => item.assignment.userId == userId,
        );
        for (final entry in _staffByCompanyDoc.entries.toList()) {
          entry.value.removeWhere((member) => member.userId == userId);
          if (entry.value.isEmpty) {
            _staffByCompanyDoc.remove(entry.key);
          }
        }
      }

      await loadUsers();
      await _refreshStaffMemberships();
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not update user level.';
      notifyListeners();
      return false;
    }
  }

  Future<void> _refreshStaffMemberships() async {
    try {
      allStaffMemberships = await _companies.listAllStaffMemberships();
      _staffByCompanyDoc.clear();
      for (final membership in allStaffMemberships) {
        _staffByCompanyDoc
            .putIfAbsent(membership.firestoreCompanyId, () => [])
            .add(membership.assignment);
      }
    } catch (_) {
      allStaffMemberships = [];
      _staffByCompanyDoc.clear();
    }
  }

  Future<bool> syncUserCompanyMemberships({
    required UserModel user,
    required List<String> companyIds,
  }) async {
    final targetIds = {
      for (final id in companyIds)
        if (id.trim().isNotEmpty) id.trim(),
    };
    if (targetIds.isEmpty) {
      errorMessage = 'Select at least one company.';
      notifyListeners();
      return false;
    }

    errorMessage = null;
    final currentIds = <String>{};
    for (final item in allStaffMemberships) {
      if (item.assignment.userId == user.id) {
        currentIds.add(item.company.id);
      }
    }

    try {
      for (final companyId in targetIds) {
        if (!currentIds.contains(companyId)) {
          final level = user.role == UserRole.admin
              ? UserRole.admin
              : UserRole.employee;
          await _companies.ensureStaffMember(
            companyId: companyId,
            user: user,
            accessLevel: level,
            overwriteAccessLevel: true,
          );
        }
      }
      for (final companyId in currentIds) {
        if (!targetIds.contains(companyId)) {
          await _companies.removeStaff(companyId: companyId, userId: user.id);
        }
      }
      await _refreshStaffMemberships();
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not update company membership.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> assignStaff({
    required String companyId,
    required StaffAssignment assignment,
  }) async {
    try {
      await _companies.assignStaff(
        companyId: companyId,
        assignment: assignment,
      );
      await loadStaff(companyId);
      return true;
    } catch (_) {
      errorMessage = 'Could not save assignment.';
      notifyListeners();
      return false;
    }
  }

  Future<int> clockDeclineCountFor({
    required String companyId,
    required String userId,
  }) {
    return _companies.getClockDeclineCount(
      companyId: companyId,
      userId: userId,
    );
  }

  Future<Map<String, int>> clockDeclineCountsFor({
    required Iterable<({String companyId, String userId})> members,
  }) {
    return _companies.getClockDeclineCounts(members: members);
  }

  Future<bool> unlockEmployeeClockRequests({
    required String companyId,
    required String userId,
  }) async {
    errorMessage = null;
    try {
      await _companies.resetClockDeclineCount(
        companyId: companyId,
        userId: userId,
      );
      await loadStaff(companyId);
      return true;
    } catch (_) {
      errorMessage = 'Could not unlock clock requests for this employee.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> saveStaffTimeCardProfile({
    required String companyId,
    required String userId,
    required EmployeeTimeCardProfile profile,
    CompanyModel? company,
    StaffAssignment? member,
    UserModel? actor,
  }) async {
    errorMessage = null;
    try {
      CompanyModel? resolvedCompany = company;
      if (resolvedCompany == null) {
        for (final item in companies) {
          if (item.id == companyId || item.firestoreId == companyId) {
            resolvedCompany = item;
            break;
          }
        }
      }
      resolvedCompany ??= selectedCompany;

      if (users.isEmpty) {
        await loadUsers();
      }

      final employee = userById(userId);
      final employeeName = member?.username.isNotEmpty == true
          ? member!.username
          : (employee?.username ?? member?.email ?? 'Employee');
      final employeeEmail =
          member?.email.isNotEmpty == true ? member!.email : (employee?.email ?? '');

      final recipientIds = <String>{userId};
      if (actor != null) recipientIds.add(actor.id);
      final companyStaff = await _companies.listStaff(companyId);
      for (final staffMember in companyStaff) {
        if (memberAccessRole(staffMember) == UserRole.admin) {
          recipientIds.add(staffMember.userId);
        }
      }
      for (final user in users) {
        if (user.role == UserRole.superAdmin) {
          recipientIds.add(user.id);
        }
      }

      await _companies.saveStaffTimeCardProfile(
        companyId: companyId,
        userId: userId,
        profile: profile,
        companyDocumentId: resolvedCompany?.firestoreId,
        companyName: resolvedCompany?.name ?? '',
        employeeName: employeeName,
        employeeEmail: employeeEmail,
        actorId: actor?.id,
        actorName: actor != null
            ? (actor.username.isNotEmpty ? actor.username : actor.email)
            : '',
        recipientIds: recipientIds.toList(),
      );

      // Editing time card settings unlocks clock requests after 3 declines.
      await _companies.resetClockDeclineCount(
        companyId: companyId,
        userId: userId,
      );

      await loadStaff(companyId);
      return true;
    } catch (e) {
      errorMessage = 'Could not save employee time card settings.';
      notifyListeners();
      return false;
    }
  }

  Future<void> ensureMember({
    required String companyId,
    required UserModel user,
  }) async {
    try {
      await _companies.ensureStaffMember(companyId: companyId, user: user);
    } catch (_) {}
  }

  /// Access level inside [selectedCompany] for [user], if any.
  UserRole? companyAccessFor(UserModel user) {
    if (user.role == UserRole.superAdmin || user.role == UserRole.user) {
      return user.role;
    }
    final company = selectedCompany;
    if (company == null) return null;

    StaffAssignment? assignment;
    if (myAssignment?.userId == user.id) {
      assignment = myAssignment;
    } else {
      for (final member in staff) {
        if (member.userId == user.id) {
          assignment = member;
          break;
        }
      }
    }
    if (assignment == null) {
      for (final item in allStaffMemberships) {
        if (item.assignment.userId == user.id &&
            (item.company.id == company.id ||
                item.firestoreCompanyId == company.firestoreId)) {
          assignment = item.assignment;
          break;
        }
      }
    }
    return assignment?.accessRole(fallback: user.role);
  }

  /// Role used for navigation / features in the currently selected company.
  UserRole effectiveRoleFor(UserModel? user) {
    if (user == null) return UserRole.user;
    if (user.role == UserRole.superAdmin || user.role == UserRole.user) {
      return user.role;
    }
    return companyAccessFor(user) ?? user.role;
  }

  UserRole memberAccessRole(StaffAssignment member) {
    final global = userById(member.userId)?.role;
    return member.accessRole(fallback: global);
  }

  Future<bool> addCompanyMember({
    required String companyId,
    required UserModel user,
    UserRole accessLevel = UserRole.employee,
  }) async {
    errorMessage = null;
    final level = accessLevel == UserRole.admin
        ? UserRole.admin
        : UserRole.employee;
    try {
      await _companies.ensureStaffMember(
        companyId: companyId,
        user: user,
        accessLevel: level,
        overwriteAccessLevel: true,
      );

      // Promote global account only when needed — never demote Admin → Employee
      // just because they were added as employee to another company.
      if (!RolePolicy.isSuperAdminEmail(user.email)) {
        if (user.role == UserRole.user) {
          await _users.updateUserRole(userId: user.id, role: level);
        } else if (user.role == UserRole.employee && level == UserRole.admin) {
          await _users.updateUserRole(userId: user.id, role: UserRole.admin);
        }
      }

      await loadStaff(companyId);
      await loadUsers();
      return true;
    } catch (_) {
      errorMessage = 'Could not add the user to this company.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> setCompanyMemberAccess({
    required String companyId,
    required String userId,
    required UserRole accessLevel,
  }) async {
    errorMessage = null;
    final level = accessLevel == UserRole.admin
        ? UserRole.admin
        : UserRole.employee;
    try {
      await _companies.setStaffAccessLevel(
        companyId: companyId,
        userId: userId,
        accessLevel: level,
      );
      if (level == UserRole.admin) {
        final user = userById(userId);
        if (user != null &&
            user.role == UserRole.employee &&
            !RolePolicy.isSuperAdminEmail(user.email)) {
          await _users.updateUserRole(userId: userId, role: UserRole.admin);
          await loadUsers();
        }
      }
      await loadStaff(companyId);
      return true;
    } catch (_) {
      errorMessage = 'Could not update company access level.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeCompanyMember({
    required String companyId,
    required String userId,
  }) async {
    errorMessage = null;
    try {
      await _companies.removeStaff(companyId: companyId, userId: userId);
      await loadStaff(companyId);
      return true;
    } catch (_) {
      errorMessage = 'Could not remove the user from this company.';
      notifyListeners();
      return false;
    }
  }

  bool unlockCompany({
    required CompanyModel company,
    required String password,
  }) {
    final ok = _companies.unlockCompany(
      company: company,
      password: password,
    );
    if (ok) {
      selectedCompany = company;
      isPickingCompany = false;
      _unlockedBeforePick = false;
      companyCodeUnlocked = true;
      _persistSelection(company.id);
      _persistUnlockExpiry();
      notifyListeners();
    }
    return ok;
  }

  Future<bool> unlockCompanyById({
    required String companyId,
    required String password,
    CompanyModel? fallback,
  }) async {
    errorMessage = null;
    try {
      CompanyModel company;
      try {
        company = await _companies.getCompanyById(companyId);
      } catch (_) {
        if (fallback == null) rethrow;
        company = fallback;
      }

      final ok = _companies.unlockCompany(
        company: company,
        password: password,
      );
      if (!ok) {
        errorMessage = company.staffPasswordHash.isEmpty
            ? 'This company has no company code yet. Ask the founder to set one.'
            : 'Incorrect company code.';
        notifyListeners();
        return false;
      }
      selectedCompany = company;
      isPickingCompany = false;
      _unlockedBeforePick = false;
      companyCodeUnlocked = true;
      await _persistSelection(company.id);
      await _persistUnlockExpiry();
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not open that company. Check the ID and try again.';
      notifyListeners();
      return false;
    }
  }

  void beginCompanyPick() {
    if (isPickingCompany) return;
    _unlockedBeforePick = companyCodeUnlocked && selectedCompany != null;
    isPickingCompany = true;
    companyCodeUnlocked = false;
    notifyListeners();
  }

  void endCompanyPick() {
    if (!isPickingCompany) return;
    isPickingCompany = false;
    // Only restore unlock if the previous company session was still valid.
    companyCodeUnlocked =
        _unlockedBeforePick && selectedCompany != null;
    _unlockedBeforePick = false;
    notifyListeners();
  }

  /// Locks company access so employee/admin must re-enter the company code.
  /// Keeps [selectedCompany] as a hint for which company to open again.
  Future<void> lockCompanySession({bool clearCompanyHint = false}) async {
    companyCodeUnlocked = false;
    isPickingCompany = false;
    _unlockedBeforePick = false;
    myAssignment = null;
    staff = [];
    tasks = [];
    roles = [];
    if (clearCompanyHint) {
      selectedCompany = null;
      await _persistSelection(null);
    }
    await _clearUnlockExpiry();
    notifyListeners();
  }

  /// Returns `false` and locks the session when the company-code unlock TTL elapsed.
  Future<bool> ensureCompanySessionValid() async {
    if (!companyCodeUnlocked || selectedCompany == null) {
      return companyCodeUnlocked;
    }
    final prefs = await SharedPreferences.getInstance();
    final expiresMs = prefs.getInt(_unlockExpiresKey);
    if (expiresMs == null) {
      // Unlock existed in memory without persisted expiry (legacy) — keep for now
      // but stamp a fresh expiry so future checks work.
      await _persistUnlockExpiry();
      return true;
    }
    if (DateTime.now().millisecondsSinceEpoch >= expiresMs) {
      await lockCompanySession();
      return false;
    }
    return true;
  }

  Future<void> restoreSelection() async {
    if (selectedCompany != null) return;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_selectedCompanyKey);
    if (id == null || id.isEmpty) return;
    try {
      selectedCompany = await _companies.getCompanyById(id);
      isPickingCompany = false;
      final expiresMs = prefs.getInt(_unlockExpiresKey);
      final stillValid = expiresMs != null &&
          DateTime.now().millisecondsSinceEpoch < expiresMs;
      companyCodeUnlocked = stillValid;
      if (!stillValid) {
        await prefs.remove(_unlockExpiresKey);
        myAssignment = null;
        staff = [];
        tasks = [];
        roles = [];
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistSelection(String? companyId) async {
    final prefs = await SharedPreferences.getInstance();
    if (companyId == null || companyId.isEmpty) {
      await prefs.remove(_selectedCompanyKey);
    } else {
      await prefs.setString(_selectedCompanyKey, companyId);
    }
  }

  Future<void> _persistUnlockExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    final expires = DateTime.now().add(AppConstants.companyCodeSessionTtl);
    await prefs.setInt(_unlockExpiresKey, expires.millisecondsSinceEpoch);
  }

  Future<void> _clearUnlockExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_unlockExpiresKey);
  }

  void clearSelection() {
    selectedCompany = null;
    myAssignment = null;
    staff = [];
    tasks = [];
    roles = [];
    allTasks = [];
    allRoles = [];
    companies = [];
    memberCompanies = [];
    isPickingCompany = false;
    companyCodeUnlocked = false;
    _unlockedBeforePick = false;
    _persistSelection(null);
    _clearUnlockExpiry();
    notifyListeners();
  }

  CompanyJobRole? roleById(String roleId) {
    for (final role in roles) {
      if (role.id == roleId) return role;
    }
    return null;
  }

  List<CompanyTask> tasksForRole(String roleId) {
    if (roleId.isEmpty) return [];
    return tasks.where((task) => task.roleId == roleId).toList();
  }

  Future<void> loadCompanyRoles(String companyId) async {
    try {
      roles = await _companies.listRoles(companyId);
      notifyListeners();
    } catch (_) {
      roles = [];
      notifyListeners();
    }
  }

  Future<bool> addCompanyRole({
    required String companyId,
    required String name,
    String description = '',
  }) async {
    errorMessage = null;
    try {
      await _companies.addRole(
        companyId: companyId,
        name: name,
        description: description,
      );
      roles = await _companies.listRoles(companyId);
      try {
        allRoles = await _companies.listAllRoles();
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not add the role.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateCompanyRole({
    required String companyId,
    required CompanyJobRole role,
    required String name,
    String description = '',
  }) async {
    errorMessage = null;
    try {
      final updated = await _companies.updateRole(
        companyId: companyId,
        role: role,
        name: name,
        description: description,
      );
      roles = [
        for (final item in roles)
          if (item.id == updated.id) updated else item,
      ];
      allRoles = [
        for (final item in allRoles)
          if (item.role.id == updated.id && item.company.id == companyId)
            CompanyRoleListing(company: item.company, role: updated)
          else
            item,
      ];
      try {
        allRoles = await _companies.listAllRoles();
        allTasks = await _companies.listAllTasks();
      } catch (_) {}
      try {
        roles = await _companies.listRoles(companyId);
        tasks = await _companies.listTasks(companyId);
        staff = await _companies.listStaff(companyId);
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not update the role.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCompanyRole({
    required String companyId,
    required String roleId,
  }) async {
    errorMessage = null;
    final usedByLocalTasks = tasks.any((task) => task.roleId == roleId);
    final usedByAllTasks = allTasks.any(
      (item) => item.company.id == companyId && item.task.roleId == roleId,
    );
    if (usedByLocalTasks || usedByAllTasks) {
      errorMessage = 'Reassign or delete tasks that use this role first.';
      notifyListeners();
      return false;
    }
    if (staff.any((member) => member.roleId == roleId)) {
      errorMessage = 'Reassign employees who still have this role first.';
      notifyListeners();
      return false;
    }
    try {
      await _companies.deleteRole(companyId: companyId, roleId: roleId);
      roles = await _companies.listRoles(companyId);
      try {
        allRoles = await _companies.listAllRoles();
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not delete the role.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> addCompanyTask({
    required String companyId,
    required String title,
    String description = '',
    String roleId = '',
    String roleName = '',
  }) async {
    errorMessage = null;
    try {
      await _companies.addTask(
        companyId: companyId,
        title: title,
        description: description,
        roleId: roleId,
        roleName: roleName,
      );
      tasks = await _companies.listTasks(companyId);
      try {
        allTasks = await _companies.listAllTasks();
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not add the task.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateCompanyTask({
    required String companyId,
    required CompanyTask task,
    required String title,
    String description = '',
    String? roleId,
    String? roleName,
  }) async {
    errorMessage = null;
    try {
      final updated = await _companies.updateTask(
        companyId: companyId,
        task: task,
        title: title,
        description: description,
        roleId: roleId,
        roleName: roleName,
      );
      tasks = [
        for (final item in tasks)
          if (item.id == updated.id) updated else item,
      ];
      allTasks = [
        for (final item in allTasks)
          if (item.task.id == updated.id && item.company.id == companyId)
            CompanyTaskListing(company: item.company, task: updated)
          else
            item,
      ];
      try {
        allTasks = await _companies.listAllTasks();
      } catch (_) {}
      try {
        tasks = await _companies.listTasks(companyId);
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not update the task.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCompanyTask({
    required String companyId,
    required String taskId,
  }) async {
    errorMessage = null;
    try {
      await _companies.deleteTask(companyId: companyId, taskId: taskId);
      tasks = await _companies.listTasks(companyId);
      try {
        allTasks = await _companies.listAllTasks();
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = 'Could not delete the task.';
      notifyListeners();
      return false;
    }
  }
}
