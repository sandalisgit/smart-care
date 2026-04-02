package com.smartcare.model;

import java.sql.Date;
import java.sql.Timestamp;

public class Patient {
    private int patientId;
    private String patientCode;
    private String firstName;
    private String lastName;
    private Date dateOfBirth;
    private String gender;
    private String bloodGroup;
    private String phone;
    private String email;
    private String emergencyContactName;
    private String emergencyContactPhone;
    private String address;
    private String city;
    private String state;
    private String postalCode;
    private String country;
    private String nationalId;
    private String insuranceProvider;
    private String insurancePolicyNumber;
    private String allergies;           // stored encrypted
    private String chronicConditions;
    private String bloodPressure;
    private Double height;
    private Double weight;
    private Timestamp registrationDate;
    private String status;
    private String photoUrl;

    // Full name helper
    public String getFullName() {
        return firstName + " " + lastName;
    }

    // --- Getters and Setters ---
    public int getPatientId() { return patientId; }
    public void setPatientId(int patientId) { this.patientId = patientId; }
    public String getPatientCode() { return patientCode; }
    public void setPatientCode(String patientCode) { this.patientCode = patientCode; }
    public String getFirstName() { return firstName; }
    public void setFirstName(String firstName) { this.firstName = firstName; }
    public String getLastName() { return lastName; }
    public void setLastName(String lastName) { this.lastName = lastName; }
    public Date getDateOfBirth() { return dateOfBirth; }
    public void setDateOfBirth(Date dateOfBirth) { this.dateOfBirth = dateOfBirth; }
    public String getGender() { return gender; }
    public void setGender(String gender) { this.gender = gender; }
    public String getBloodGroup() { return bloodGroup; }
    public void setBloodGroup(String bloodGroup) { this.bloodGroup = bloodGroup; }
    public String getPhone() { return phone; }
    public void setPhone(String phone) { this.phone = phone; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getEmergencyContactName() { return emergencyContactName; }
    public void setEmergencyContactName(String s) { this.emergencyContactName = s; }
    public String getEmergencyContactPhone() { return emergencyContactPhone; }
    public void setEmergencyContactPhone(String s) { this.emergencyContactPhone = s; }
    public String getAddress() { return address; }
    public void setAddress(String address) { this.address = address; }
    public String getCity() { return city; }
    public void setCity(String city) { this.city = city; }
    public String getState() { return state; }
    public void setState(String state) { this.state = state; }
    public String getPostalCode() { return postalCode; }
    public void setPostalCode(String postalCode) { this.postalCode = postalCode; }
    public String getCountry() { return country; }
    public void setCountry(String country) { this.country = country; }
    public String getNationalId() { return nationalId; }
    public void setNationalId(String nationalId) { this.nationalId = nationalId; }
    public String getInsuranceProvider() { return insuranceProvider; }
    public void setInsuranceProvider(String s) { this.insuranceProvider = s; }
    public String getInsurancePolicyNumber() { return insurancePolicyNumber; }
    public void setInsurancePolicyNumber(String s) { this.insurancePolicyNumber = s; }
    public String getAllergies() { return allergies; }
    public void setAllergies(String allergies) { this.allergies = allergies; }
    public String getChronicConditions() { return chronicConditions; }
    public void setChronicConditions(String s) { this.chronicConditions = s; }
    public Timestamp getRegistrationDate() { return registrationDate; }
    public void setRegistrationDate(Timestamp t) { this.registrationDate = t; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public Double getHeight() { return height; }
    public void setHeight(Double height) { this.height = height; }
    public Double getWeight() { return weight; }
    public void setWeight(Double weight) { this.weight = weight; }
    public String getPhotoUrl() { return photoUrl; }
    public void setPhotoUrl(String photoUrl) { this.photoUrl = photoUrl; }
}
