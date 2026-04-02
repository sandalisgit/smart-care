package com.smartcare.security;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * AES-256-GCM encryption for sensitive data at rest.
 * FR-73: All patient PII, EMR data, prescriptions encrypted before DB storage.
 * NFR-09: DB field values unreadable without decryption key.
 *
 * Key stored in environment variable SMARTCARE_AES_KEY (base64-encoded 32 bytes).
 * Generate: openssl rand -base64 32
 *
 * Storage format: Base64(12-byte IV) + ":" + Base64(ciphertext+16-byte auth tag)
 * The IV is unique per encryption — same plaintext produces different ciphertext.
 */
public class EncryptionService {

    private static final String ALGORITHM = "AES/GCM/NoPadding";
    private static final int GCM_IV_LENGTH = 12;        // 96 bits — recommended for GCM
    private static final int GCM_TAG_LENGTH = 128;       // bits — authentication tag
    private static final SecureRandom SECURE_RANDOM = new SecureRandom();

    // Loaded once at startup from environment variable
    private static final byte[] KEY = loadKey();

    private static byte[] loadKey() {
        String keyEnv = System.getenv("SMARTCARE_AES_KEY");
        if (keyEnv == null || keyEnv.isEmpty()) {
            // Dev fallback — NEVER use in production
            // In production: fail fast if key not set
            System.err.println("[WARNING] SMARTCARE_AES_KEY not set. Using insecure dev key.");
            keyEnv = "jP/tm/aF9JY2BRk5O+m9MR2tCtp/RDV8uajsJxBEFjs="; // dev only — exactly 32 bytes
        }
        byte[] decoded = Base64.getDecoder().decode(keyEnv);
        if (decoded.length != 32) {
            throw new IllegalStateException("AES key must be exactly 32 bytes (256 bits). Got: " + decoded.length);
        }
        return decoded;
    }

    /**
     * Encrypt plaintext. Returns null if input is null (allows optional fields).
     */
    public static String encrypt(String plaintext) {
        if (plaintext == null || plaintext.isEmpty()) return plaintext;
        try {
            // Generate unique 96-bit IV for each encryption
            byte[] iv = new byte[GCM_IV_LENGTH];
            SECURE_RANDOM.nextBytes(iv);

            SecretKeySpec secretKey = new SecretKeySpec(KEY, "AES");
            GCMParameterSpec paramSpec = new GCMParameterSpec(GCM_TAG_LENGTH, iv);

            Cipher cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(Cipher.ENCRYPT_MODE, secretKey, paramSpec);

            byte[] ciphertext = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));

            // Format: Base64(IV) : Base64(ciphertext+auth_tag)
            return Base64.getEncoder().encodeToString(iv) + ":" + Base64.getEncoder().encodeToString(ciphertext);

        } catch (Exception e) {
            throw new RuntimeException("Encryption failed", e);
        }
    }

    /**
     * Decrypt ciphertext. Returns null if input is null.
     */
    public static String decrypt(String ciphertext) {
        if (ciphertext == null || ciphertext.isEmpty()) return ciphertext;
        try {
            String[] parts = ciphertext.split(":", 2);
            if (parts.length != 2) {
                // Not encrypted (legacy or plain text field) — return as-is
                return ciphertext;
            }

            byte[] iv = Base64.getDecoder().decode(parts[0]);
            byte[] encryptedData = Base64.getDecoder().decode(parts[1]);

            SecretKeySpec secretKey = new SecretKeySpec(KEY, "AES");
            GCMParameterSpec paramSpec = new GCMParameterSpec(GCM_TAG_LENGTH, iv);

            Cipher cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(Cipher.DECRYPT_MODE, secretKey, paramSpec);

            byte[] decryptedData = cipher.doFinal(encryptedData);
            return new String(decryptedData, StandardCharsets.UTF_8);

        } catch (Exception e) {
            throw new RuntimeException("Decryption failed — data may be corrupted or wrong key", e);
        }
    }

    /**
     * Check if a string looks like it's already encrypted by this service.
     */
    public static boolean isEncrypted(String value) {
        if (value == null) return false;
        String[] parts = value.split(":", 2);
        if (parts.length != 2) return false;
        try {
            byte[] iv = Base64.getDecoder().decode(parts[0]);
            return iv.length == GCM_IV_LENGTH;
        } catch (Exception e) {
            return false;
        }
    }
}
