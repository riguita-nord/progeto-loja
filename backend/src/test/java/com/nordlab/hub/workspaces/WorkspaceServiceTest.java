package com.nordlab.hub.workspaces;

import com.nordlab.hub.users.UserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class WorkspaceServiceTest {
    @Mock
    private WorkspaceRepository workspaces;

    @Mock
    private WorkspaceMembershipRepository memberships;

    @Mock
    private UserRepository users;

    @InjectMocks
    private WorkspaceService service;

    @Test
    void hidesWorkspaceFromNonMembers() {
        UUID workspaceId = UUID.randomUUID();
        UUID outsiderId = UUID.randomUUID();
        when(workspaces.findAccessibleByIdAndUserId(workspaceId, outsiderId)).thenReturn(Optional.empty());

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> service.get(outsiderId, workspaceId)
        );

        assertEquals(404, exception.getStatusCode().value());
        verify(workspaces, never()).findById(workspaceId);
    }

    @Test
    void viewerCannotUpdateWorkspace() {
        UUID workspaceId = UUID.randomUUID();
        UUID viewerId = UUID.randomUUID();
        when(memberships.findByIdWorkspaceIdAndIdUserId(workspaceId, viewerId))
                .thenReturn(Optional.of(new WorkspaceMembership(workspaceId, viewerId, WorkspaceRole.VIEWER)));

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> service.update(viewerId, workspaceId, new UpdateWorkspaceRequest("Changed", "Description"))
        );

        assertEquals(403, exception.getStatusCode().value());
        verify(workspaces, never()).findById(workspaceId);
    }
}
