/**
 * Cloud Functions pour la lecture des données utilisateurs
 * avec déchiffrement des PII
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {decryptPII, encryptionKey} from "./crypto-utils.js";

// Types pour les custom claims
interface StationRoles {
  [stationId: string]: "agent" | "leader" | "chief" | "admin";
}

interface CustomClaims {
  sdisId: string;
  role: "agent" | "leader" | "chief" | "admin";
  stations: StationRoles;
}

// Types de réponse
interface UserProfile {
  authUid: string;
  email: string;
  matricule: string;
  firstName: string;
  lastName: string;
  createdAt: string;
}

interface StationUser {
  id: string;
  authUid: string;
  email?: string;
  matricule: string;
  firstName: string;
  lastName: string;
  station: string;
  status: string;
  admin: boolean;
  team: string;
  skills: string[];
  keySkills: string[];
  personalAlertEnabled: boolean;
  chiefAlertEnabled: boolean;
  anomalyAlertEnabled: boolean;
  positionId?: string;
  agentAvailabilityStatus?: string;
  suspensionStartDate?: string;
}

interface MembershipRequest {
  authUid: string;
  matricule: string;
  firstName: string;
  lastName: string;
  status: "pending" | "accepted" | "rejected";
  requestedAt: string;
  respondedAt: string | null;
  respondedBy: string | null;
}

/**
 * Récupère le profil utilisateur (avec déchiffrement)
 */
export const getUserProfile = onCall(
  {secrets: [encryptionKey]},
  async (request) => {
    // Vérifier l'authentification
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise");
    }

    const targetUid = (request.data?.authUid as string) || request.auth.uid;
    const claims = request.auth.token as unknown as CustomClaims;

    if (!claims.sdisId) {
      throw new HttpsError(
        "failed-precondition",
        "Utilisateur sans SDIS assigné"
      );
    }

    // Un utilisateur ne peut voir que son propre profil sauf s'il est admin
    if (targetUid !== request.auth.uid &&
        !Object.values(claims.stations || {}).includes("admin")) {
      throw new HttpsError(
        "permission-denied",
        "Vous ne pouvez consulter que votre propre profil"
      );
    }

    const db = getFirestore();
    const key = encryptionKey.value();

    const userRef = db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("users")
      .doc(targetUid);

    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw new HttpsError("not-found", "Profil utilisateur non trouvé");
    }

    const userData = userDoc.data()!;

    // Déchiffrer les PII
    const decrypted = decryptPII({
      firstName_encrypted: userData.firstName_encrypted,
      lastName_encrypted: userData.lastName_encrypted,
      email_encrypted: userData.email_encrypted,
    }, key);

    const profile: UserProfile = {
      authUid: userData.authUid,
      email: decrypted.email || "",
      matricule: userData.matricule || "", // Le matricule est en clair
      firstName: decrypted.firstName || "",
      lastName: decrypted.lastName || "",
      createdAt: userData.createdAt?.toDate?.()?.toISOString() || "",
    };

    return profile;
  }
);

/**
 * Récupère la liste des utilisateurs d'une station (avec déchiffrement)
 */
export const getStationUsers = onCall(
  {secrets: [encryptionKey]},
  async (request) => {
    // Vérifier l'authentification
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise");
    }

    const stationId = request.data?.stationId as string;
    const claims = request.auth.token as unknown as CustomClaims;

    if (!stationId) {
      throw new HttpsError("invalid-argument", "stationId requis");
    }

    if (!claims.sdisId) {
      throw new HttpsError(
        "failed-precondition",
        "Utilisateur sans SDIS assigné"
      );
    }

    // Vérifier que l'utilisateur a accès à cette station
    if (!claims.stations?.[stationId]) {
      throw new HttpsError(
        "permission-denied",
        "Vous n'avez pas accès à cette caserne"
      );
    }

    const db = getFirestore();
    const key = encryptionKey.value();

    const usersSnapshot = await db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("stations")
      .doc(stationId)
      .collection("users")
      .get();

    const users: StationUser[] = [];

    for (const doc of usersSnapshot.docs) {
      const userData = doc.data();

      // Déchiffrer les PII
      const decrypted = decryptPII({
        firstName_encrypted: userData.firstName_encrypted,
        lastName_encrypted: userData.lastName_encrypted,
        email_encrypted: userData.email_encrypted,
        
      }, key);

      users.push({
        id: doc.id,
        authUid: userData.authUid || "",
        email: decrypted.email,
        matricule: userData.matricule || doc.id,
        firstName: decrypted.firstName || userData.firstName || "",
        lastName: decrypted.lastName || userData.lastName || "",
        station: userData.station || stationId,
        status: userData.status || "agent",
        admin: userData.admin || false,
        team: userData.team || "",
        skills: userData.skills || [],
        keySkills: userData.keySkills || [],
        personalAlertEnabled: userData.personalAlertEnabled ?? true,
        chiefAlertEnabled: userData.chiefAlertEnabled ?? false,
        anomalyAlertEnabled: userData.anomalyAlertEnabled ?? false,
        positionId: userData.positionId,
        agentAvailabilityStatus: userData.agentAvailabilityStatus || "active",
        suspensionStartDate: userData.suspensionStartDate
          ? (typeof userData.suspensionStartDate === "string"
              ? userData.suspensionStartDate
              : (userData.suspensionStartDate as {toDate: () => Date}).toDate().toISOString())
          : undefined,
      });
    }

    return {users};
  }
);

