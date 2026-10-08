package com.nordlab.hub.workspaces;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface WorkspaceMembershipRepository extends JpaRepository<WorkspaceMembership, WorkspaceMembershipId> {
    List<WorkspaceMembership> findByIdWorkspaceId(UUID workspaceId);
    Optional<WorkspaceMembership> findByIdWorkspaceIdAndIdUserId(UUID workspaceId, UUID userId);
}
