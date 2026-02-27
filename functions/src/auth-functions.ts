/**
 * Cloud Functions pour l'authentification et la gestion des utilisateurs
 * - Création de compte
 * - Gestion des demandes d'adhésion
 * - Gestion des custom claims
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
// Note: beforeUserDeleted n'est pas disponible dans firebase-functions v2
// Le nettoyage est effectué par la fonction deleteUser callable
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp, FieldValue} from "firebase-admin/firestore";
import {encryptPII, decryptPII, encryptionKey} from "./crypto-utils.js";

// Types pour les custom claims
interface StationRoles {
  [stationId: string]: "agent" | "leader" | "chief" | "admin";
}

interface CustomClaims {
  sdisId: string;
  role: "agent" | "leader" | "chief" | "admin";
  stations: StationRoles;
}

// Type pour les données de création de compte
interface CreateAccountData {
  email: string;
  password: string;
  matricule: string;
  firstName: string;
  lastName: string;
  sdisId: string;
}

// Type pour les données de demande d'adhésion
interface RequestMembershipData {
  stationId: string;
}

// Type pour la gestion des demandes
interface HandleMembershipData {
  stationId: string;
  requestAuthUid: string;
  action: "accept" | "reject";
  role?: "agent" | "leader" | "chief" | "admin";
  team?: string;
}

// Type pour la réservation de matricule
interface ReserveMatriculeData {
  stationId: string;
  matricule: string;
}

// Type pour l'ajout d'un utilisateur existant
interface AddExistingUserData {
  stationId: string;
  matricule: string;
  role?: "agent" | "leader" | "chief" | "admin";
  team?: string;
}

// Type pour la mise à jour de rôle
interface UpdateUserRoleData {
  stationId: string;
  userMatricule: string;
  newRole: "agent" | "leader" | "chief" | "admin";
}

// Type pour le pré-enregistrement d'un agent
interface PreRegisterAgentData {
  stationId: string;
  matricule: string;
}

// Type pour le retrait d'une station
interface RemoveUserFromStationData {
  stationId: string;
  userMatricule: string;
}

// Type pour la suppression d'un utilisateur
interface DeleteUserData {
  authUid: string;
}

/**
 * Calcule le rôle le plus élevé parmi toutes les stations
 */
function computeHighestRole(stations: StationRoles): CustomClaims["role"] {
  const roleHierarchy: CustomClaims["role"][] = [
    "agent",
    "leader",
    "chief",
    "admin",
  ];
  let highest: CustomClaims["role"] = "agent";

  for (const role of Object.values(stations)) {
    if (roleHierarchy.indexOf(role) > roleHierarchy.indexOf(highest)) {
      highest = role;
    }
  }

  return highest;
}

/**
 * Met à jour les custom claims d'un utilisateur
 */
async function updateUserClaims(
  authUid: string,
  sdisId: string,
  stations: StationRoles
): Promise<void> {
  const auth = getAuth();

  const claims: CustomClaims = {
    sdisId,
    role: computeHighestRole(stations),
    stations,
  };

  await auth.setCustomUserClaims(authUid, claims);
  console.log(`✅ Custom claims updated for user ${authUid}:`, claims);
}

/**
 * Création de compte utilisateur
 * - Crée le compte Firebase Auth
 * - Crée le profil utilisateur dans Firestore (PII chiffrées)
 * - Vérifie les réservations de matricule et auto-affilie si nécessaire
 * - Définit les custom claims
 */
