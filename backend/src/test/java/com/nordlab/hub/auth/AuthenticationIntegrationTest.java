package com.nordlab.hub.auth;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.MockMvc;
import com.nordlab.hub.users.UserRepository;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Testcontainers(disabledWithoutDocker = true)
class AuthenticationIntegrationTest {
    private static final String SETUP_TOKEN = "test-only-bootstrap-token-not-for-production";
    private static final String ADMIN_EMAIL = "owner@example.test";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("nordhub.auth.bootstrap-token", () -> SETUP_TOKEN);
        registry.add("nordhub.auth.bootstrap-email", () -> ADMIN_EMAIL);
    }

    @Autowired
    private MockMvc mvc;

    @Autowired
    private UserRepository users;

    @Test
    void bootstrapIsOneTimeAndSessionsAuthenticateTheCurrentUser() throws Exception {
        MvcResult bootstrap = mvc.perform(post("/api/v1/auth/bootstrap")
                        .header("X-Setup-Token", SETUP_TOKEN)
                        .with(csrf().asHeader())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"owner@example.test","displayName":"Workspace owner","password":"secure-password-123"}
                                """))
                .andExpect(status().isCreated())
                .andReturn();

        assertThat(bootstrap.getResponse().getContentAsString())
                .contains("\"email\":\"owner@example.test\"")
                .doesNotContain("password");

        mvc.perform(post("/api/v1/auth/bootstrap")
                        .header("X-Setup-Token", SETUP_TOKEN)
                        .with(csrf().asHeader())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"owner@example.test","displayName":"Workspace owner","password":"secure-password-123"}
                                """))
                .andExpect(status().isConflict());

        mvc.perform(post("/api/v1/auth/register")
                        .with(csrf().asHeader())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"member@example.test","displayName":"Workspace member","password":"secure-password-456"}
                                """))
                .andExpect(status().isCreated());

        for (int attempt = 0; attempt < 4; attempt++) {
            mvc.perform(post("/api/v1/auth/login")
                            .with(csrf().asHeader())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {"email":"owner@example.test","password":"incorrect-password"}
                                    """))
                    .andExpect(status().isUnauthorized());
        }
        assertThat(users.findByEmail(ADMIN_EMAIL).orElseThrow().getFailedLoginAttempts()).isEqualTo(4);

        MvcResult login = mvc.perform(post("/api/v1/auth/login")
                        .with(csrf().asHeader())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"owner@example.test","password":"secure-password-123"}
                                """))
                .andExpect(status().isOk())
                .andReturn();
        assertThat(users.findByEmail(ADMIN_EMAIL).orElseThrow().getFailedLoginAttempts()).isZero();

        MockHttpSession session = (MockHttpSession) login.getRequest().getSession(false);
        assertThat(session).isNotNull();
        mvc.perform(get("/api/v1/auth/me").session(session))
                .andExpect(status().isOk())
                .andExpect(result -> assertThat(result.getResponse().getContentAsString())
                        .contains("\"email\":\"owner@example.test\""));
    }
}
