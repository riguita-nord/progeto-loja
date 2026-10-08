package com.nordlab.hub.users;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "users")
public class UserAccount {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, unique = true, length = 320)
    private String email;

    @Column(nullable = false, length = 120)
    private String displayName;

    @Column(nullable = false, name = "password_hash", length = 100)
    private String passwordHash;

    @Column(nullable = false)
    private boolean enabled = true;

    @Column(nullable = false, name = "is_admin")
    private boolean admin;

    @Column(nullable = false, name = "failed_login_attempts")
    private int failedLoginAttempts;

    @Column(name = "locked_until")
    private Instant lockedUntil;

    @Column(nullable = false, name = "created_at", updatable = false)
    private Instant createdAt;

    @Column(nullable = false, name = "updated_at")
    private Instant updatedAt;

    protected UserAccount() {
    }

    public UserAccount(String email, String displayName, String passwordHash) {
        this(email, displayName, passwordHash, false);
    }

    public UserAccount(String email, String displayName, String passwordHash, boolean admin) {
        this.email = email;
        this.displayName = displayName;
        this.passwordHash = passwordHash;
        this.admin = admin;
    }

    @jakarta.persistence.PrePersist
    void onCreate() {
        Instant now = Instant.now();
        createdAt = now;
        updatedAt = now;
    }

    @jakarta.persistence.PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }

    public UUID getId() { return id; }
    public String getEmail() { return email; }
    public String getDisplayName() { return displayName; }
    public String getPasswordHash() { return passwordHash; }
    public boolean isEnabled() { return enabled; }
    public boolean isAdmin() { return admin; }
    public int getFailedLoginAttempts() { return failedLoginAttempts; }
    public Instant getLockedUntil() { return lockedUntil; }

    public void setPasswordHash(String passwordHash) { this.passwordHash = passwordHash; }
    public void recordFailedLogin(Instant lockedUntil) {
        failedLoginAttempts++;
        this.lockedUntil = lockedUntil;
    }
    public void resetFailedLogins() {
        failedLoginAttempts = 0;
        lockedUntil = null;
    }
}