export const createAccount = onCall(
  {region: "europe-west1", secrets: [encryptionKey]},
  async (request) => {
    const data = request.data as CreateAccountData;

    // Validation des données
    if (!data.email || !data.password || !data.matricule ||
        !data.firstName || !data.lastName || !data.sdisId) {
      throw new HttpsError(
        "invalid-argument",
        "Tous les champs sont requis: email, password, matricule, " +
        "firstName, lastName, sdisId"
      );
    }

    // Validation du mot de passe
    if (data.password.length < 6) {
      throw new HttpsError(
        "invalid-argument",
        "Le mot de passe doit contenir au moins 6 caractères"
      );
    }

    const db = getFirestore();
    const auth = getAuth();
    const key = encryptionKey.value();

    try {
      console.log(`🔄 Starting account creation for ${data.email}`);

      // Créer le compte Firebase Auth
      const userRecord = await auth.createUser({
        email: data.email,
        password: data.password,
        displayName: `${data.firstName} ${data.lastName}`,
      });

      console.log(`✅ Firebase Auth user created: ${userRecord.uid}`);

      // Chiffrer les PII (sauf matricule qui est stocké en clair)
      console.log(`🔒 Encrypting PII data...`);
      const encryptedPII = encryptPII({
        firstName: data.firstName,
        lastName: data.lastName,
        email: data.email,
      }, key);
      console.log(`✅ PII encrypted successfully`);

      // Vérifier l'unicité du matricule dans le SDIS
      // Le matricule est en clair pour faciliter la recherche
      console.log(`🔍 Checking matricule uniqueness in SDIS ${data.sdisId}...`);
      const existingUsersSnapshot = await db
        .collection("sdis")
        .doc(data.sdisId)
        .collection("users")
        .where("matricule", "==", data.matricule)
        .get();

      if (!existingUsersSnapshot.empty) {
        console.log(`❌ Matricule already exists in SDIS ${data.sdisId}`);
        // Supprimer le compte Auth créé
        await auth.deleteUser(userRecord.uid);
        throw new HttpsError(
          "already-exists",
          "Ce matricule est déjà utilisé dans ce SDIS"
        );
      }
      console.log(`✅ Matricule is unique in SDIS ${data.sdisId}`);

      // Vérifier si le matricule est pré-enregistré (lookup O(1) via collection index)
      const stations: StationRoles = {};
      const stationsToJoin: string[] = [];

      console.log(`🔍 Checking pre-registration index for matricule ${data.matricule}...`);
      const preRegDoc = await db
        .collection("sdis").doc(data.sdisId)
        .collection("pre_registered_matricules").doc(data.matricule)
        .get();

      if (preRegDoc.exists) {
        const preRegData = preRegDoc.data()!;
        const preRegStationIds = preRegData.stationIds as string[] || [];
        console.log(`✅ Found pre-registration in ${preRegStationIds.length} station(s)`);

        for (const stationId of preRegStationIds) {
          stationsToJoin.push(stationId);
          stations[stationId] = "agent";
        }
      } else {
        console.log(`ℹ️ No pre-registration found for matricule ${data.matricule}`);
      }

      // Créer le profil utilisateur global
      console.log(`💾 Creating user profile in Firestore...`);
      await db
        .collection("sdis")
        .doc(data.sdisId)
        .collection("users")
        .doc(userRecord.uid)
        .set({
          authUid: userRecord.uid,
          matricule: data.matricule, // En clair (non sensible)
          ...encryptedPII, // firstName, lastName, email chiffrés
          acceptedStations: [],
          pendingStations: [],
          createdAt: Timestamp.now(),
        });

      console.log(`✅ User profile created in Firestore`);

      // Lier l'utilisateur aux stations pré-enregistrées
      console.log(`🏢 Linking user to ${stationsToJoin.length} pre-registered station(s)...`);
      for (const stationId of stationsToJoin) {
        // merge: true préserve team/skills déjà assignés par le leader
        await db
          .collection("sdis")
          .doc(data.sdisId)
          .collection("stations")
          .doc(stationId)
          .collection("users")
          .doc(data.matricule)
          .set({
            id: data.matricule,
            authUid: userRecord.uid,
            ...encryptedPII,
            station: stationId,
            createdAt: Timestamp.now(),
          }, {merge: true});

        console.log(`✅ User linked to pre-registered station ${stationId}`);
      }

      // Mettre à jour acceptedStations dans le profil global
      if (stationsToJoin.length > 0) {
        await db
          .collection("sdis").doc(data.sdisId)
          .collection("users").doc(userRecord.uid)
          .update({
            acceptedStations: FieldValue.arrayUnion(...stationsToJoin),
          });
        console.log(`✅ acceptedStations updated with ${stationsToJoin.length} station(s)`);
      }

      // Nettoyer l'index de pré-enregistrement
      if (preRegDoc.exists) {
        await preRegDoc.ref.delete();
        console.log(`🧹 Pre-registration index cleaned up for ${data.matricule}`);
      }

      // Mettre à jour les custom claims
      console.log(`🎫 Updating custom claims...`);
      await updateUserClaims(userRecord.uid, data.sdisId, stations);
      console.log(`✅ Custom claims updated successfully`);

      console.log(`🎉 Account creation complete for ${data.email}`);
      return {
        success: true,
        authUid: userRecord.uid,
        stationsJoined: stationsToJoin,
      };
    } catch (error) {
      console.error("❌ Error creating account:", error);
      console.error("Error details:", JSON.stringify(error, null, 2));

      // Gestion spécifique des erreurs Firebase Auth
      if ((error as {code?: string}).code === "auth/email-already-exists") {
        throw new HttpsError(
          "already-exists",
          "Un compte existe déjà avec cette adresse email"
        );
      }

      // Si c'est déjà une HttpsError, la relancer telle quelle
      if (error instanceof HttpsError) {
        throw error;
      }

      // Pour toute autre erreur, logger et relancer avec détails
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error("Unexpected error:", errorMessage);
      throw new HttpsError(
        "internal",
        `Erreur lors de la création du compte: ${errorMessage}`
      );
    }
  }
);

/**
 * Demande d'adhésion à une caserne
 */
