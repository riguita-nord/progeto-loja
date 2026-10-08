export class ApiError extends Error {
    constructor(message, status, code = 'API_ERROR', fields = {}) {
        super(message);
        this.name = 'ApiError';
        this.status = status;
        this.code = code;
        this.fields = fields;
    }
}

function readCookie(name) {
    const cookie = document.cookie.split('; ').find((entry) => entry.startsWith(`${name}=`));
    return cookie ? decodeURIComponent(cookie.slice(name.length + 1)) : null;
}

async function getCsrfToken() {
    const existingToken = readCookie('XSRF-TOKEN');
    if (existingToken) return { headerName: 'X-XSRF-TOKEN', token: existingToken };

    const response = await fetch('/api/v1/auth/csrf', {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin'
    });
    if (!response.ok) {
        throw new ApiError(`Could not obtain a CSRF token (HTTP ${response.status}).`, response.status);
    }
    const csrf = await response.json();
    return {
        headerName: csrf.headerName,
        token: readCookie('XSRF-TOKEN') || csrf.token
    };
}

function apiUrl(path) {
    const normalized = path.startsWith('/') ? path : `/${path}`;
    if (normalized.startsWith('/api/v1/')) return normalized;
    const versionedPath = normalized.startsWith('/v1/') ? normalized.slice(3) : normalized;
    return `/api/v1${versionedPath}`;
}

export async function request(path, options = {}) {
    const headers = new Headers(options.headers);
    headers.set('Accept', 'application/json');
    if (options.body && !(options.body instanceof FormData) && !headers.has('Content-Type')) {
        headers.set('Content-Type', 'application/json');
    }

    const method = (options.method || 'GET').toUpperCase();
    if (!['GET', 'HEAD', 'OPTIONS', 'TRACE'].includes(method)) {
        const csrf = await getCsrfToken();
        headers.set(csrf.headerName, csrf.token);
    }

    const response = await fetch(apiUrl(path), {
        ...options,
        method,
        credentials: 'same-origin',
        headers
    });

    if (!response.ok) {
        const errorBody = await response.text();
        let error = {};
        if (errorBody) {
            try {
                error = JSON.parse(errorBody);
            } catch (parseError) {
                if (!(parseError instanceof SyntaxError)) throw parseError;
            }
        }
        throw new ApiError(
            error.message || `API request failed with status ${response.status}.`,
            response.status,
            error.code,
            error.fields
        );
    }

    if (response.status === 204) return null;
    return response.json();
}
