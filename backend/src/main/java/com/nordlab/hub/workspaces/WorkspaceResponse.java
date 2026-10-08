package com.nordlab.hub.workspaces;

import java.util.UUID;

public record WorkspaceResponse(UUID id, String name, String description, UUID ownerId) {
    public static WorkspaceResponse from(Workspace workspace) {
        return new WorkspaceResponse(
                workspace.getId(),
                workspace.getName(),
                workspace.getDescription(),
                workspace.getOwnerId()
        );
    }
}