export const requestMembership = onCall(
  {region: "europe-west1", secrets: [encryptionKey]},
  async (request) => {
    // Vérifier l'authentification
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise");
    }

    const data = request.data as RequestMembershipData;
    const callerUid = request.auth.uid;
    const claims = request.auth.token as unknown as CustomClaims;

    if (!data.stationId) {
      throw new HttpsError("invalid-argument", "stationId requis");
    }

    if (!claims.sdisId) {
      throw new HttpsError(
        "failed-precondition",
        "Utilisateur sans SDIS assigné"
      );
    }

    const db = getFirestore();
    // key est utilisé pour le chiffrement si nécessaire dans de futures versions
    void encryptionKey.value();

    // Vérifier qu'il n'y a pas déjà une demande pending
    const existingRequest = await db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("stations")
      .doc(data.stationId)
      .collection("membership_requests")
      .doc(callerUid)
      .get();

    if (existingRequest.exists &&
        existingRequest.data()?.status === "pending") {
      throw new HttpsError(
        "already-exists",
        "Une demande est déjà en attente pour cette caserne"
      );
    }

    // Récupérer le profil utilisateur pour les infos
    const userProfile = await db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("users")
      .doc(callerUid)
      .get();

    if (!userProfile.exists) {
      throw new HttpsError("not-found", "Profil utilisateur non trouvé");
    }

    const userData = userProfile.data()!;

    // Créer la demande d'adhésion
    await db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("stations")
      .doc(data.stationId)
      .collection("membership_requests")
      .doc(callerUid)
      .set({
        authUid: callerUid,
        matricule: userData.matricule,
        firstName_encrypted: userData.firstName_encrypted,
        lastName_encrypted: userData.lastName_encrypted,
        status: "pending",
        requestedAt: Timestamp.now(),
        respondedAt: null,
        respondedBy: null,
      });

    // Ajouter la station aux pendingStations du profil global
    await db.collection("sdis").doc(claims.sdisId).collection("users")
      .doc(callerUid).update({
        pendingStations: FieldValue.arrayUnion(data.stationId),
      });

    // Notifier les admins de la station
    const stationAdminsSnap = await db
      .collection(`sdis/${claims.sdisId}/stations/${data.stationId}/users`)
      .where("admin", "==", true)
      .get();
    const adminMatricules = stationAdminsSnap.docs.map((d) => d.id);
    if (adminMatricules.length > 0) {
      await db
        .collection(`sdis/${claims.sdisId}/stations/${data.stationId}/notificationTriggers`)
        .add({
          type: "membership_requested",
          targetUserIds: adminMatricules,
          agentMatricule: userData.matricule,
          createdAt: Timestamp.now(),
          processed: false,
        });
    }

    console.log(
      `✅ Membership request created for user ${callerUid} ` +
      `to station ${data.stationId}`
    );

    return {success: true};
  }
);

/**
 * Traitement d'une demande d'adhésion (accept/reject)
 */
export const handleMembershipRequest = onCall(
  {region: "europe-west1", secrets: [encryptionKey]},
  async (request) => {
    // Vérifier l'authentification
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise");
    }

    const data = request.data as HandleMembershipData;
    const callerUid = request.auth.uid;
    const claims = request.auth.token as unknown as CustomClaims;

    // Validation
    if (!data.stationId || !data.requestAuthUid || !data.action) {
      throw new HttpsError(
        "invalid-argument",
        "stationId, requestAuthUid et action requis"
      );
    }

    // Vérifier que l'appelant est admin de la station
    if (!claims.stations?.[data.stationId] ||
        claims.stations[data.stationId] !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Seuls les admins peuvent gérer les demandes d'adhésion"
      );
    }

    const db = getFirestore();
    const auth = getAuth();

    // Récupérer la demande
    const requestRef = db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("stations")
      .doc(data.stationId)
      .collection("membership_requests")
      .doc(data.requestAuthUid);

    const requestDoc = await requestRef.get();

    if (!requestDoc.exists) {
      throw new HttpsError("not-found", "Demande non trouvée");
    }

    const requestData = requestDoc.data()!;

    if (requestData.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        "Cette demande a déjà été traitée"
      );
    }

    if (data.action === "reject") {
      // Simplement mettre à jour le statut
      await requestRef.update({
        status: "rejected",
        respondedAt: Timestamp.now(),
        respondedBy: callerUid,
      });

      // Retirer la station des pendingStations du profil global
      await db.collection("sdis").doc(claims.sdisId).collection("users")
        .doc(data.requestAuthUid).update({
          pendingStations: FieldValue.arrayRemove(data.stationId),
        });

      // Notifier l'utilisateur refusé
      const rejectedMatricule = requestData.matricule as string | undefined;
      if (rejectedMatricule) {
        const stationDocRej = await db
          .collection(`sdis/${claims.sdisId}/stations`)
          .doc(data.stationId)
          .get();
        const stationNameRej = (stationDocRej.data()?.name as string | undefined) || data.stationId;
        await db
          .collection(`sdis/${claims.sdisId}/stations/${data.stationId}/notificationTriggers`)
          .add({
            type: "membership_rejected",
            targetUserIds: [rejectedMatricule],
            stationName: stationNameRej,
            createdAt: Timestamp.now(),
            processed: false,
          });
      }

      console.log(
        `❌ Membership request rejected for user ${data.requestAuthUid}`
      );

      return {success: true, action: "rejected"};
    }

    // Action = accept
    // Récupérer le profil global de l'utilisateur
    const userProfileRef = db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("users")
      .doc(data.requestAuthUid);

    const userProfile = await userProfileRef.get();

    if (!userProfile.exists) {
      throw new HttpsError("not-found", "Profil utilisateur non trouvé");
    }

    const userData = userProfile.data()!;

    // Le matricule est en clair
    const matricule = userData.matricule;
    const role = data.role || "agent";

    // Créer le profil dans la station
    await db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("stations")
      .doc(data.stationId)
      .collection("users")
      .doc(matricule)
      .set({
        id: matricule,
        authUid: data.requestAuthUid,
        firstName_encrypted: userData.firstName_encrypted,
        lastName_encrypted: userData.lastName_encrypted,
        email_encrypted: userData.email_encrypted,
        matricule: userData.matricule,
        station: data.stationId,
        status: role,
        admin: role === "admin",
        team: data.team || "",
        skills: [],
        keySkills: [],
        personalAlertEnabled: false,
        personalAlertHour: 18,
        membershipAlertEnabled: role === "admin",
        createdAt: Timestamp.now(),
      });

    // Mettre à jour la demande
    await requestRef.update({
      status: "accepted",
      respondedAt: Timestamp.now(),
      respondedBy: callerUid,
    });

    // Mettre à jour les custom claims de l'utilisateur accepté
    const currentUser = await auth.getUser(data.requestAuthUid);
    const currentClaims = (currentUser.customClaims || {}) as CustomClaims;
    const updatedStations = {
      ...currentClaims.stations,
      [data.stationId]: role,
    };

    await updateUserClaims(
      data.requestAuthUid,
      claims.sdisId,
      updatedStations
    );

    // Mettre à jour acceptedStations et pendingStations du profil global
    await userProfileRef.update({
      acceptedStations: FieldValue.arrayUnion(data.stationId),
      pendingStations: FieldValue.arrayRemove(data.stationId),
    });

    // Notifier l'utilisateur accepté
    const stationDocAcc = await db
      .collection(`sdis/${claims.sdisId}/stations`)
      .doc(data.stationId)
      .get();
    const stationNameAcc = (stationDocAcc.data()?.name as string | undefined) || data.stationId;
    await db
      .collection(`sdis/${claims.sdisId}/stations/${data.stationId}/notificationTriggers`)
      .add({
        type: "membership_accepted",
        targetUserIds: [matricule],
        stationName: stationNameAcc,
        createdAt: Timestamp.now(),
        processed: false,
      });

    console.log(
      `✅ Membership request accepted for user ${data.requestAuthUid} ` +
      `to station ${data.stationId} with role ${role}`
    );

    return {
      success: true,
      action: "accepted",
      matricule,
    };
  }
);

