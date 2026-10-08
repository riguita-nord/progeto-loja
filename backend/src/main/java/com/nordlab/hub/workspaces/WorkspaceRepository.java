package com.nordlab.hub.workspaces;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface WorkspaceRepository extends JpaRepository<Workspace, UUID> {
    @Query("""
            select w from Workspace w
            where exists (
                select m.id.workspaceId from WorkspaceMembership m
                where m.id.workspaceId = w.id and m.id.userId = :userId
            )
            order by w.createdAt desc
            """)
    List<Workspace> findAccessibleByUserId(@Param("userId") UUID userId);

    @Query("""
            select w from Workspace w
            where w.id = :workspaceId and exists (
                select m.id.workspaceId from WorkspaceMembership m
                where m.id.workspaceId = w.id and m.id.userId = :userId
            )
            """)
    Optional<Workspace> findAccessibleByIdAndUserId(
            @Param("workspaceId") UUID workspaceId,
            @Param("userId") UUID userId
    );
}
