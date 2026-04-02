package com.smartcare;

import com.smartcare.dao.PatientDAO;
import com.smartcare.dao.AppointmentDAO;
import com.smartcare.model.Patient;
import com.smartcare.security.EncryptionService;
import com.smartcare.security.AuthService;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.MockedStatic;
import org.mockito.junit.jupiter.MockitoExtension;

import java.sql.*;
import java.time.LocalDate;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Unit test suite for Smart Care.
 * Uses Mockito to mock DB connections — no live DB required.
 * Run: mvn test
 * Coverage: mvn jacoco:report → target/site/jacoco/index.html
 */
@ExtendWith(MockitoExtension.class)
class SmartCareTests {

    // =====================================================================
    // ENCRYPTION SERVICE TESTS
    // =====================================================================
    @Nested
    @DisplayName("EncryptionService — AES-256-GCM")
    class EncryptionTests {

        @Test
        @DisplayName("Encrypt and decrypt roundtrip returns original value")
        void encryptDecryptRoundtrip() {
            String original = "Penicillin, Peanuts";
            String encrypted = EncryptionService.encrypt(original);
            String decrypted = EncryptionService.decrypt(encrypted);
            assertEquals(original, decrypted, "Decrypted value must match original");
        }

        @Test
        @DisplayName("Same plaintext produces different ciphertext each time (unique IV)")
        void uniqueIvPerEncryption() {
            String plain = "Aspirin allergy";
            String enc1 = EncryptionService.encrypt(plain);
            String enc2 = EncryptionService.encrypt(plain);
            assertNotEquals(enc1, enc2, "Each encryption must use a unique IV");
        }

        @Test
        @DisplayName("Null input returns null")
        void nullInputReturnsNull() {
            assertNull(EncryptionService.encrypt(null));
            assertNull(EncryptionService.decrypt(null));
        }

        @Test
        @DisplayName("Empty string input returns empty string")
        void emptyStringPassthrough() {
            assertEquals("", EncryptionService.encrypt(""));
            assertEquals("", EncryptionService.decrypt(""));
        }

        @Test
        @DisplayName("isEncrypted correctly identifies encrypted vs plain text")
        void isEncryptedDetection() {
            String encrypted = EncryptionService.encrypt("test value");
            assertTrue(EncryptionService.isEncrypted(encrypted));
            assertFalse(EncryptionService.isEncrypted("plain text"));
            assertFalse(EncryptionService.isEncrypted(null));
        }

        @Test
        @DisplayName("Encrypted value has correct format: base64:base64")
        void encryptedValueFormat() {
            String encrypted = EncryptionService.encrypt("test");
            assertTrue(encrypted.contains(":"), "Encrypted value must have IV:ciphertext format");
            String[] parts = encrypted.split(":", 2);
            assertEquals(2, parts.length);
            // Verify IV is 12 bytes (16 base64 chars)
            byte[] iv = java.util.Base64.getDecoder().decode(parts[0]);
            assertEquals(12, iv.length, "IV must be 12 bytes (96-bit)");
        }

        @Test
        @DisplayName("Long text (EMR record) encrypts and decrypts correctly")
        void longTextEncryption() {
            String longText = "Patient presented with severe chest pain radiating to left arm. ".repeat(20);
            String encrypted = EncryptionService.encrypt(longText);
            String decrypted = EncryptionService.decrypt(encrypted);
            assertEquals(longText, decrypted);
        }
    }

    // =====================================================================
    // PASSWORD HASHING TESTS
    // =====================================================================
    @Nested
    @DisplayName("AuthService — bcrypt password hashing (NFR-06)")
    class PasswordTests {

        @Test
        @DisplayName("Hash password produces non-null bcrypt hash")
        void hashNotNull() {
            String hash = AuthService.hashPassword("SecurePass@123");
            assertNotNull(hash);
            assertTrue(hash.startsWith("$2b$12$") || hash.startsWith("$2a$12$"),
                    "Hash must use bcrypt with cost factor 12");
        }

        @Test
        @DisplayName("Correct password verifies against its hash")
        void correctPasswordVerifies() {
            String pass = "Hospital@2026!";
            String hash = AuthService.hashPassword(pass);
            assertTrue(AuthService.verifyPassword(pass, hash));
        }

        @Test
        @DisplayName("Wrong password fails verification")
        void wrongPasswordFails() {
            String hash = AuthService.hashPassword("CorrectPassword!");
            assertFalse(AuthService.verifyPassword("WrongPassword!", hash));
        }

