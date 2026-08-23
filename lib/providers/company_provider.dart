import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company_job_role.dart';
import '../models/company_model.dart';
import '../models/company_task.dart';
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
  CompanyModel? selectedCompany;
  bool isPickingCompany = false;
  StaffAssignment? myAssignment;
  final Map<String, Uint8List> logos = {};
  int logoRevision = 0;

  static const _selectedCompanyKey = 'selected_company_id';

  String _logoKey(String companyId) => 'company_$companyId';

  Uint8List? logoFor(String companyId) => logos[companyId];

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

  Future<void> loadStaff(String companyId) async {
    try {
      staff = await _companies.listStaff(companyId);
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
          : 'Could not save the company. Check Firestore rules and try again.';
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
  }) async {
    try {
      await _users.updateUserRole(userId: userId, role: role);
      await loadUsers();
      return true;
    } catch (_) {
      errorMessage = 'Could not update user role.';
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

  Future<void> ensureMember({
    required String companyId,
    required UserModel user,
  }) async {
    try {
      await _companies.ensureStaffMember(companyId: companyId, user: user);
    } catch (_) {}
  }

  Future<bool> addCompanyMember({
    required String companyId,
    required UserModel user,
  }) async {
    errorMessage = null;
    try {
      await _companies.ensureStaffMember(companyId: companyId, user: user);
      if (user.role == UserRole.user &&
          !RolePolicy.isSuperAdminEmail(user.email)) {
        await _users.updateUserRole(
          userId: user.id,
          role: UserRole.employee,
        );
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
      _persistSelection(company.id);
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
        errorMessage = 'Incorrect company code.';
        notifyListeners();
        return false;
      }
      selectedCompany = company;
      isPickingCompany = false;
      await _persistSelection(company.id);
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
    isPickingCompany = true;
    notifyListeners();
  }

  void endCompanyPick() {
    if (!isPickingCompany) return;
    isPickingCompany = false;
    notifyListeners();
  }

  Future<void> restoreSelection() async {
    if (selectedCompany != null) return;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_selectedCompanyKey);
    if (id == null || id.isEmpty) return;
    try {
      selectedCompany = await _companies.getCompanyById(id);
      isPickingCompany = false;
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
    _persistSelection(null);
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
