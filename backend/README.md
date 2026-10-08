# Nord Hub backend

The backend is a Java 21 / Spring Boot modular monolith. All Java, Maven and backend configuration is kept under `backend/`; the frontend remains in `frontend/`, and the Ubuntu installer is in `installer/`.

## Build and run

```sh
cd backend
sh ./mvnw clean verify
DATABASE_URL=jdbc:postgresql://localhost:5432/nordhub \
DATABASE_USERNAME=nordhub \
DATABASE_PASSWORD='<local secret>' \
sh ./mvnw spring-boot:run
```

On Windows, use `mvnw.cmd`. The first wrapper run downloads the pinned Maven distribution and verifies its SHA-256 checksum. A local PostgreSQL database is required for the application and integration tests.

The backend binds to `0.0.0.0:8080` by default for private-network testing. On the Ubuntu install, Nginx serves the homepage and proxies API calls over HTTP port 80; open `http://<server-LAN-IP>/` (for example, `http://192.168.139.54/`) to see the website. Port 8080 is the backend API, not the website. Set `SERVER_ADDRESS=127.0.0.1` to restrict the backend to local connections through Nginx. Binding to all interfaces exposes the backend port directly and bypasses Nginx-level request limits; do not expose it to the public internet, and restrict port 8080 to the test network in the host firewall. Flyway applies versioned schema migrations; Hibernate validates the schema and never updates it automatically. Configure a strong, private `BOOTSTRAP_TOKEN` before starting an empty database.

## Initial account

The installer generates a random setup token and displays it after installation. Open `/setup` on the installed site and enter the configured administrator email, a password of at least 12 characters, and the token. If the output was lost, ask the server administrator to retrieve it securely; keep it private. The equivalent API is `POST /api/v1/auth/bootstrap` with the token in `X-Setup-Token` and a JSON body containing `email`, `displayName`, and `password`. When `ADMIN_EMAIL` was configured during installation, the request must use that email. The token is accepted only until the first user is created and the bootstrap marker is committed.

After setup, public account registration is available at `POST /api/v1/auth/register`. Authentication uses server-side sessions, HttpOnly cookies, CSRF tokens, and Argon2id password hashes. The login endpoint applies a 15-minute account lock after five consecutive bad-password attempts. Password recovery, SMTP verification and broader IP-based rate limiting are not implemented yet.

## Initial API

All API routes use `/api/v1/`.

| Area | Routes |
| --- | --- |
| Session | `GET /auth/csrf`, `POST /auth/bootstrap`, `POST /auth/register`, `POST /auth/login`, `POST /auth/logout`, `GET /auth/me`, `POST /auth/password` |
| Workspaces | `GET/POST /workspaces`, `GET/PUT /workspaces/{id}`, `GET/POST /workspaces/{id}/members`, `DELETE /workspaces/{id}/members/{userId}` |

Workspace reads require membership. Updates and member management require Owner or Admin membership. Responses use DTOs; API validation and error responses are handled centrally. OpenAPI is available at `/swagger-ui.html` to authenticated users only. Actuator exposes only the unauthenticated, detail-free health endpoint.

## Integration tests

`sh ./mvnw verify` runs the unit and PostgreSQL integration tests. The integration tests use Testcontainers and are skipped automatically when Docker is unavailable. The installer runs the same Maven verification before activating a release.

## Current implementation scope

Implemented so far: Spring Boot foundation, PostgreSQL/Flyway, secure password hashing, session authentication, one-time initial account bootstrap, registration, password changes, failed-login lockout, CSRF/CORS boundaries, user profile endpoint, workspace CRUD/member operations and workspace access checks.

Password recovery, email verification, teams, projects, tasks, documents, files, calendar, onboarding, notifications, audit events, HTTPS automation and production-scale distributed rate limiting remain future implementation work. Do not treat this initial increment as production-complete.