/**
 * Réservation d'un matricule pour pré-affiliation
 */
export const reserveMatricule = onCall({region: "europe-west1"}, async (request) => {
  // Vérifier l'authentification
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentification requise");
  }

  const data = request.data as ReserveMatriculeData;
  const callerUid = request.auth.uid;
  const claims = request.auth.token as unknown as CustomClaims;

  // Validation
  if (!data.stationId || !data.matricule) {
    throw new HttpsError(
      "invalid-argument",
      "stationId et matricule requis"
    );
  }

  // Vérifier que l'appelant est admin de la station
  if (!claims.stations?.[data.stationId] ||
      claims.stations[data.stationId] !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Seuls les admins peuvent réserver des matricules"
    );
  }

  const db = getFirestore();

  // Vérifier si le matricule n'est pas déjà réservé pour cette station
  const existingReservation = await db
    .collection("sdis")
    .doc(claims.sdisId)
    .collection("stations")
    .doc(data.stationId)
    .collection("reserved_matricules")
    .doc(data.matricule)
    .get();

  if (existingReservation.exists) {
    throw new HttpsError(
      "already-exists",
      "Ce matricule est déjà réservé pour cette caserne"
    );
  }

  // Créer la réservation
  await db
    .collection("sdis")
    .doc(claims.sdisId)
    .collection("stations")
    .doc(data.stationId)
    .collection("reserved_matricules")
    .doc(data.matricule)
    .set({
      matricule: data.matricule,
      reservedBy: callerUid,
      reservedAt: Timestamp.now(),
    });

  console.log(
    `✅ Matricule ${data.matricule} reserved for station ${data.stationId}`
  );

  return {success: true};
});

/**
 * Pré-enregistrement d'un agent dans une station
 * Crée un profil station minimal (sans PII) pour anticiper la création de compte.
 * Accessible aux leaders et admins de la station.
 */
