package com.nordlab.hub.security;

import com.nordlab.hub.users.UserAccount;
import com.nordlab.hub.users.UserRepository;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
public class HubUserDetailsService implements UserDetailsService {
    private final UserRepository users;

    public HubUserDetailsService(UserRepository users) {
        this.users = users;
    }

    @Override
    public UserDetails loadUserByUsername(String email) throws UsernameNotFoundException {
        UserAccount account = users.findByEmail(email)
                .orElseThrow(() -> new UsernameNotFoundException("Account not found."));
        return User.withUsername(account.getId().toString())
                .password(account.getPasswordHash())
                .disabled(!account.isEnabled())
                .authorities(account.isAdmin()
                        ? new String[]{"ROLE_USER", "ROLE_ADMIN"}
                        : new String[]{"ROLE_USER"})
                .build();
    }
}
