import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/models/membership_request_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';

/// Service pour appeler les Cloud Functions
/// Gère toutes les opérations d'authentification et de gestion utilisateurs
class CloudFunctionsService {
  static final CloudFunctionsService _instance = CloudFunctionsService._internal();
  factory CloudFunctionsService() => _instance;
  CloudFunctionsService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  // ============================================
  // CRÉATION DE COMPTE
  // ============================================

  /// Crée un nouveau compte utilisateur
  /// Retourne l'authUid et les stations rejointes automatiquement (si matricule réservé)
  Future<CreateAccountResult> createAccount({
    required String email,
    required String password,
    required String matricule,
    required String firstName,
    required String lastName,
    required String sdisId,
  }) async {
    try {
      debugPrint('📤 Calling createAccount for: $email');

      final callable = _functions.httpsCallable('createAccount');
      final result = await callable.call<Map<String, dynamic>>({
        'email': email,
        'password': password,
        'matricule': matricule,
        'firstName': firstName,
        'lastName': lastName,
        'sdisId': sdisId,
      });

      final data = result.data;
      debugPrint('✅ Account created: ${data['authUid']}');

      return CreateAccountResult(
        success: data['success'] == true,
        authUid: data['authUid'] as String?,
        stationsJoined: data['stationsJoined'] != null
            ? List<String>.from(data['stationsJoined'])
            : [],
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ createAccount error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    } catch (e) {
      debugPrint('❌ createAccount error: $e');
      rethrow;
    }
  }

  // ============================================
  // DEMANDES D'ADHÉSION
  // ============================================

  /// Demande à rejoindre une caserne
  Future<void> requestMembership({required String stationId}) async {
    try {
      debugPrint('📤 Requesting membership for station: $stationId');

      final callable = _functions.httpsCallable('requestMembership');
      await callable.call<Map<String, dynamic>>({
        'stationId': stationId,
      });

      debugPrint('✅ Membership request sent');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ requestMembership error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  /// Crée une nouvelle station avec un code d'authentification
  /// Retourne le stationId et le nom de la station créée
  Future<CreateStationResult> createStationWithCode({
    required String code,
  }) async {
    try {
      debugPrint('📤 Creating station with code: $code');

      final callable = _functions.httpsCallable('createStationWithCode');
      final result = await callable.call<Map<String, dynamic>>({
        'code': code,
      });

      final data = result.data;
      debugPrint('✅ Station created: ${data['stationName']}');

      return CreateStationResult(
        success: data['success'] == true,
        stationId: data['stationId'] as String?,
        stationName: data['stationName'] as String?,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ createStationWithCode error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  /// Accepte ou refuse une demande d'adhésion
  Future<HandleMembershipResult> handleMembershipRequest({
    required String stationId,
    required String requestAuthUid,
    required bool accept,
    String? role,
    String? team,
  }) async {
    try {
      debugPrint('📤 Handling membership request: $requestAuthUid (accept: $accept)');

      final callable = _functions.httpsCallable('handleMembershipRequest');
      final result = await callable.call<Map<String, dynamic>>({
        'stationId': stationId,
        'requestAuthUid': requestAuthUid,
        'action': accept ? 'accept' : 'reject',
        if (role != null) 'role': role,
        if (team != null) 'team': team,
      });

      final data = result.data;
      debugPrint('✅ Membership request handled: ${data['action']}');

      return HandleMembershipResult(
        success: data['success'] == true,
        action: data['action'] as String?,
        matricule: data['matricule'] as String?,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ handleMembershipRequest error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  /// Récupère les demandes d'adhésion d'une station
  Future<List<MembershipRequest>> getMembershipRequests({
    required String stationId,
    String? status,
  }) async {
    try {
      debugPrint('📤 Getting membership requests for station: $stationId');

      final callable = _functions.httpsCallable('getMembershipRequests');
      final result = await callable.call<Map<String, dynamic>>({
        'stationId': stationId,
        if (status != null) 'status': status,
      });

      final data = result.data;
      final requests = (data['requests'] as List<dynamic>?)
          ?.map((r) => MembershipRequest.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList() ?? [];

      debugPrint('✅ Got ${requests.length} membership requests');
      return requests;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ getMembershipRequests error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  /// Récupère le nombre de demandes en attente (pour la pastille)
  Future<int> getPendingMembershipRequestsCount({
    required String stationId,
  }) async {
    try {
      final callable = _functions.httpsCallable('getPendingMembershipRequestsCount');
      final result = await callable.call<Map<String, dynamic>>({
        'stationId': stationId,
      });

      return result.data['count'] as int? ?? 0;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ getPendingMembershipRequestsCount error: ${e.code}');
      return 0;
    }
  }

  /// Récupère les demandes d'adhésion de l'utilisateur courant
  Future<List<MyMembershipRequest>> getMyMembershipRequests() async {
    try {
      debugPrint('📤 Getting my membership requests');

      final callable = _functions.httpsCallable('getMyMembershipRequests');
      final result = await callable.call<Map<String, dynamic>>({});

      final data = result.data;
      final requests = (data['requests'] as List<dynamic>?)
          ?.map((r) => MyMembershipRequest.fromJson(r as Map<String, dynamic>))
          .toList() ?? [];

      debugPrint('✅ Got ${requests.length} of my membership requests');
      return requests;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ getMyMembershipRequests error: ${e.code}');
      throw _handleFunctionsException(e);
    }
  }

  // ============================================
  // GESTION DES AGENTS (ADMIN)
  // ============================================

  /// Réserve un matricule pour pré-affiliation
  Future<void> reserveMatricule({
    required String stationId,
    required String matricule,
  }) async {
    try {
      debugPrint('📤 Reserving matricule: $matricule for station: $stationId');

      final callable = _functions.httpsCallable('reserveMatricule');
      await callable.call<Map<String, dynamic>>({
        'stationId': stationId,
        'matricule': matricule,
      });

      debugPrint('✅ Matricule reserved');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ reserveMatricule error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  /// Pré-enregistre un agent dans une station (profil minimal sans PII)
  /// L'agent pourra créer son compte plus tard et sera automatiquement affilié
  Future<void> preRegisterAgent({
    required String stationId,
    required String matricule,
  }) async {
    try {
      debugPrint(
          '📤 Pre-registering agent $matricule for station: $stationId');

      final callable = _functions.httpsCallable('preRegisterAgent');
      await callable.call<Map<String, dynamic>>({
        'stationId': stationId,
        'matricule': matricule,
      });

      debugPrint('✅ Agent pre-registered');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ preRegisterAgent error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  /// Ajoute un utilisateur existant à une station
  Future<AddUserResult> addExistingUserToStation({
    required String stationId,
    required String matricule,
    String? role,
    String? team,
  }) async {
    try {
      debugPrint('📤 Adding existing user $matricule to station: $stationId');

      final callable = _functions.httpsCallable('addExistingUserToStation');
      final result = await callable.call<Map<String, dynamic>>({
        'stationId': stationId,
        'matricule': matricule,
        if (role != null) 'role': role,
        if (team != null) 'team': team,
      });

      final data = result.data;
      debugPrint('✅ User added to station');

      return AddUserResult(
        success: data['success'] == true,
        authUid: data['authUid'] as String?,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ addExistingUserToStation error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  /// Met à jour le rôle d'un utilisateur dans une station
  Future<void> updateUserRole({
    required String stationId,
    required String userMatricule,
    required String newRole,
  }) async {
    try {
      debugPrint('📤 Updating role for $userMatricule to $newRole');

      final callable = _functions.httpsCallable('updateUserRole');
      await callable.call<Map<String, dynamic>>({
        'stationId': stationId,
        'userMatricule': userMatricule,
        'newRole': newRole,
      });

      debugPrint('✅ User role updated');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ updateUserRole error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  /// Retire un utilisateur d'une station
  Future<void> removeUserFromStation({
    required String stationId,
    required String userMatricule,
  }) async {
    try {
      debugPrint('📤 Removing $userMatricule from station: $stationId');

      final callable = _functions.httpsCallable('removeUserFromStation');
      await callable.call<Map<String, dynamic>>({
        'stationId': stationId,
        'userMatricule': userMatricule,
      });

      debugPrint('✅ User removed from station');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ removeUserFromStation error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  /// Supprime complètement un utilisateur
  Future<void> deleteUser({required String authUid}) async {
    try {
      debugPrint('📤 Deleting user: $authUid');

      final callable = _functions.httpsCallable('deleteUser');
      await callable.call<Map<String, dynamic>>({
        'authUid': authUid,
      });

      debugPrint('✅ User deleted');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ deleteUser error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  // ============================================
  // LECTURE DES DONNÉES (AVEC DÉCHIFFREMENT)
  // ============================================

  /// Récupère le profil utilisateur (déchiffré)
  Future<User?> getUserProfile({String? authUid}) async {
    try {
      debugPrint('📤 Getting user profile: ${authUid ?? 'current'}');

      final callable = _functions.httpsCallable('getUserProfile');
      final result = await callable.call<Map<String, dynamic>>({
        if (authUid != null) 'authUid': authUid,
      });

      final data = result.data;
      debugPrint('✅ Got user profile');

      return User.fromJson(data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ getUserProfile error: ${e.code} - ${e.message}');
      if (e.code == 'not-found') return null;
      throw _handleFunctionsException(e);
    }
  }

  /// Récupère la liste des utilisateurs d'une station (déchiffrés)
  Future<List<User>> getStationUsers({required String stationId}) async {
    try {
      debugPrint('📤 Getting users for station: $stationId');

      final callable = _functions.httpsCallable('getStationUsers');
      final result = await callable.call<Map<String, dynamic>>({
        'stationId': stationId,
      });

      final data = result.data;
      final users = (data['users'] as List<dynamic>?)
          ?.map((u) => User.fromJson(u as Map<String, dynamic>))
          .toList() ?? [];

      debugPrint('✅ Got ${users.length} station users');
      return users;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ getStationUsers error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  /// Récupère l'email associé à un matricule (pour connexion par matricule)
  Future<String?> getEmailByMatricule({
    required String matricule,
    required String sdisId,
  }) async {
    try {
      debugPrint('📤 Getting email for matricule: $matricule in SDIS: $sdisId');

      final callable = _functions.httpsCallable('getEmailByMatricule');
      final result = await callable.call<Map<String, dynamic>>({
        'matricule': matricule,
        'sdisId': sdisId,
      });

      final email = result.data['email'] as String?;
      debugPrint('✅ Email found: $email');
      return email;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ getEmailByMatricule error: ${e.code} - ${e.message}');
      return null;
    }
  }

  /// Récupère un utilisateur par authUid dans une station (avec déchiffrement)
  Future<User?> getUserByAuthUidForStation({
    required String authUid,
    required String stationId,
  }) async {
    try {
      debugPrint('📤 Getting user by authUid: $authUid in station: $stationId');

      final callable = _functions.httpsCallable('getUserByAuthUidForStation');
      final result = await callable.call({
        'authUid': authUid,
        'stationId': stationId,
      });

      final data = result.data as Map<Object?, Object?>?;
      if (data == null) return null;

      final userData = data['user'];
      if (userData == null) return null;

      final userMap = Map<String, dynamic>.from(userData as Map);

      // Convertir les données en objet User
      final user = User(
        id: userMap['id'] as String? ?? userMap['matricule'] as String? ?? '',
        authUid: userMap['authUid'] as String?,
        email: userMap['email'] as String?,
        firstName: userMap['firstName'] as String? ?? '',
        lastName: userMap['lastName'] as String? ?? '',
        station: userMap['station'] as String? ?? stationId,
        status: userMap['status'] as String? ?? 'agent',
        admin: userMap['admin'] as bool? ?? false,
        team: userMap['team'] as String? ?? '',
        skills: (userMap['skills'] as List<dynamic>?)?.cast<String>() ?? [],
        keySkills: (userMap['keySkills'] as List<dynamic>?)?.cast<String>() ?? [],
        personalAlertEnabled: userMap['personalAlertEnabled'] as bool? ?? false,
        personalAlertHour: userMap['personalAlertHour'] as int? ?? 18,
        positionId: userMap['positionId'] as String?,
      );

      debugPrint('✅ User loaded: ${user.firstName} ${user.lastName}');
      return user;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ getUserByAuthUidForStation error: ${e.code} - ${e.message}');
      return null;
    }
  }

  /// Récupère tous les utilisateurs d'une station (avec déchiffrement)
  Future<List<User>> getUsersByStation({
    required String stationId,
  }) async {
    try {
      debugPrint('📤 Getting all users for station: $stationId');

      final callable = _functions.httpsCallable('getUsersByStation');
      final result = await callable.call({
        'stationId': stationId,
      });

      final data = result.data as Map<Object?, Object?>?;
      if (data == null) return [];

      final usersData = data['users'];
      if (usersData == null) return [];

      final usersList = usersData as List<dynamic>;

      final users = usersList.map((userData) {
        final userMap = Map<String, dynamic>.from(userData as Map);

        return User(
          id: userMap['id'] as String? ?? userMap['matricule'] as String? ?? '',
          authUid: userMap['authUid'] as String?,
          email: userMap['email'] as String?,
          firstName: userMap['firstName'] as String? ?? '',
          lastName: userMap['lastName'] as String? ?? '',
          station: userMap['station'] as String? ?? stationId,
          status: userMap['status'] as String? ?? 'agent',
          admin: userMap['admin'] as bool? ?? false,
          team: userMap['team'] as String? ?? '',
          skills: (userMap['skills'] as List<dynamic>?)?.cast<String>() ?? [],
          keySkills: (userMap['keySkills'] as List<dynamic>?)?.cast<String>() ?? [],
          personalAlertEnabled: userMap['personalAlertEnabled'] as bool? ?? false,
          personalAlertHour: userMap['personalAlertHour'] as int? ?? 18,
          positionId: userMap['positionId'] as String?,
          agentAvailabilityStatus: userMap['agentAvailabilityStatus'] as String? ?? AgentAvailabilityStatus.active,
          suspensionStartDate: userMap['suspensionStartDate'] != null
              ? DateTime.tryParse(userMap['suspensionStartDate'] as String)
              : null,
        );
      }).toList();

      debugPrint('✅ Loaded ${users.length} users from station $stationId');
      return users;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ getUsersByStation error: ${e.code} - ${e.message}');
      return [];
    }
  }

  /// Récupère la liste des casernes du SDIS
  Future<List<StationInfo>> getSDISStations() async {
    try {
      debugPrint('📤 Getting SDIS stations');

      final callable = _functions.httpsCallable('getSDISStations');
      final result = await callable.call<Map<String, dynamic>>({});

      final data = result.data;
      final stations = (data['stations'] as List<dynamic>?)
          ?.map((s) => StationInfo.fromJson(s as Map<String, dynamic>))
          .toList() ?? [];

      debugPrint('✅ Got ${stations.length} stations');
      return stations;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ getSDISStations error: ${e.code} - ${e.message}');
      throw _handleFunctionsException(e);
    }
  }

  // ============================================
  // LECTURE DIRECTE FIRESTORE (profil global)
  // ============================================

  /// Récupère les listes acceptedStations et pendingStations du profil global
  /// Lecture directe depuis Firestore (autorisée par les rules pour son propre doc)
  /// Fallback: si acceptedStations est vide, dérive depuis les custom claims
  Future<({List<String> accepted, List<String> pending})> getUserStationLists() async {
    final uid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    final sdisId = SDISContext().currentSDISId;

    if (uid == null || sdisId == null) {
      debugPrint('❌ getUserStationLists: uid or sdisId is null');
      return (accepted: <String>[], pending: <String>[]);
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('sdis')
          .doc(sdisId)
          .collection('users')
          .doc(uid)
          .get();

      final data = doc.data() ?? {};
      final accepted = List<String>.from(data['acceptedStations'] ?? []);
      final pending = List<String>.from(data['pendingStations'] ?? []);

      // Fallback: si acceptedStations est vide, dériver depuis les custom claims
      if (accepted.isEmpty) {
        final idTokenResult = await firebase_auth.FirebaseAuth.instance.currentUser?.getIdTokenResult();
        final claims = idTokenResult?.claims;
        if (claims != null && claims['stations'] != null) {
          final stationsMap = claims['stations'] as Map<dynamic, dynamic>;
          accepted.addAll(stationsMap.keys.cast<String>());
          debugPrint('⚡ getUserStationLists: fallback from claims: $accepted');
        }
      }

      debugPrint('✅ getUserStationLists: accepted=${accepted.length}, pending=${pending.length}');
      return (accepted: accepted, pending: pending);
    } catch (e) {
      debugPrint('❌ getUserStationLists error: $e');
      return (accepted: <String>[], pending: <String>[]);
    }
  }

  // ============================================
  // HELPER METHODS
  // ============================================

  Exception _handleFunctionsException(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return Exception('Authentification requise. Veuillez vous reconnecter.');
      case 'permission-denied':
        return Exception('Vous n\'avez pas les droits nécessaires.');
      case 'not-found':
        return Exception('Ressource non trouvée.');
      case 'already-exists':
        return Exception(e.message ?? 'Cette ressource existe déjà.');
      case 'invalid-argument':
        return Exception(e.message ?? 'Données invalides.');
      case 'failed-precondition':
        return Exception(e.message ?? 'Conditions non remplies.');
      default:
        return Exception(e.message ?? 'Une erreur est survenue.');
    }
  }
}

// ============================================
// RESULT CLASSES
// ============================================

class CreateAccountResult {
  final bool success;
  final String? authUid;
  final List<String> stationsJoined;

  CreateAccountResult({
    required this.success,
    this.authUid,
    this.stationsJoined = const [],
  });
}

class HandleMembershipResult {
  final bool success;
  final String? action;
  final String? matricule;

  HandleMembershipResult({
    required this.success,
    this.action,
    this.matricule,
  });
}

class AddUserResult {
  final bool success;
  final String? authUid;

  AddUserResult({
    required this.success,
    this.authUid,
  });
}

class CreateStationResult {
  final bool success;
  final String? stationId;
  final String? stationName;

  CreateStationResult({
    required this.success,
    this.stationId,
    this.stationName,
  });
}

/// Informations basiques d'une station (pour StationSearchPage)
class StationInfo {
  final String id;
  final String name;
  final int userCount;

  StationInfo({
    required this.id,
    required this.name,
    required this.userCount,
  });

  factory StationInfo.fromJson(Map<String, dynamic> json) {
    return StationInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      userCount: json['userCount'] ?? 0,
    );
  }
}