/**
 * Récupère les demandes d'adhésion en attente (avec déchiffrement)
 */
export const getMembershipRequests = onCall(
  {secrets: [encryptionKey]},
  async (request) => {
    // Vérifier l'authentification
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise");
    }

    const stationId = request.data?.stationId as string;
    const statusFilter = request.data?.status as string | undefined;
    const claims = request.auth.token as unknown as CustomClaims;

    if (!stationId) {
      throw new HttpsError("invalid-argument", "stationId requis");
    }

    if (!claims.sdisId) {
      throw new HttpsError(
        "failed-precondition",
        "Utilisateur sans SDIS assigné"
      );
    }

    // Vérifier que l'utilisateur est admin de cette station
    if (!claims.stations?.[stationId] ||
        claims.stations[stationId] !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Seuls les admins peuvent voir les demandes d'adhésion"
      );
    }

    const db = getFirestore();
    const key = encryptionKey.value();

    let query = db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("stations")
      .doc(stationId)
      .collection("membership_requests") as FirebaseFirestore.Query;

    if (statusFilter) {
      query = query.where("status", "==", statusFilter);
    }

    const requestsSnapshot = await query.get();

    const requests: MembershipRequest[] = [];

    for (const doc of requestsSnapshot.docs) {
      const requestData = doc.data();

      // Déchiffrer les PII
      const decrypted = decryptPII({
        firstName_encrypted: requestData.firstName_encrypted,
        lastName_encrypted: requestData.lastName_encrypted,
        
      }, key);

      requests.push({
        authUid: requestData.authUid || doc.id,
        matricule: requestData.matricule || "", // Le matricule est en clair
        firstName: decrypted.firstName || "",
        lastName: decrypted.lastName || "",
        status: requestData.status || "pending",
        requestedAt: requestData.requestedAt?.toDate?.()?.toISOString() || "",
        respondedAt: requestData.respondedAt?.toDate?.()?.toISOString() || null,
        respondedBy: requestData.respondedBy || null,
      });
    }

    return {requests};
  }
);

/**
 * Récupère le nombre de demandes d'adhésion en attente
 * (pour l'affichage de la pastille)
 */
export const getPendingMembershipRequestsCount = onCall(async (request) => {
  // Vérifier l'authentification
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentification requise");
  }

  const stationId = request.data?.stationId as string;
  const claims = request.auth.token as unknown as CustomClaims;

  if (!stationId) {
    throw new HttpsError("invalid-argument", "stationId requis");
  }

  if (!claims.sdisId) {
    throw new HttpsError(
      "failed-precondition",
      "Utilisateur sans SDIS assigné"
    );
  }

  // Vérifier que l'utilisateur est admin de cette station
  if (!claims.stations?.[stationId] ||
      claims.stations[stationId] !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Seuls les admins peuvent voir les demandes d'adhésion"
    );
  }

  const db = getFirestore();

  const requestsSnapshot = await db
    .collection("sdis")
    .doc(claims.sdisId)
    .collection("stations")
    .doc(stationId)
    .collection("membership_requests")
    .where("status", "==", "pending")
    .count()
    .get();

  return {count: requestsSnapshot.data().count};
});

/**
 * Récupère la liste des casernes du SDIS (pour StationSearchPage)
 */
export const getSDISStations = onCall(async (request) => {
  // Vérifier l'authentification
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentification requise");
  }

  const claims = request.auth.token as unknown as CustomClaims;

  if (!claims.sdisId) {
    throw new HttpsError(
      "failed-precondition",
      "Utilisateur sans SDIS assigné"
    );
  }

  const db = getFirestore();

  const stationsSnapshot = await db
    .collection("sdis")
    .doc(claims.sdisId)
    .collection("stations")
    .get();

  const stations: Array<{
    id: string;
    name: string;
    userCount: number;
  }> = [];

  for (const doc of stationsSnapshot.docs) {
    const stationData = doc.data();

    // Compter les utilisateurs
    const usersCount = await db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("stations")
      .doc(doc.id)
      .collection("users")
      .count()
      .get();

    stations.push({
      id: doc.id,
      name: stationData.name || doc.id,
      userCount: usersCount.data().count,
    });
  }

  return {stations};
});

