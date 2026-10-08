package com.nordlab.hub.workspaces;

import com.nordlab.hub.users.UserAccount;
import com.nordlab.hub.users.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Testcontainers(disabledWithoutDocker = true)
class WorkspaceIsolationIntegrationTest {
    @Container
    private static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Autowired
    private MockMvc mvc;

    @Autowired
    private UserRepository users;

    @Autowired
    private WorkspaceRepository workspaces;

    @Autowired
    private WorkspaceMembershipRepository memberships;

    @Autowired
    private PasswordEncoder passwordEncoder;

    private UUID memberId;
    private UUID outsiderId;
    private UUID workspaceId;

    @BeforeEach
    void createAccountsAndWorkspace() {
        String suffix = UUID.randomUUID().toString();
        UserAccount member = users.save(new UserAccount(
                "member-" + suffix + "@example.test", "Workspace member", passwordEncoder.encode("not-a-real-password")
        ));
        UserAccount outsider = users.save(new UserAccount(
                "outsider-" + suffix + "@example.test", "Workspace outsider", passwordEncoder.encode("not-a-real-password")
        ));
        Workspace workspace = workspaces.save(new Workspace("Private workspace", "Private description", member.getId()));
        memberships.save(new WorkspaceMembership(workspace.getId(), member.getId(), WorkspaceRole.OWNER));
        memberId = member.getId();
        outsiderId = outsider.getId();
        workspaceId = workspace.getId();
    }

    @Test
    void membersCanReadWorkspaceButOtherUsersCannot() throws Exception {
        mvc.perform(get("/api/v1/workspaces/{id}", workspaceId)
                        .with(user(memberId.toString()).roles("USER")))
                .andExpect(status().isOk());

        MvcResult result = mvc.perform(get("/api/v1/workspaces/{id}", workspaceId)
                        .with(user(outsiderId.toString()).roles("USER")))
                .andExpect(status().isNotFound())
                .andReturn();

        assertThat(result.getResponse().getContentAsString())
                .contains("\"code\":\"NOT_FOUND\"")
                .doesNotContain("Private description");
    }

    @Test
    void authenticatedUserCanCreateWorkspaceAndBecomesOwner() throws Exception {
        MvcResult result = mvc.perform(post("/api/v1/workspaces")
                        .with(user(outsiderId.toString()).roles("USER"))
                        .with(csrf().asHeader())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"New workspace","description":"Created by the current member"}
                                """))
                .andExpect(status().isCreated())
                .andReturn();

        assertThat(result.getResponse().getContentAsString())
                .contains("\"name\":\"New workspace\"")
                .contains("\"ownerId\":\"" + outsiderId + "\"");
    }
}
