import { applyTranslations, getLocale, setLocale, translate } from './i18n.js';
import { request } from './api.js';

const themeKey = 'nord-hub-theme';
function storedTheme() {
    try { return localStorage.getItem(themeKey) === 'dark' ? 'dark' : 'light'; }
    catch { return 'light'; }
}
function applyTheme(theme) {
    document.documentElement.dataset.appTheme = theme;
    try { localStorage.setItem(themeKey, theme); } catch { /* Storage can be disabled. */ }
    document.querySelectorAll('[data-account-theme]').forEach(button => {
        button.setAttribute('aria-pressed', String(button.dataset.accountTheme === theme));
    });
}
export function initializeAccountMenu({ onOpenLogin }) {
    const container = document.querySelector('.app-account');
    const trigger = container.querySelector('.app-account-trigger');
    const panel = container.querySelector('.app-account-panel');
    const close = () => { panel.hidden = true; trigger.setAttribute('aria-expanded', 'false'); };
    const show = () => { panel.hidden = false; trigger.setAttribute('aria-expanded', 'true'); };
    trigger.addEventListener('click', () => panel.hidden ? show() : close());
    document.addEventListener('pointerdown', event => { if (!container.contains(event.target)) close(); });
    document.addEventListener('keydown', event => {
        if (event.key === 'Escape' && !panel.hidden) { close(); trigger.focus(); }
    });
    panel.querySelector('[data-account-login]').addEventListener('click', () => { close(); onOpenLogin(); });
    panel.querySelector('[data-account-refresh]').addEventListener('click', () => window.location.reload());
    panel.querySelectorAll('[data-account-locale]').forEach(button => button.addEventListener('click', () => {
        setLocale(button.dataset.accountLocale); applyTranslations(); updateLocale();
    }));
    const updateLocale = () => panel.querySelectorAll('[data-account-locale]').forEach(button => {
        button.setAttribute('aria-pressed', String(button.dataset.accountLocale === getLocale()));
    });
    panel.querySelectorAll('[data-account-theme]').forEach(button => button.addEventListener('click', () => applyTheme(button.dataset.accountTheme)));
    panel.querySelector('[data-account-settings]').addEventListener('click', close);
    const error = panel.querySelector('.app-account-error');
    const logout = panel.querySelector('[data-account-logout]');
    logout.addEventListener('click', async () => {
        logout.disabled = true; error.hidden = true;
        try { await request('/auth/logout', { method: 'POST' }); window.location.assign('/'); }
        catch { error.textContent = translate('account.error'); error.hidden = false; logout.disabled = false; }
    });
    const setUser = user => {
        const name = user?.displayName || user?.email || translate('account.guest');
        const initial = name.trim().charAt(0).toUpperCase();
        container.querySelectorAll('.app-account-name, .app-account-card-name').forEach(el => { el.textContent = name; el.removeAttribute('data-i18n'); });
        container.querySelectorAll('.app-account-avatar').forEach(el => { el.textContent = initial; });
        container.querySelector('.app-account-role').textContent = user?.email || '';
        container.querySelector('.app-account-card-email').textContent = user?.email || '';
        container.querySelector('[data-account-login]').hidden = true;
        logout.hidden = false;
    };
    applyTheme(storedTheme());
    updateLocale();
    request('/auth/me').then(setUser).catch(() => { /* Guests must not display fictional account data. */ });
    document.querySelector('.app-notification-button').addEventListener('click', () => {
        // Notifications are reserved for the notification module; no fabricated notification data.
        document.querySelector('.app-notification-button').blur();
    });
}