export const preRegisterAgent = onCall({region: "europe-west1"}, async (request) => {
  // Vérifier l'authentification
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentification requise");
  }

  const data = request.data as PreRegisterAgentData;
  const callerUid = request.auth.uid;
  const claims = request.auth.token as unknown as CustomClaims;

  // Validation
  if (!data.stationId || !data.matricule) {
    throw new HttpsError(
      "invalid-argument",
      "stationId et matricule requis"
    );
  }

  const matricule = data.matricule.trim();
  if (!matricule) {
    throw new HttpsError("invalid-argument", "Le matricule ne peut pas être vide");
  }

  // Vérifier que l'appelant est admin OU leader de la station
  const callerRole = claims.stations?.[data.stationId];
  if (!callerRole || (callerRole !== "admin" && callerRole !== "leader")) {
    throw new HttpsError(
      "permission-denied",
      "Seuls les admins et leaders peuvent pré-enregistrer des agents"
    );
  }

  const db = getFirestore();

  // Vérifier si le matricule n'existe pas déjà comme user dans cette station
  const existingUser = await db
    .collection("sdis").doc(claims.sdisId)
    .collection("stations").doc(data.stationId)
    .collection("users").doc(matricule)
    .get();

  if (existingUser.exists) {
    throw new HttpsError(
      "already-exists",
      "Ce matricule existe déjà dans cette caserne"
    );
  }

  // Vérifier si le matricule correspond à un compte existant dans le SDIS
  const globalUserSnapshot = await db
    .collection("sdis").doc(claims.sdisId)
    .collection("users")
    .where("matricule", "==", matricule)
    .limit(1)
    .get();

  if (!globalUserSnapshot.empty) {
    throw new HttpsError(
      "already-exists",
      "Ce matricule correspond à un compte existant. " +
      "Utilisez 'Ajouter un utilisateur existant' à la place."
    );
  }

  // Créer le profil station minimal (sans PII, sans authUid)
  await db
    .collection("sdis").doc(claims.sdisId)
    .collection("stations").doc(data.stationId)
    .collection("users").doc(matricule)
    .set({
      id: matricule,
      station: data.stationId,
      status: "agent",
      admin: false,
      team: "",
      skills: [],
      keySkills: [],
      personalAlertEnabled: true,
    });

  // Créer/mettre à jour l'index de pré-enregistrement pour lookup O(1)
  const indexRef = db
    .collection("sdis").doc(claims.sdisId)
    .collection("pre_registered_matricules").doc(matricule);

  const indexDoc = await indexRef.get();
  if (indexDoc.exists) {
    await indexRef.update({
      stationIds: FieldValue.arrayUnion(data.stationId),
    });
  } else {
    await indexRef.set({
      matricule: matricule,
      stationIds: [data.stationId],
      createdBy: callerUid,
      createdAt: Timestamp.now(),
    });
  }

  console.log(
    `✅ Agent ${matricule} pré-enregistré pour la station ${data.stationId}`
  );

  return {success: true};
});

/**
 * Ajout d'un utilisateur existant à une station
 */
export const addExistingUserToStation = onCall(
  {region: "europe-west1", secrets: [encryptionKey]},
  async (request) => {
    // Vérifier l'authentification
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise");
    }

    const data = request.data as AddExistingUserData;
    const claims = request.auth.token as unknown as CustomClaims;

    // Validation
    if (!data.stationId || !data.matricule) {
      throw new HttpsError(
        "invalid-argument",
        "stationId et matricule requis"
      );
    }

    // Vérifier que l'appelant est admin de la station
    if (!claims.stations?.[data.stationId] ||
        claims.stations[data.stationId] !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Seuls les admins peuvent ajouter des utilisateurs"
      );
    }

    const db = getFirestore();
    const auth = getAuth();

    // Chercher l'utilisateur par matricule (en clair)
    const usersSnapshot = await db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("users")
      .where("matricule", "==", data.matricule)
      .limit(1)
      .get();

    if (usersSnapshot.empty) {
      throw new HttpsError(
        "not-found",
        "Aucun utilisateur trouvé avec ce matricule"
      );
    }

    const targetDoc = usersSnapshot.docs[0];
    const targetUser = targetDoc.data();
    const targetAuthUid = targetDoc.id;

    const role = data.role || "agent";

    // Créer le profil dans la station
    await db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("stations")
      .doc(data.stationId)
      .collection("users")
      .doc(data.matricule)
      .set({
        id: data.matricule,
        authUid: targetAuthUid,
        firstName_encrypted: targetUser.firstName_encrypted,
        lastName_encrypted: targetUser.lastName_encrypted,
        email_encrypted: targetUser.email_encrypted,
        station: data.stationId,
        status: role,
        admin: role === "admin",
        team: data.team || "",
        skills: [],
        keySkills: [],
        personalAlertEnabled: true,
        membershipAlertEnabled: role === "admin",
        createdAt: Timestamp.now(),
      });

    // Mettre à jour les custom claims
    const currentUser = await auth.getUser(targetAuthUid);
    const currentClaims = (currentUser.customClaims || {}) as CustomClaims;
    const updatedStations = {
      ...currentClaims.stations,
      [data.stationId]: role,
    };

    await updateUserClaims(targetAuthUid, claims.sdisId, updatedStations);

    // Ajouter la station aux acceptedStations du profil global
    await db.collection("sdis").doc(claims.sdisId).collection("users")
      .doc(targetAuthUid).update({
        acceptedStations: FieldValue.arrayUnion(data.stationId),
      });

    console.log(
      `✅ User ${data.matricule} added to station ${data.stationId}`
    );

    return {
      success: true,
      authUid: targetAuthUid,
    };
  }
);

/**
 * Mise à jour du rôle d'un utilisateur dans une station
 */
