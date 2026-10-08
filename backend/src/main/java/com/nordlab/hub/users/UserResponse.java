package com.nordlab.hub.users;

import java.util.UUID;

public record UserResponse(UUID id, String email, String displayName) {
    public static UserResponse from(UserAccount user) {
        return new UserResponse(user.getId(), user.getEmail(), user.getDisplayName());
    }
}