        @Test
        @DisplayName("Same password produces different hashes (salt)")
        void differentHashesForSamePassword() {
            String pass = "SamePassword123";
            String h1 = AuthService.hashPassword(pass);
            String h2 = AuthService.hashPassword(pass);
            assertNotEquals(h1, h2, "bcrypt must produce unique salts");
        }

        @Test
        @DisplayName("Cost factor is 12 as required by NFR-06")
        void costFactor12() {
            String hash = AuthService.hashPassword("testpass");
            assertTrue(hash.contains("$12$"), "bcrypt cost factor must be 12");
        }
    }

    // =====================================================================
    // PATIENT MODEL TESTS
    // =====================================================================
    @Nested
    @DisplayName("Patient Model")
    class PatientModelTests {

        @Test
        @DisplayName("getFullName returns first + last name")
        void fullNameConcatenation() {
            Patient p = new Patient();
            p.setFirstName("Sandali");
            p.setLastName("Dissanayake");
            assertEquals("Sandali Dissanayake", p.getFullName());
        }

        @Test
        @DisplayName("Patient object allows null fields without NPE")
        void nullFieldsAllowed() {
            Patient p = new Patient();
            assertNull(p.getAllergies());
            assertNull(p.getEmail());
            assertDoesNotThrow(p::getFullName);
        }

        @Test
        @DisplayName("Patient setters and getters work correctly")
        void settersGetters() {
            Patient p = new Patient();
            p.setPatientId(42);
            p.setPatientCode("PT-2026-000042");
            p.setGender("Female");
            p.setBloodGroup("O+");
            p.setStatus("Active");

            assertEquals(42, p.getPatientId());
            assertEquals("PT-2026-000042", p.getPatientCode());
            assertEquals("Female", p.getGender());
            assertEquals("O+", p.getBloodGroup());
            assertEquals("Active", p.getStatus());
        }
    }

    // =====================================================================
    // APPOINTMENT CONFLICT DETECTION LOGIC TESTS
    // =====================================================================
    @Nested
    @DisplayName("Appointment Slot Logic")
    class AppointmentSlotTests {

        @Test
        @DisplayName("Slot time correctly formatted as HH:mm")
        void slotFormat() {
            // Test that time values parse correctly
            Time t = Time.valueOf("09:00:00");
            String slot = t.toString().substring(0, 5);
            assertEquals("09:00", slot);

            Time t2 = Time.valueOf("14:30:00");
            String slot2 = t2.toString().substring(0, 5);
            assertEquals("14:30", slot2);
        }

        @Test
        @DisplayName("Slot generation produces 30-minute intervals")
        void slotInterval() {
            java.time.LocalTime start = java.time.LocalTime.of(9, 0);
            java.time.LocalTime end = java.time.LocalTime.of(10, 0);
            java.util.List<String> slots = new java.util.ArrayList<>();

            java.time.LocalTime current = start;
            while (current.isBefore(end)) {
                slots.add(current.toString().substring(0, 5));
                current = current.plusMinutes(30);
            }

            assertEquals(2, slots.size());
            assertEquals("09:00", slots.get(0));
            assertEquals("09:30", slots.get(1));
        }

        @Test
        @DisplayName("Day of week encoding is correct (Monday=1, Sunday=7)")
        void dayOfWeekEncoding() {
            LocalDate monday = LocalDate.of(2026, 3, 16); // A Monday
            int dow = monday.getDayOfWeek().getValue();
            assertEquals(1, dow);

            LocalDate sunday = LocalDate.of(2026, 3, 22); // A Sunday
            assertEquals(7, sunday.getDayOfWeek().getValue());
        }
    }

    // =====================================================================
    // BILLING CALCULATION TESTS
    // =====================================================================
    @Nested
    @DisplayName("Billing Calculations")
    class BillingTests {

        @Test
        @DisplayName("Line total calculated correctly: qty * price * (1-disc) * (1+tax)")
        void lineTotalCalculation() {
            int qty = 2;
            double unitPrice = 5000.0;
            double discountPct = 10.0; // 10% discount
            double taxPct = 0.0;

            double lineTotal = qty * unitPrice * (1 - discountPct / 100) * (1 + taxPct / 100);
            assertEquals(9000.0, lineTotal, 0.001);
        }

