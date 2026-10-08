package com.nordlab.hub.workspaces;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;

import java.io.Serializable;
import java.util.UUID;

@Embeddable
public class WorkspaceMembershipId implements Serializable {
    @Column(name = "workspace_id")
    private UUID workspaceId;

    @Column(name = "user_id")
    private UUID userId;

    protected WorkspaceMembershipId() {
    }

    public WorkspaceMembershipId(UUID workspaceId, UUID userId) {
        this.workspaceId = workspaceId;
        this.userId = userId;
    }

    public UUID getWorkspaceId() { return workspaceId; }
    public UUID getUserId() { return userId; }

    @Override
    public boolean equals(Object other) {
        if (this == other) return true;
        if (!(other instanceof WorkspaceMembershipId that)) return false;
        return workspaceId.equals(that.workspaceId) && userId.equals(that.userId);
    }

    @Override
    public int hashCode() {
        return 31 * workspaceId.hashCode() + userId.hashCode();
    }
}