export const updateUserRole = onCall({region: "europe-west1"}, async (request) => {
  // Vérifier l'authentification
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentification requise");
  }

  const data = request.data as UpdateUserRoleData;
  const claims = request.auth.token as unknown as CustomClaims;

  // Validation
  if (!data.stationId || !data.userMatricule || !data.newRole) {
    throw new HttpsError(
      "invalid-argument",
      "stationId, userMatricule et newRole requis"
    );
  }

  // Vérifier que l'appelant est admin de la station
  if (!claims.stations?.[data.stationId] ||
      claims.stations[data.stationId] !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Seuls les admins peuvent modifier les rôles"
    );
  }

  const db = getFirestore();
  const auth = getAuth();

  // Récupérer le profil utilisateur dans la station
  const userRef = db
    .collection("sdis")
    .doc(claims.sdisId)
    .collection("stations")
    .doc(data.stationId)
    .collection("users")
    .doc(data.userMatricule);

  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    throw new HttpsError("not-found", "Utilisateur non trouvé dans la station");
  }

  const userData = userDoc.data()!;
  const targetAuthUid = userData.authUid;

  // Mettre à jour le profil Firestore
  await userRef.update({
    status: data.newRole,
    admin: data.newRole === "admin",
    membershipAlertEnabled: data.newRole === "admin",
  });

  // Mettre à jour les custom claims
  const currentUser = await auth.getUser(targetAuthUid);
  const currentClaims = (currentUser.customClaims || {}) as CustomClaims;
  const updatedStations = {
    ...currentClaims.stations,
    [data.stationId]: data.newRole,
  };

  await updateUserClaims(targetAuthUid, claims.sdisId, updatedStations);

  console.log(
    `✅ User ${data.userMatricule} role updated to ${data.newRole} ` +
    `in station ${data.stationId}`
  );

  return {success: true};
});

/**
 * Retrait d'un utilisateur d'une station
 */
export const removeUserFromStation = onCall({region: "europe-west1"}, async (request) => {
  // Vérifier l'authentification
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentification requise");
  }

  const data = request.data as RemoveUserFromStationData;
  const claims = request.auth.token as unknown as CustomClaims;

  // Validation
  if (!data.stationId || !data.userMatricule) {
    throw new HttpsError(
      "invalid-argument",
      "stationId et userMatricule requis"
    );
  }

  // Vérifier que l'appelant est admin de la station
  if (!claims.stations?.[data.stationId] ||
      claims.stations[data.stationId] !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Seuls les admins peuvent retirer des utilisateurs"
    );
  }

  const db = getFirestore();
  const auth = getAuth();

  // Récupérer le profil utilisateur dans la station
  const userRef = db
    .collection("sdis")
    .doc(claims.sdisId)
    .collection("stations")
    .doc(data.stationId)
    .collection("users")
    .doc(data.userMatricule);

  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    throw new HttpsError("not-found", "Utilisateur non trouvé dans la station");
  }

  const userData = userDoc.data()!;
  const targetAuthUid = userData.authUid;

  // Supprimer le profil de la station
  await userRef.delete();

  // Mettre à jour les custom claims et le profil global seulement si l'utilisateur a un compte
  if (targetAuthUid) {
    try {
      const currentUser = await auth.getUser(targetAuthUid);
      const currentClaims = (currentUser.customClaims || {}) as CustomClaims;
      const updatedStations = {...currentClaims.stations};
      delete updatedStations[data.stationId];

      await updateUserClaims(targetAuthUid, claims.sdisId, updatedStations);

      // Retirer la station des acceptedStations du profil global
      await db.collection("sdis").doc(claims.sdisId).collection("users")
        .doc(targetAuthUid).update({
          acceptedStations: FieldValue.arrayRemove(data.stationId),
        });
    } catch (e) {
      console.warn(`⚠️ Could not update claims/profile for ${targetAuthUid}: ${e}`);
    }
  }

  // Nettoyer l'index de pré-enregistrement si existant
  const preRegRef = db
    .collection("sdis").doc(claims.sdisId)
    .collection("pre_registered_matricules").doc(data.userMatricule);
  const preRegDoc = await preRegRef.get();
  if (preRegDoc.exists) {
    const stationIds = preRegDoc.data()!.stationIds as string[] || [];
    if (stationIds.length <= 1) {
      await preRegRef.delete();
    } else {
      await preRegRef.update({
        stationIds: FieldValue.arrayRemove(data.stationId),
      });
    }
    console.log(`🧹 Pre-registration index cleaned up for ${data.userMatricule}`);
  }

  console.log(
    `✅ User ${data.userMatricule} removed from station ${data.stationId}`
  );

  return {success: true};
});

/**
 * Suppression complète d'un utilisateur
 */
