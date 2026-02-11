/**
 * Utilitaires de chiffrement/déchiffrement AES-256-GCM
 * pour la protection des données personnelles (RGPD)
 */

import * as crypto from "crypto";
import {defineSecret} from "firebase-functions/params";

// Définition du secret pour la clé de chiffrement
// La valeur doit être configurée dans Google Cloud Secret Manager
export const encryptionKey = defineSecret("NEXSHIFT_ENCRYPTION_KEY");

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12; // GCM recommande 12 bytes
const AUTH_TAG_LENGTH = 16;

/**
 * Chiffre une chaîne de caractères avec AES-256-GCM
 * @param plaintext - Texte en clair à chiffrer
 * @param key - Clé de chiffrement (32 bytes / 256 bits, encodée en hex ou base64)
 * @returns Chaîne chiffrée en base64 (format: iv:authTag:ciphertext)
 */
export function encrypt(plaintext: string, key: string): string {
  // Décoder la clé (supporte hex ou base64)
  const keyBuffer = Buffer.from(key, "hex").length === 32
    ? Buffer.from(key, "hex")
    : Buffer.from(key, "base64");

  if (keyBuffer.length !== 32) {
    throw new Error("La clé de chiffrement doit faire 256 bits (32 bytes)");
  }

  // Générer un IV aléatoire
  const iv = crypto.randomBytes(IV_LENGTH);

  // Créer le cipher
  const cipher = crypto.createCipheriv(ALGORITHM, keyBuffer, iv, {
    authTagLength: AUTH_TAG_LENGTH,
  });

  // Chiffrer
  const encrypted = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);

  // Récupérer le tag d'authentification
  const authTag = cipher.getAuthTag();

  // Combiner iv + authTag + ciphertext et encoder en base64
  const combined = Buffer.concat([iv, authTag, encrypted]);
  return combined.toString("base64");
}

/**
 * Déchiffre une chaîne chiffrée avec AES-256-GCM
 * @param encryptedData - Données chiffrées en base64 (format: iv:authTag:ciphertext)
 * @param key - Clé de chiffrement (32 bytes / 256 bits)
 * @returns Texte en clair
 */
export function decrypt(encryptedData: string, key: string): string {
  // Décoder la clé
  const keyBuffer = Buffer.from(key, "hex").length === 32
    ? Buffer.from(key, "hex")
    : Buffer.from(key, "base64");

  if (keyBuffer.length !== 32) {
    throw new Error("La clé de chiffrement doit faire 256 bits (32 bytes)");
  }

  // Décoder les données
  const combined = Buffer.from(encryptedData, "base64");

  // Extraire les composants
  const iv = combined.subarray(0, IV_LENGTH);
  const authTag = combined.subarray(IV_LENGTH, IV_LENGTH + AUTH_TAG_LENGTH);
  const encrypted = combined.subarray(IV_LENGTH + AUTH_TAG_LENGTH);

  // Créer le decipher
  const decipher = crypto.createDecipheriv(ALGORITHM, keyBuffer, iv, {
    authTagLength: AUTH_TAG_LENGTH,
  });
  decipher.setAuthTag(authTag);

  // Déchiffrer
  const decrypted = Buffer.concat([
    decipher.update(encrypted),
    decipher.final(),
  ]);

  return decrypted.toString("utf8");
}

/**
 * Interface pour les données personnelles (PII)
 * Note: Le matricule n'est PAS une donnée sensible et est stocké en clair
 */
export interface PIIFields {
  firstName?: string;
  lastName?: string;
  email?: string;
}

/**
 * Interface pour les données personnelles chiffrées
 */
export interface EncryptedPIIFields {
  firstName_encrypted?: string;
  lastName_encrypted?: string;
  email_encrypted?: string;
}

/**
 * Chiffre les champs PII d'un objet
 * @param pii - Objet contenant les champs PII en clair
 * @param key - Clé de chiffrement
 * @returns Objet avec les champs PII chiffrés
 */
export function encryptPII(pii: PIIFields, key: string): EncryptedPIIFields {
  const result: EncryptedPIIFields = {};

  if (pii.firstName) {
    result.firstName_encrypted = encrypt(pii.firstName, key);
  }
  if (pii.lastName) {
    result.lastName_encrypted = encrypt(pii.lastName, key);
  }
  if (pii.email) {
    result.email_encrypted = encrypt(pii.email, key);
  }

  return result;
}

/**
 * Déchiffre les champs PII d'un objet
 * @param encrypted - Objet contenant les champs PII chiffrés
 * @param key - Clé de chiffrement
 * @returns Objet avec les champs PII en clair
 */
export function decryptPII(
  encrypted: EncryptedPIIFields,
  key: string
): PIIFields {
  const result: PIIFields = {};

  if (encrypted.firstName_encrypted) {
    result.firstName = decrypt(encrypted.firstName_encrypted, key);
  }
  if (encrypted.lastName_encrypted) {
    result.lastName = decrypt(encrypted.lastName_encrypted, key);
  }
  if (encrypted.email_encrypted) {
    result.email = decrypt(encrypted.email_encrypted, key);
  }

  return result;
}

/**
 * Génère une nouvelle clé de chiffrement AES-256
 * À utiliser une seule fois pour initialiser le secret
 * @returns Clé en hexadécimal (64 caractères)
 */
export function generateEncryptionKey(): string {
  return crypto.randomBytes(32).toString("hex");
}
