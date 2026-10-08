package com.nordlab.hub.workspaces;

import java.util.UUID;

public record WorkspaceMemberResponse(UUID userId, String email, String displayName, WorkspaceRole role) {
}
