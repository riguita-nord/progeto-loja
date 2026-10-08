# Nord Hub

Nord Hub is organized as two separate frontend experiences, an isolated Java backend, and a Ubuntu Server installer:

```text
frontend/
  public/          Public homepage and internal application HTML
  src/css/         Homepage and application styles
  src/js/          Browser modules, router and API client
backend/
  pom.xml
  mvnw
  src/             Spring Boot Java source, resources, migrations and tests
installer/
  nord-hub-installer.sh
```

The public homepage is `frontend/public/index.html`; the internal application starts at `frontend/public/app.html`. The backend and installer do not place server code inside the frontend.

See [backend/README.md](./backend/README.md) for build, API, authentication and current backend scope. See [frontend/README.md](./frontend/README.md) for the static server aliases and SPA fallback required to serve the application.

## Ubuntu Server installation

From the checked-out repository:

```sh
sudo bash ./installer/nord-hub-installer.sh install
sudo bash ./installer/nord-hub-installer.sh doctor
```

The installer accepts Ubuntu 24.04/26.04 on amd64/arm64, creates a non-root service account and PostgreSQL role, runs the backend tests before activation, and serves the existing frontend and API through Nginx on one origin. It preserves existing Nord Hub configuration and refuses to overwrite an unrelated Nginx site. The setup token is generated randomly and displayed only once.

For private-network testing, Nginx serves the Nord Hub homepage over HTTP port 80 at `http://<server-LAN-IP>/` (for example, `http://192.168.139.54/`). The installer makes the Nord Hub site the default HTTP site so opening the machine's IP shows the homepage instead of Nginx's welcome page. On an existing Ubuntu install, rerun the updated installer with `sudo bash ./installer/nord-hub-installer.sh install`; the installer updates its managed Nginx site and verifies the homepage. The backend API listens separately on port 8080; do not use `:8080` for the website, and do not expose that backend port to the public internet because it bypasses Nginx-level request limits.

Other supported commands are `update`, `status`, `restart`, `stop`, `start`, `logs`, `backup`, `restore`, and `uninstall`. Restore and uninstall require explicit confirmation. Uninstall retains configuration, database, storage and backups.

**Deployment limitation:** the current installer configures HTTP only. A configured domain does not itself provide TLS; do not expose the service publicly until HTTPS is configured and verified. The application currently implements the identity and workspace increment only; the other product modules and production operations listed in the project requirements are not complete.
