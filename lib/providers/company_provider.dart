import 'package:flutter/material.dart';

import '../models/company_model.dart';
import '../models/staff_assignment.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/company_repository.dart';
import '../services/user_repository.dart';

class CompanyProvider extends ChangeNotifier {
  CompanyProvider({
    CompanyRepository? companyRepository,
    UserRepository? userRepository,
  })  : _companies = companyRepository ?? CompanyRepository(),
        _users = userRepository ?? UserRepository();

  final CompanyRepository _companies;
  final UserRepository _users;

  bool isLoading = false;
  String? errorMessage;
  List<CompanyModel> companies = [];
  List<UserModel> users = [];
  List<StaffAssignment> staff = [];
  CompanyModel? selectedCompany;
  StaffAssignment? myAssignment;

  Future<void> loadCompanies() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      companies = await _companies.listCompanies();
    } catch (_) {
      errorMessage = 'Unable to load companies.';
    } finally {
      isLoading = false;
      notifyListeners();
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
    required String name,
    required String password,
    required String createdBy,
  }) async {
    isLoading = true;
    notifyListeners();
    try {
      await _companies.createCompany(
        name: name,
        password: password,
        createdBy: createdBy,
      );
      await loadCompanies();
      return true;
    } catch (_) {
      errorMessage = 'Could not create company.';
      isLoading = false;
      notifyListeners();
      return false;
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
      notifyListeners();
    }
    return ok;
  }

  void clearSelection() {
    selectedCompany = null;
    myAssignment = null;
    staff = [];
    notifyListeners();
  }
}
