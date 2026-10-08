package com.nordlab.hub.auth;

import com.nordlab.hub.common.AppSetting;
import com.nordlab.hub.common.AppSettingRepository;
import com.nordlab.hub.users.UserAccount;
import com.nordlab.hub.users.UserRepository;
import com.nordlab.hub.users.UserResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.context.HttpSessionSecurityContextRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.Instant;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.UUID;

import static org.springframework.http.HttpStatus.CONFLICT;
import static org.springframework.http.HttpStatus.LOCKED;
import static org.springframework.http.HttpStatus.UNAUTHORIZED;

@Service
public class AuthenticationService {
    private static final int MAX_FAILED_ATTEMPTS = 5;
    private static final Duration LOCK_DURATION = Duration.ofMinutes(15);

    private final UserRepository users;
    private final AppSettingRepository settings;
    private final PasswordEncoder passwordEncoder;
    private final AuthenticationManager authenticationManager;
    private final String bootstrapToken;
    private final String bootstrapEmail;

    public AuthenticationService(
            UserRepository users,
            AppSettingRepository settings,
            PasswordEncoder passwordEncoder,
            AuthenticationManager authenticationManager,
            @Value("${nordhub.auth.bootstrap-token:}") String bootstrapToken,
            @Value("${nordhub.auth.bootstrap-email:}") String bootstrapEmail
    ) {
        this.users = users;
        this.settings = settings;
        this.passwordEncoder = passwordEncoder;
        this.authenticationManager = authenticationManager;
        this.bootstrapToken = bootstrapToken;
        this.bootstrapEmail = bootstrapEmail;
    }

    @Transactional
    public UserResponse register(RegisterRequest request) {
        if (!settings.existsById("initial_admin_created")) {
            throw new ResponseStatusException(CONFLICT, "Initial account setup must be completed before public registration is enabled.");
        }
        String email = normalizeEmail(request.email());
        if (users.existsByEmail(email)) {
            throw new ResponseStatusException(CONFLICT, "An account with this email already exists.");
        }
        UserAccount account = users.save(new UserAccount(
                email,
                request.displayName().strip(),
                passwordEncoder.encode(request.password())
        ));
        return UserResponse.from(account);
    }

    @Transactional
    public UserResponse bootstrap(BootstrapRequest request, String suppliedToken) {
        if (bootstrapToken.isBlank() || suppliedToken == null
                || !MessageDigest.isEqual(
                bootstrapToken.getBytes(StandardCharsets.UTF_8),
                suppliedToken.getBytes(StandardCharsets.UTF_8))) {
            throw new ResponseStatusException(UNAUTHORIZED, "The setup token is invalid or disabled.");
        }
        if (users.count() != 0 || settings.existsById("initial_admin_created")) {
            throw new ResponseStatusException(CONFLICT, "Initial account setup has already been completed.");
        }
        String email = normalizeEmail(request.email());
        if (!bootstrapEmail.isBlank() && !bootstrapEmail.equalsIgnoreCase(email)) {
            throw new ResponseStatusException(UNAUTHORIZED, "The email address does not match the configured initial administrator.");
        }
        settings.saveAndFlush(new AppSetting("initial_admin_created", "true"));
        UserAccount account = users.save(new UserAccount(
                email,
                request.displayName().strip(),
                passwordEncoder.encode(request.password()),
                true
        ));
        return UserResponse.from(account);
    }

    @Transactional(noRollbackFor = BadCredentialsException.class)
    public UserResponse login(LoginRequest request, HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        String email = normalizeEmail(request.email());
        UserAccount account = users.findByEmailForUpdate(email)
                .orElseThrow(() -> new BadCredentialsException("Invalid credentials."));
        if (account.getLockedUntil() != null && account.getLockedUntil().isAfter(Instant.now())) {
            throw new ResponseStatusException(LOCKED, "Sign-in is temporarily locked. Try again later.");
        }
        if (account.getLockedUntil() != null) {
            account.resetFailedLogins();
        }

        Authentication authentication;
        try {
            authentication = authenticationManager.authenticate(
                    UsernamePasswordAuthenticationToken.unauthenticated(email, request.password())
            );
        } catch (BadCredentialsException exception) {
            int nextAttempt = account.getFailedLoginAttempts() + 1;
            account.recordFailedLogin(nextAttempt >= MAX_FAILED_ATTEMPTS
                    ? Instant.now().plus(LOCK_DURATION)
                    : null);
            users.save(account);
            throw new BadCredentialsException("Invalid credentials.");
        }

        account.resetFailedLogins();
        users.save(account);
        httpRequest.getSession(true);
        httpRequest.changeSessionId();
        SecurityContext context = SecurityContextHolder.createEmptyContext();
        context.setAuthentication(authentication);
        SecurityContextHolder.setContext(context);
        new HttpSessionSecurityContextRepository().saveContext(context, httpRequest, httpResponse);
        return UserResponse.from(account);
    }

    public UserResponse currentUser(UUID userId) {
        return users.findById(userId)
                .map(UserResponse::from)
                .orElseThrow(() -> new ResponseStatusException(UNAUTHORIZED, "The authenticated account no longer exists."));
    }

    @Transactional
    public void changePassword(UUID userId, ChangePasswordRequest request) {
        UserAccount account = users.findById(userId)
                .orElseThrow(() -> new ResponseStatusException(UNAUTHORIZED, "The authenticated account no longer exists."));
        if (!passwordEncoder.matches(request.currentPassword(), account.getPasswordHash())) {
            throw new BadCredentialsException("The current password is incorrect.");
        }
        account.setPasswordHash(passwordEncoder.encode(request.newPassword()));
        account.resetFailedLogins();
        users.save(account);
    }

    private String normalizeEmail(String email) {
        return email.strip().toLowerCase(Locale.ROOT);
    }
}