/**
 * Récupère les demandes d'adhésion de l'utilisateur courant
 * (pour voir le statut de ses demandes)
 */
export const getMyMembershipRequests = onCall(async (request) => {
  // Vérifier l'authentification
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentification requise");
  }

  const callerUid = request.auth.uid;
  const claims = request.auth.token as unknown as CustomClaims;

  if (!claims.sdisId) {
    throw new HttpsError(
      "failed-precondition",
      "Utilisateur sans SDIS assigné"
    );
  }

  const db = getFirestore();

  // Récupérer toutes les stations
  const stationsSnapshot = await db
    .collection("sdis")
    .doc(claims.sdisId)
    .collection("stations")
    .get();

  const myRequests: Array<{
    stationId: string;
    stationName: string;
    status: "pending" | "accepted" | "rejected";
    requestedAt: string;
  }> = [];

  for (const stationDoc of stationsSnapshot.docs) {
    const requestDoc = await db
      .collection("sdis")
      .doc(claims.sdisId)
      .collection("stations")
      .doc(stationDoc.id)
      .collection("membership_requests")
      .doc(callerUid)
      .get();

    if (requestDoc.exists) {
      const requestData = requestDoc.data()!;
      const stationData = stationDoc.data();

      myRequests.push({
        stationId: stationDoc.id,
        stationName: stationData.name || stationDoc.id,
        status: requestData.status,
        requestedAt: requestData.requestedAt?.toDate?.()?.toISOString() || "",
      });
    }
  }

  return {requests: myRequests};
});

/**
 * Récupère un utilisateur spécifique par authUid dans une station
 * avec déchiffrement des PII
 */
export const getUserByAuthUidForStation = onCall(
  {secrets: [encryptionKey]},
  async (request) => {
    // Vérifier l'authentification
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise");
    }

    const targetAuthUid = request.data?.authUid as string;
    const stationId = request.data?.stationId as string;
    const claims = request.auth.token as unknown as CustomClaims;

    if (!targetAuthUid || !stationId) {
      throw new HttpsError(
        "invalid-argument",
        "authUid et stationId requis"
      );
    }

    if (!claims.sdisId) {
      throw new HttpsError(
        "failed-precondition",
        "Utilisateur sans SDIS assigné"
      );
    }

    // Vérifier que l'utilisateur a accès à cette station
    if (!claims.stations?.[stationId]) {
      throw new HttpsError(
        "permission-denied",
        "Vous n'avez pas accès à cette caserne"
      );
    }

    const db = getFirestore();
    const key = encryptionKey.value();

    try {
      // Chercher l'utilisateur dans la station par authUid
      const usersSnapshot = await db
        .collection("sdis")
        .doc(claims.sdisId)
        .collection("stations")
        .doc(stationId)
        .collection("users")
        .where("authUid", "==", targetAuthUid)
        .limit(1)
        .get();

      if (usersSnapshot.empty) {
        throw new HttpsError(
          "not-found",
          "Utilisateur non trouvé dans cette station"
        );
      }

      const userDoc = usersSnapshot.docs[0];
      const userData = userDoc.data();

      // Déchiffrer les PII
      const decrypted = decryptPII({
        firstName_encrypted: userData.firstName_encrypted,
        lastName_encrypted: userData.lastName_encrypted,
        email_encrypted: userData.email_encrypted,
        
      }, key);

      const user: StationUser = {
        id: userDoc.id,
        authUid: userData.authUid || "",
        email: decrypted.email,
        matricule: userData.matricule || userDoc.id,
        firstName: decrypted.firstName || "",
        lastName: decrypted.lastName || "",
        station: userData.station || stationId,
        status: userData.status || "agent",
        admin: userData.admin || false,
        team: userData.team || "",
        skills: userData.skills || [],
        keySkills: userData.keySkills || [],
        personalAlertEnabled: userData.personalAlertEnabled ?? true,
        chiefAlertEnabled: userData.chiefAlertEnabled ?? false,
        anomalyAlertEnabled: userData.anomalyAlertEnabled ?? false,
        positionId: userData.positionId,
      };

      return {user};
    } catch (error) {
      console.error("❌ Error loading user by authUid:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        "Erreur lors du chargement de l'utilisateur"
      );
    }
  }
);