export const deleteUser = onCall(
  {region: "europe-west1", secrets: [encryptionKey]},
  async (request) => {
    // Vérifier l'authentification
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise");
    }

    const data = request.data as DeleteUserData;
    const claims = request.auth.token as unknown as CustomClaims;

    // Validation
    if (!data.authUid) {
      throw new HttpsError("invalid-argument", "authUid requis");
    }

    // Vérifier que l'appelant est admin d'au moins une station
    const isAdmin = Object.values(claims.stations || {}).includes("admin");
    if (!isAdmin) {
      throw new HttpsError(
        "permission-denied",
        "Seuls les admins peuvent supprimer des utilisateurs"
      );
    }

    const db = getFirestore();
    const auth = getAuth();

    // Récupérer l'utilisateur cible
    const targetUser = await auth.getUser(data.authUid);
    const targetClaims = (targetUser.customClaims || {}) as CustomClaims;

    // Vérifier que l'utilisateur appartient au même SDIS
    if (targetClaims.sdisId !== claims.sdisId) {
      throw new HttpsError(
        "permission-denied",
        "Vous ne pouvez supprimer que des utilisateurs de votre SDIS"
      );
    }

    // Récupérer le profil global pour obtenir le matricule
    const userProfileRef = db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("users")
      .doc(data.authUid);

    const userProfile = await userProfileRef.get();

    if (userProfile.exists) {
      const userData = userProfile.data()!;
      // Le matricule est en clair
      const matricule = userData.matricule;

      if (matricule) {
        // Supprimer de toutes les stations
        for (const stationId of Object.keys(targetClaims.stations || {})) {
          const stationUserRef = db
            .collection("sdis")
            .doc(claims.sdisId)
            .collection("stations")
            .doc(stationId)
            .collection("users")
            .doc(matricule);

          await stationUserRef.delete();
          console.log(`✅ User deleted from station ${stationId}`);
        }
      }

      // Supprimer le profil global
      await userProfileRef.delete();
      console.log(`✅ User global profile deleted`);
    }

    // Supprimer le compte Firebase Auth
    await auth.deleteUser(data.authUid);
    console.log(`✅ Firebase Auth user deleted: ${data.authUid}`);

    return {success: true};
  }
);

// Note: Le nettoyage automatique n'est pas implémenté via trigger
// car beforeUserDeleted n'est pas disponible dans firebase-functions v2.
// Utilisez la fonction deleteUser callable pour supprimer un utilisateur,
// elle nettoie automatiquement toutes les données Firestore.

// Type pour la création de station avec code
interface CreateStationWithCodeData {
  code: string;
  matricule?: string; // Matricule fourni par l'utilisateur (optionnel)
}

/**
 * Crée une nouvelle station en utilisant un code d'authentification
 * - Vérifie que le code existe et n'est pas consommé
 * - Génère un UUID pour la station
 * - Crée la station avec subscriptionEndDate basée sur trial/premium
 * - Ajoute l'utilisateur comme premier membre avec admin=true
 * - Met à jour les custom claims
 */
