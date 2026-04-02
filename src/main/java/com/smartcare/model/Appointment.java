package com.smartcare.model;

import java.sql.Date;
import java.sql.Time;
import java.sql.Timestamp;

/** Appointment model */
public class Appointment {
    private int appointmentId;
    private int patientId;
    private int doctorId;
    private Date appointmentDate;
    private Time appointmentTime;
    private String appointmentType;
    private String status;
    private String reason;
    private String notes;
    private double consultationFee;
    private Timestamp createdAt;

    // Getters and setters
    public int getAppointmentId() { return appointmentId; }
    public void setAppointmentId(int v) { this.appointmentId = v; }
    public int getPatientId() { return patientId; }
    public void setPatientId(int v) { this.patientId = v; }
    public int getDoctorId() { return doctorId; }
    public void setDoctorId(int v) { this.doctorId = v; }
    public Date getAppointmentDate() { return appointmentDate; }
    public void setAppointmentDate(Date v) { this.appointmentDate = v; }
    public Time getAppointmentTime() { return appointmentTime; }
    public void setAppointmentTime(Time v) { this.appointmentTime = v; }
    public String getAppointmentType() { return appointmentType; }
    public void setAppointmentType(String v) { this.appointmentType = v; }
    public String getStatus() { return status; }
    public void setStatus(String v) { this.status = v; }
    public String getReason() { return reason; }
    public void setReason(String v) { this.reason = v; }
    public String getNotes() { return notes; }
    public void setNotes(String v) { this.notes = v; }
    public double getConsultationFee() { return consultationFee; }
    public void setConsultationFee(double v) { this.consultationFee = v; }
    public Timestamp getCreatedAt() { return createdAt; }
    public void setCreatedAt(Timestamp v) { this.createdAt = v; }
}