/**
 * Trouve l'email associé à un matricule dans un SDIS
 * Permet la connexion par matricule en récupérant l'email réel
 */
export const getEmailByMatricule = onCall(
  {secrets: [encryptionKey]},
  async (request) => {
    const matricule = request.data?.matricule as string;
    const sdisId = request.data?.sdisId as string;

    if (!matricule || !sdisId) {
      throw new HttpsError(
        "invalid-argument",
        "matricule et sdisId requis"
      );
    }

    const db = getFirestore();
    const key = encryptionKey.value();

    try {
      console.log(`🔍 Searching for matricule ${matricule} in SDIS ${sdisId}`);

      // Chercher dans la collection globale des utilisateurs
      // Le matricule est stocké en clair pour faciliter la recherche
      const usersSnapshot = await db
        .collection("sdis")
        .doc(sdisId)
        .collection("users")
        .where("matricule", "==", matricule)
        .limit(1)
        .get();

      if (usersSnapshot.empty) {
        console.log(`❌ Matricule not found: ${matricule}`);
        throw new HttpsError(
          "not-found",
          "Matricule non trouvé"
        );
      }

      const userDoc = usersSnapshot.docs[0];
      const userData = userDoc.data();

      // Déchiffrer l'email
      const decrypted = decryptPII({
        email_encrypted: userData.email_encrypted,
      }, key);

      console.log(`✅ Email found for matricule ${matricule}`);

      return {
        email: decrypted.email,
      };
    } catch (error) {
      console.error("❌ Error finding email:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        "Erreur lors de la recherche du matricule"
      );
    }
  }
);

/**
 * Récupère tous les utilisateurs d'une station (avec déchiffrement)
 * Retourne une liste d'utilisateurs avec leurs données déchiffrées
 */
export const getUsersByStation = onCall(
  {secrets: [encryptionKey]},
  async (request) => {
    // Vérifier l'authentification
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise");
    }

    const stationId = request.data?.stationId as string;
    const claims = request.auth.token as unknown as CustomClaims;

    if (!stationId) {
      throw new HttpsError(
        "invalid-argument",
        "stationId requis"
      );
    }

    if (!claims.sdisId) {
      throw new HttpsError(
        "failed-precondition",
        "Utilisateur sans SDIS assigné"
      );
    }

    // Vérifier que l'utilisateur a accès à cette station
    if (!claims.stations?.[stationId]) {
      throw new HttpsError(
        "permission-denied",
        "Vous n'avez pas accès à cette caserne"
      );
    }

    const db = getFirestore();
    const key = encryptionKey.value();

    try {
      // Récupérer tous les utilisateurs de la station
      const usersSnapshot = await db
        .collection("sdis")
        .doc(claims.sdisId)
        .collection("stations")
        .doc(stationId)
        .collection("users")
        .get();

      const users: StationUser[] = [];

      for (const doc of usersSnapshot.docs) {
        const userData = doc.data();

        // Déchiffrer les PII
        const decrypted = decryptPII({
          firstName_encrypted: userData.firstName_encrypted,
          lastName_encrypted: userData.lastName_encrypted,
          email_encrypted: userData.email_encrypted,
        }, key);

        users.push({
          id: doc.id,
          authUid: userData.authUid || "",
          email: decrypted.email,
          matricule: userData.matricule || doc.id, // Le matricule est en clair
          firstName: decrypted.firstName || "",
          lastName: decrypted.lastName || "",
          station: userData.station || stationId,
          status: userData.status || "agent",
          admin: userData.admin || false,
          team: userData.team || "",
          skills: userData.skills || [],
          keySkills: userData.keySkills || [],
          personalAlertEnabled: userData.personalAlertEnabled ?? true,
          chiefAlertEnabled: userData.chiefAlertEnabled ?? false,
          anomalyAlertEnabled: userData.anomalyAlertEnabled ?? false,
          positionId: userData.positionId,
          agentAvailabilityStatus: userData.agentAvailabilityStatus || "active",
          suspensionStartDate: userData.suspensionStartDate
            ? (typeof userData.suspensionStartDate === "string"
                ? userData.suspensionStartDate
                : (userData.suspensionStartDate as {toDate: () => Date}).toDate().toISOString())
            : undefined,
        });
      }

      console.log(`✅ Retrieved ${users.length} users from station ${stationId}`);
      return {users};
    } catch (error) {
      console.error("❌ Error loading users by station:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        "Erreur lors du chargement des utilisateurs"
      );
    }
  }
);