export const createStationWithCode = onCall(
  {region: "europe-west1", secrets: [encryptionKey]},
  async (request) => {
    // Vérifier l'authentification
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise");
    }

    const data = request.data as CreateStationWithCodeData;
    const claims = request.auth.token as unknown as CustomClaims;

    if (!data.code) {
      throw new HttpsError("invalid-argument", "Code requis");
    }

    if (!claims.sdisId) {
      throw new HttpsError(
        "failed-precondition",
        "Utilisateur sans SDIS assigné"
      );
    }

    const db = getFirestore();
    const key = encryptionKey.value();

    try {
      console.log(`🔍 Validating auth code: ${data.code}`);

      // Chercher le code dans /sdis/{sdisId}/auth_codes
      const authCodesSnapshot = await db
        .collection("sdis")
        .doc(claims.sdisId)
        .collection("auth_codes")
        .where("code", "==", data.code)
        .limit(1)
        .get();

      if (authCodesSnapshot.empty) {
        console.log(`❌ Auth code not found: ${data.code}`);
        throw new HttpsError(
          "not-found",
          "Code d'authentification invalide"
        );
      }

      const authCodeDoc = authCodesSnapshot.docs[0];
      const authCodeData = authCodeDoc.data();

      // Vérifier que le code n'est pas déjà consommé
      if (authCodeData.consumed) {
        console.log(`❌ Auth code already consumed: ${data.code}`);
        throw new HttpsError(
          "already-exists",
          "Ce code a déjà été utilisé"
        );
      }

      console.log(`✅ Auth code valid: ${authCodeData.stationName}`);

      // Récupérer ou créer le profil utilisateur global
      const userProfileRef = db
        .collection("sdis")
        .doc(claims.sdisId)
        .collection("users")
        .doc(request.auth.uid);

      const userProfileDoc = await userProfileRef.get();

      let userProfileData: any;
      let decrypted: any;

      if (!userProfileDoc.exists) {
        // Le profil global n'existe pas, le créer maintenant
        console.log(`⚠️ User profile doesn't exist in global collection, creating it...`);

        // Récupérer les données depuis Firebase Auth
        const authUser = await getAuth().getUser(request.auth.uid);
        const email = authUser.email || "";
        const displayName = authUser.displayName || "";

        // Extraire prénom et nom du displayName (si disponible)
        const nameParts = displayName.split(" ");
        const firstName = nameParts[0] || "Utilisateur";
        const lastName = nameParts.slice(1).join(" ") || "";

        // Utiliser le matricule fourni ou générer un temporaire
        const matricule = data.matricule || String(Date.now()).slice(-6);
        console.log(`📝 Using matricule: ${matricule} ${data.matricule ? "(provided)" : "(generated)"}`);

        // Chiffrer les PII (sauf matricule qui est en clair)
        const encrypted = encryptPII({
          firstName: firstName,
          lastName: lastName,
          email: email,
        }, key);

        // Créer le profil global
        const newProfileData = {
          authUid: request.auth.uid,
          matricule: matricule, // Matricule en clair (non sensible)
          firstName_encrypted: encrypted.firstName_encrypted,
          lastName_encrypted: encrypted.lastName_encrypted,
          email_encrypted: encrypted.email_encrypted,
          acceptedStations: [],
          pendingStations: [],
          createdAt: Timestamp.now(),
        };

        await userProfileRef.set(newProfileData);
        console.log(`✅ Global user profile created with matricule: ${matricule}`);

        userProfileData = newProfileData;
        decrypted = {
          firstName: firstName,
          lastName: lastName,
          email: email,
          matricule: matricule,
        };
      } else {
        userProfileData = userProfileDoc.data()!;

        // Déchiffrer les PII
        decrypted = decryptPII({
          firstName_encrypted: userProfileData.firstName_encrypted,
          lastName_encrypted: userProfileData.lastName_encrypted,
          email_encrypted: userProfileData.email_encrypted,
        }, key);

        // Le matricule est stocké en clair
        const storedMatricule = userProfileData.matricule;

        // Si un matricule est fourni et différent de celui stocké, mettre à jour
        if (data.matricule && data.matricule !== storedMatricule) {
          console.log(`📝 Updating matricule from ${storedMatricule} to ${data.matricule}`);

          await userProfileRef.update({
            matricule: data.matricule, // Matricule en clair (non sensible)
          });

          console.log(`✅ Matricule updated to: ${data.matricule}`);
          decrypted.matricule = data.matricule;
        } else {
          decrypted.matricule = storedMatricule;
        }
      }

      console.log(`👤 User matricule: ${decrypted.matricule}`);

      // Générer un UUID pour la station
      const stationId = `station_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
      console.log(`🏢 Creating station with ID: ${stationId}`);

      // Calculer la date de fin d'abonnement
      const now = Date.now();
      const durationMs = authCodeData.trial
        ? 30 * 24 * 60 * 60 * 1000  // 30 jours
        : 365 * 24 * 60 * 60 * 1000; // 1 an
      const subscriptionEndDate = Timestamp.fromMillis(now + durationMs);

      console.log(
        `📅 Subscription: ${authCodeData.trial ? "Trial (30 days)" : "Premium (1 year)"}`
      );

      // Créer la station
      await db
        .collection("sdis")
        .doc(claims.sdisId)
        .collection("stations")
        .doc(stationId)
        .set({
          name: authCodeData.stationName,
          subscriptionEndDate: subscriptionEndDate,
          createdAt: Timestamp.now(),
          createdBy: request.auth.uid,
        });

      console.log(`✅ Station created: ${authCodeData.stationName}`);

      // Créer le profil utilisateur dans la station
      const userMatricule = decrypted.matricule || request.auth.uid;
      await db
        .collection("sdis")
        .doc(claims.sdisId)
        .collection("stations")
        .doc(stationId)
        .collection("users")
        .doc(userMatricule)
        .set({
          id: userMatricule,
          authUid: request.auth.uid,
          matricule: userMatricule,
          firstName_encrypted: userProfileData.firstName_encrypted,
          lastName_encrypted: userProfileData.lastName_encrypted,
          email_encrypted: userProfileData.email_encrypted,
          station: stationId,
          status: "agent",
          admin: true,
          team: "",
          skills: [],
          keySkills: [],
          personalAlertEnabled: true,
          personalAlertHour: 18,
          membershipAlertEnabled: true,
          createdAt: Timestamp.now(),
        });

      console.log(`✅ User added to station as admin`);

      // Mettre à jour les custom claims
      const updatedStations: StationRoles = {
        ...(claims.stations || {}),
        [stationId]: "admin",
      };

      await updateUserClaims(
        request.auth.uid,
        claims.sdisId,
        updatedStations
      );

      console.log(`✅ Custom claims updated`);

      // Ajouter la station aux acceptedStations du profil global
      await userProfileRef.update({
        acceptedStations: FieldValue.arrayUnion(stationId),
      });

      // Marquer le code comme consommé
      await authCodeDoc.ref.update({
        consumed: true,
        consumedAt: Timestamp.now(),
        consumedBy: request.auth.uid,
      });

      console.log(`✅ Auth code marked as consumed`);

      return {
        success: true,
        stationId: stationId,
        stationName: authCodeData.stationName,
      };
    } catch (error) {
      console.error("❌ Error creating station:", error);

      // Si c'est déjà une HttpsError, la relancer
      if (error instanceof HttpsError) {
        throw error;
      }

      // Pour toute autre erreur, logger et relancer avec détails
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error("Unexpected error:", errorMessage);
      throw new HttpsError(
        "internal",
        `Erreur lors de la création de la station: ${errorMessage}`
      );
    }
  }
);
