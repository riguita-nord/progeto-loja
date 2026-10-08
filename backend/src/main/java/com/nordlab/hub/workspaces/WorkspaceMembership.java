package com.nordlab.hub.workspaces;

import jakarta.persistence.Column;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "workspace_memberships")
public class WorkspaceMembership {
    @EmbeddedId
    private WorkspaceMembershipId id;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private WorkspaceRole role;

    @Column(nullable = false, name = "joined_at", updatable = false)
    private Instant joinedAt;

    protected WorkspaceMembership() {
    }

    public WorkspaceMembership(UUID workspaceId, UUID userId, WorkspaceRole role) {
        id = new WorkspaceMembershipId(workspaceId, userId);
        this.role = role;
    }

    @jakarta.persistence.PrePersist
    void onCreate() {
        joinedAt = Instant.now();
    }

    public WorkspaceMembershipId getId() { return id; }
    public WorkspaceRole getRole() { return role; }
    public void setRole(WorkspaceRole role) { this.role = role; }
}
