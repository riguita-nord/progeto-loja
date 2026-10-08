package com.nordlab.hub.workspaces;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public record AddWorkspaceMemberRequest(
        @Email @NotBlank @Size(max = 320) String email,
        @NotNull WorkspaceRole role
) {
}
