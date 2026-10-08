# Nord Hub frontend

The frontend is split into two independent experiences:

- `public/index.html` is the public homepage.
- `public/setup.html` is the one-time administrator setup page served at `/setup`.
- `public/app.html` is the entry point for the internal application.
- `public/components/` and `public/pages/` contain the application's HTML shell and route templates.
- `src/css/` contains the public and application stylesheets.
- `src/js/` contains the public-page code, shared application core, and lazy-loaded route modules.

The frontend uses native HTML, CSS, and JavaScript modules. No backend implementation is included; `src/js/core/api.js` is the shared boundary for future communication with the Java backend in the repository's `backend/` directory.

## Routes and modules

The application router supports `/dashboard`, `/workspaces`, `/projects`, `/documentation`, `/files`, `/calendar`, `/tasks`, and `/settings`. Register routes and their dynamic imports in `src/js/core/module-loader.js`. Each route has its own HTML in `public/pages/` and JavaScript in `src/js/pages/`. Route styles live in `src/css/pages/`; routes with the same presentation share a stylesheet to avoid duplication.

Route modules export `mount(container, context)` and may return `unmount()` and `refresh()` lifecycle methods. The router keeps the application shell in place while replacing route content, updates browser history, and removes route-specific styles when navigating away. Non-dashboard pages currently show translated preparation states and make no claim to provide backend-backed features.

## Web server configuration

Serve `frontend/public/` as the document root and expose `frontend/src/` at the URL prefix `/src/`. Also serve the public `components/`, `pages/`, and `assets/` directories at those same URL prefixes. The application expects these URLs when loading its layout, route templates, stylesheets, modules, and logo.

Example Nginx configuration (replace the paths with the deployed absolute paths):

```nginx
root /path/to/frontend/public;

location /api/ {
    proxy_pass http://localhost:8080/api/;
}

location /src/ {
    alias /path/to/frontend/src/;
}

location /components/ {
    alias /path/to/frontend/public/components/;
}

location /pages/ {
    alias /path/to/frontend/public/pages/;
}

location /assets/ {
    alias /path/to/frontend/public/assets/;
}

location = / {
    try_files /index.html =404;
}

location = /setup {
    try_files /setup.html =404;
}

location / {
    try_files $uri $uri/ /app.html;
}
```

For Apache, configure the document root as `frontend/public/`, enable `mod_alias` and `mod_rewrite`, and add aliases (replace the example paths with the deployed absolute paths):

```apache
DirectoryIndex index.html
Alias /src/ "/path/to/frontend/src/"
Alias /components/ "/path/to/frontend/public/components/"
Alias /pages/ "/path/to/frontend/public/pages/"
Alias /assets/ "/path/to/frontend/public/assets/"

<Directory "/path/to/frontend/src/">
    Require all granted
</Directory>
<Directory "/path/to/frontend/public/components/">
    Require all granted
</Directory>
<Directory "/path/to/frontend/public/pages/">
    Require all granted
</Directory>
<Directory "/path/to/frontend/public/assets/">
    Require all granted
</Directory>
```

Enable `mod_rewrite` and use the following fallback in `.htaccess` in the document root. The root URL continues to serve `index.html`; unknown application routes load `app.html`.

```apache
RewriteEngine On
RewriteCond %{REQUEST_URI} !^/(api|src|components|pages|assets)(/|$)
RewriteCond %{REQUEST_URI} !^/$
RewriteRule ^setup$ setup.html [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ app.html [L]
```

The fallback must not rewrite `/api/` requests. Use in-app navigation to test routes on servers without SPA fallback; direct route refreshes require the configuration above.

## Backend boundary

All backend code and configuration belong in the repository-level `backend/` directory. Keep browser JavaScript separate from the Java backend. The `src/js/core/permissions.js` module only controls frontend presentation and is not an authorization or security boundary.
