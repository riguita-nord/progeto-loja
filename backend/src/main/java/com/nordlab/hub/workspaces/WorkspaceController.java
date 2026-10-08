package com.nordlab.hub.workspaces;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/workspaces")
public class WorkspaceController {
    private final WorkspaceService workspaces;

    public WorkspaceController(WorkspaceService workspaces) {
        this.workspaces = workspaces;
    }

    @GetMapping
    public List<WorkspaceResponse> list(@AuthenticationPrincipal UserDetails principal) {
        return workspaces.list(userId(principal));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public WorkspaceResponse create(
            @AuthenticationPrincipal UserDetails principal,
            @Valid @RequestBody CreateWorkspaceRequest request
    ) {
        return workspaces.create(userId(principal), request);
    }

    @GetMapping("/{workspaceId}")
    public WorkspaceResponse get(
            @AuthenticationPrincipal UserDetails principal,
            @PathVariable UUID workspaceId
    ) {
        return workspaces.get(userId(principal), workspaceId);
    }

    @PutMapping("/{workspaceId}")
    public WorkspaceResponse update(
            @AuthenticationPrincipal UserDetails principal,
            @PathVariable UUID workspaceId,
            @Valid @RequestBody UpdateWorkspaceRequest request
    ) {
        return workspaces.update(userId(principal), workspaceId, request);
    }

    @GetMapping("/{workspaceId}/members")
    public List<WorkspaceMemberResponse> members(
            @AuthenticationPrincipal UserDetails principal,
            @PathVariable UUID workspaceId
    ) {
        return workspaces.members(userId(principal), workspaceId);
    }

    @PostMapping("/{workspaceId}/members")
    @ResponseStatus(HttpStatus.CREATED)
    public WorkspaceMemberResponse addMember(
            @AuthenticationPrincipal UserDetails principal,
            @PathVariable UUID workspaceId,
            @Valid @RequestBody AddWorkspaceMemberRequest request
    ) {
        return workspaces.addMember(userId(principal), workspaceId, request);
    }

    @DeleteMapping("/{workspaceId}/members/{userId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void removeMember(
            @AuthenticationPrincipal UserDetails principal,
            @PathVariable UUID workspaceId,
            @PathVariable UUID userId
    ) {
        workspaces.removeMember(userId(principal), workspaceId, userId);
    }

    private UUID userId(UserDetails principal) {
        return UUID.fromString(principal.getUsername());
    }
}
