package com.nordlab.hub.workspaces;

import com.nordlab.hub.users.UserAccount;
import com.nordlab.hub.users.UserRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Locale;
import java.util.UUID;

@Service
public class WorkspaceService {
    private final WorkspaceRepository workspaces;
    private final WorkspaceMembershipRepository memberships;
    private final UserRepository users;

    public WorkspaceService(
            WorkspaceRepository workspaces,
            WorkspaceMembershipRepository memberships,
            UserRepository users
    ) {
        this.workspaces = workspaces;
        this.memberships = memberships;
        this.users = users;
    }

    @Transactional
    public WorkspaceResponse create(UUID actorId, CreateWorkspaceRequest request) {
        Workspace workspace = workspaces.save(new Workspace(
                request.name().strip(),
                request.description() == null ? null : request.description().strip(),
                actorId
        ));
        memberships.save(new WorkspaceMembership(workspace.getId(), actorId, WorkspaceRole.OWNER));
        return WorkspaceResponse.from(workspace);
    }

    @Transactional(readOnly = true)
    public List<WorkspaceResponse> list(UUID actorId) {
        return workspaces.findAccessibleByUserId(actorId)
                .stream()
                .map(WorkspaceResponse::from)
                .toList();
    }

    @Transactional(readOnly = true)
    public WorkspaceResponse get(UUID actorId, UUID workspaceId) {
        return WorkspaceResponse.from(requireMemberWorkspace(actorId, workspaceId));
    }

    @Transactional
    public WorkspaceResponse update(UUID actorId, UUID workspaceId, UpdateWorkspaceRequest request) {
        Workspace workspace = requireWorkspaceRole(actorId, workspaceId, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        workspace.update(request.name().strip(), request.description() == null ? null : request.description().strip());
        return WorkspaceResponse.from(workspace);
    }

    @Transactional(readOnly = true)
    public List<WorkspaceMemberResponse> members(UUID actorId, UUID workspaceId) {
        requireMemberWorkspace(actorId, workspaceId);
        return memberships.findByIdWorkspaceId(workspaceId).stream()
                .map(membership -> users.findById(membership.getId().getUserId())
                        .map(user -> memberResponse(user, membership))
                        .orElseThrow(() -> new IllegalStateException("Workspace membership refers to a missing user.")))
                .toList();
    }

    @Transactional
    public WorkspaceMemberResponse addMember(UUID actorId, UUID workspaceId, AddWorkspaceMemberRequest request) {
        requireWorkspaceRole(actorId, workspaceId, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        String email = request.email().strip().toLowerCase(Locale.ROOT);
        UserAccount user = users.findByEmail(email)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No user has this email address."));
        if (request.role() == WorkspaceRole.OWNER) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Ownership cannot be assigned through member management.");
        }
        WorkspaceMembershipId id = new WorkspaceMembershipId(workspaceId, user.getId());
        if (memberships.existsById(id)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "The user is already a workspace member.");
        }
        return memberResponse(user, memberships.save(new WorkspaceMembership(workspaceId, user.getId(), request.role())));
    }

    @Transactional
    public void removeMember(UUID actorId, UUID workspaceId, UUID userId) {
        requireWorkspaceRole(actorId, workspaceId, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        Workspace workspace = workspaces.findById(workspaceId)
                .orElseThrow(() -> notFound());
        if (workspace.getOwnerId().equals(userId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "The workspace owner cannot be removed.");
        }
        WorkspaceMembership membership = memberships.findByIdWorkspaceIdAndIdUserId(workspaceId, userId)
                .orElseThrow(() -> notFound());
        WorkspaceMembership actorMembership = memberships.findByIdWorkspaceIdAndIdUserId(workspaceId, actorId)
                .orElseThrow(WorkspaceService::notFound);
        if (actorMembership.getRole() == WorkspaceRole.ADMIN
                && (membership.getRole() == WorkspaceRole.ADMIN || membership.getRole() == WorkspaceRole.OWNER)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Workspace admins cannot remove owners or other admins.");
        }
        memberships.delete(membership);
    }

    private Workspace requireMemberWorkspace(UUID actorId, UUID workspaceId) {
        return workspaces.findAccessibleByIdAndUserId(workspaceId, actorId)
                .orElseThrow(WorkspaceService::notFound);
    }

    private Workspace requireWorkspaceRole(UUID actorId, UUID workspaceId, WorkspaceRole... allowedRoles) {
        WorkspaceMembership membership = memberships.findByIdWorkspaceIdAndIdUserId(workspaceId, actorId)
                .orElseThrow(WorkspaceService::notFound);
        for (WorkspaceRole allowedRole : allowedRoles) {
            if (membership.getRole() == allowedRole) {
                return workspaces.findById(workspaceId).orElseThrow(WorkspaceService::notFound);
            }
        }
        throw new ResponseStatusException(HttpStatus.FORBIDDEN, "You do not have permission to manage this workspace.");
    }

    private WorkspaceMemberResponse memberResponse(UserAccount user, WorkspaceMembership membership) {
        return new WorkspaceMemberResponse(user.getId(), user.getEmail(), user.getDisplayName(), membership.getRole());
    }

    private static ResponseStatusException notFound() {
        return new ResponseStatusException(HttpStatus.NOT_FOUND, "Workspace or member not found.");
    }
}