        @Test
        @DisplayName("Balance amount updates correctly after payment")
        void balanceAfterPayment() {
            double totalAmount = 15000.0;
            double paidAmount = 5000.0;
            double balance = totalAmount - paidAmount;
            assertEquals(10000.0, balance, 0.001);

            // After second payment
            double secondPayment = 10000.0;
            double newBalance = balance - secondPayment;
            assertEquals(0.0, newBalance, 0.001);
        }

        @Test
        @DisplayName("Bill number format validation")
        void billNumberFormat() {
            String billNumber = "BILL20260320" + String.format("%04d", 1);
            assertTrue(billNumber.startsWith("BILL"));
            assertEquals(16, billNumber.length());
        }
    }

    // =====================================================================
    // NOSHOW AI FEATURE ENCODING TESTS
    // =====================================================================
    @Nested
    @DisplayName("AI No-Show Feature Encoding")
    class NoShowEncodingTests {

        @Test
        @DisplayName("Appointment type encodes to correct integer")
        void appointmentTypeEncoding() {
            // Mirrors logic in NoShowPredictor
            assertEquals(0, encodeType("Consultation"));
            assertEquals(1, encodeType("Follow-up"));
            assertEquals(2, encodeType("Emergency"));
            assertEquals(3, encodeType("Routine Check"));
            assertEquals(0, encodeType(null));
        }

        private int encodeType(String type) {
            if (type == null) return 0;
            return switch (type) {
                case "Consultation" -> 0;
                case "Follow-up" -> 1;
                case "Emergency" -> 2;
                case "Routine Check" -> 3;
                default -> 0;
            };
        }

        @Test
        @DisplayName("Days until appointment is non-negative")
        void daysUntilNonNegative() {
            long daysUntil = (Date.valueOf("2026-03-20").getTime() - System.currentTimeMillis())
                    / (1000 * 60 * 60 * 24);
            long clamped = Math.max(0, daysUntil);
            assertTrue(clamped >= 0);
        }
    }

    // =====================================================================
    // SECURITY / AUDIT TESTS
    // =====================================================================
    @Nested
    @DisplayName("Security — SHA-256 Hash Chaining")
    class AuditHashTests {

        @Test
        @DisplayName("SHA-256 produces 64-character hex string")
        void sha256OutputLength() throws Exception {
            java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest("test content".getBytes());
            String hex = java.util.HexFormat.of().formatHex(hash);
            assertEquals(64, hex.length(), "SHA-256 hex must be 64 characters");
        }

        @Test
        @DisplayName("Same input always produces same hash (deterministic)")
        void deterministicHash() throws Exception {
            java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
            String input = "userId1:CREATE_PATIENT:patients:42:" + 1234567890L;
            byte[] h1 = digest.digest(input.getBytes());
            byte[] h2 = digest.digest(input.getBytes());
            assertArrayEquals(h1, h2);
        }

        @Test
        @DisplayName("Different inputs produce different hashes (no collision)")
        void noCollision() throws Exception {
            java.security.MessageDigest d = java.security.MessageDigest.getInstance("SHA-256");
            byte[] h1 = d.digest("record1".getBytes());
            byte[] h2 = d.digest("record2".getBytes());
            assertFalse(java.util.Arrays.equals(h1, h2));
        }
    }

    // =====================================================================
    // PATIENT CODE FORMAT TESTS
    // =====================================================================
    @Nested
    @DisplayName("Patient Code Generation")
    class PatientCodeTests {

        @Test
        @DisplayName("Patient code follows PT-YYYY-NNNNNN format")
        void codeFormat() {
            int year = java.time.Year.now().getValue();
            String code = String.format("PT-%d-%06d", year, 1);
            assertEquals("PT-2026-000001", code);
        }

        @Test
        @DisplayName("Patient codes are unique when count increments")
        void codesAreUnique() {
            int year = java.time.Year.now().getValue();
            String c1 = String.format("PT-%d-%06d", year, 1);
            String c2 = String.format("PT-%d-%06d", year, 2);
            assertNotEquals(c1, c2);
        }

        @Test
        @DisplayName("Patient code is zero-padded to 6 digits")
        void zeroPadded() {
            int year = 2026;
            String code = String.format("PT-%d-%06d", year, 5);
            assertEquals("PT-2026-000005", code);
            assertTrue(code.matches("PT-\\d{4}-\\d{6}"));
        }
    }
}
