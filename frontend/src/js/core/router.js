import { emit, on } from './events.js';
import { loadModule, routeRegistry } from './module-loader.js';
import { applyTranslations, translate } from './i18n.js';

let activeModule = null;
let activePageStylesheet = null;
let navigationId = 0;
const stylesheetLoads = new Map();

function normalizePath(pathname) {
    if (pathname === '/' || pathname === '/index.html' || pathname === '/app.html' || pathname === '/public/app.html') {
        return '/dashboard';
    }
    return pathname.length > 1 && pathname.endsWith('/') ? pathname.slice(0, -1) : pathname;
}

function updateNavigation(pathname) {
    document.querySelectorAll('[data-route-link]').forEach((link) => {
        const isActive = link.dataset.routeLink === routeRegistry.get(pathname)?.module;
        link.classList.toggle('active', isActive);
        if (isActive) link.setAttribute('aria-current', 'page');
        else link.removeAttribute('aria-current');
    });
}

function showStatus(message, isError = false) {
    const status = document.querySelector('#app-route-status');
    status.hidden = !message;
    status.textContent = message;
    status.classList.toggle('is-error', isError);
}

function loadPageMarkup(page) {
    return fetch(`/pages/${encodeURIComponent(page)}`).then(async (response) => {
        if (!response.ok) throw new Error(`Could not load module page "${page}" (HTTP ${response.status}).`);
        const parsed = new DOMParser().parseFromString(await response.text(), 'text/html');
        const fragment = document.createDocumentFragment();
        Array.from(parsed.body.children).forEach((element) => {
            fragment.append(document.importNode(element, true));
        });
        return fragment;
    });
}

function loadPageStylesheet(styles) {
    const current = activePageStylesheet?.dataset.routeStylesheet === styles
        ? activePageStylesheet
        : Array.from(document.querySelectorAll('link[data-route-stylesheet]'))
            .find((link) => link.dataset.routeStylesheet === styles);
    if (current) return Promise.resolve(current);

    const pending = stylesheetLoads.get(styles);
    if (pending) return pending;

    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = `/src/css/pages/${encodeURIComponent(styles)}`;
    link.dataset.routeStylesheet = styles;

    const load = new Promise((resolve, reject) => {
        link.addEventListener('load', () => resolve(link), { once: true });
        link.addEventListener('error', () => {
            link.remove();
            reject(new Error(`Could not load page stylesheet "${styles}".`));
        }, { once: true });
        document.head.append(link);
    }).finally(() => {
        stylesheetLoads.delete(styles);
    });

    stylesheetLoads.set(styles, load);
    return load;
}

async function unmountActiveModule() {
    const moduleInstance = activeModule;
    activeModule = null;
    if (moduleInstance?.unmount) await moduleInstance.unmount();
}

function removeInactiveStylesheet(stylesheet) {
    document.querySelectorAll('link[data-route-stylesheet]').forEach((link) => {
        if (link !== stylesheet) link.remove();
    });
}

export async function navigate(pathname, { replace = false } = {}) {
    const path = normalizePath(pathname);
    const route = routeRegistry.get(path);
    const requestId = ++navigationId;
    const content = document.querySelector('#app-route-content');

    if (!route) {
        try {
            await unmountActiveModule();
        } catch (error) {
            console.error('The active page failed to unmount after navigation to an unknown route.', error);
        }
        if (requestId !== navigationId) return;
        activePageStylesheet = null;
        removeInactiveStylesheet(null);
        content.replaceChildren();
        showStatus(translate('layout.notFound'), true);
        document.title = `404 — Nord-Lab Hub`;
        updateNavigation(path);
        emit('route:change', { path, module: null, notFound: true });
        return;
    }

    if (window.location.pathname !== path) {
        if (replace) window.history.replaceState({}, '', path);
        else window.history.pushState({}, '', path);
    }

    showStatus(translate('layout.loading'));
    updateNavigation(path);

    try {
        await unmountActiveModule();
        if (requestId !== navigationId) return;
        content.replaceChildren();

        const [moduleDefinition, pageMarkup, stylesheet] = await Promise.all([
            loadModule(route),
            loadPageMarkup(route.page),
            loadPageStylesheet(route.styles)
        ]);
        if (requestId !== navigationId) return;

        content.replaceChildren(pageMarkup);
        const lifecycle = await moduleDefinition.mount(content, { path });
        if (requestId !== navigationId) {
            if (typeof lifecycle === 'function') await lifecycle();
            else await lifecycle?.unmount?.();
            return;
        }

        activeModule = typeof lifecycle === 'function' ? { unmount: lifecycle } : lifecycle;
        activePageStylesheet = stylesheet;
        removeInactiveStylesheet(stylesheet);
        showStatus('');
        document.title = `${translate(route.titleKey)} — Nord-Lab Hub`;
        applyTranslations();
        updateNavigation(path);
        emit('route:change', { path, module: route.module });
    } catch (error) {
        console.error(`Could not load route "${path}".`, error);
        if (requestId !== navigationId) return;
        content.replaceChildren();
        activePageStylesheet = null;
        removeInactiveStylesheet(null);
        showStatus(translate('layout.loadError'), true);
        emit('route:error', { path, error });
    }
}

export function initializeRouter() {
    document.addEventListener('click', (event) => {
        const link = event.target.closest('a[data-app-route]');
        if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        event.preventDefault();
        void navigate(new URL(link.href).pathname);
    });

    window.addEventListener('popstate', () => {
        void navigate(window.location.pathname, { replace: true });
    });

    on('locale:change', () => {
        void navigate(window.location.pathname, { replace: true });
    });

    return navigate(window.location.pathname, { replace: true });
}
