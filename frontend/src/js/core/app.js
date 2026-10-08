import { applyTranslations, getLocale, setLocale, translate } from './i18n.js';
import { initializeRouter } from './router.js';
import { initializeAccountMenu } from './account-menu.js';

async function loadLayout() {
    const layoutUrl = new URL('/components/app-layout.html', window.location.origin);
    layoutUrl.searchParams.set('v', '3');
    const response = await fetch(layoutUrl);
    if (!response.ok) {
        throw new Error(`Could not load the main layout (HTTP ${response.status}).`);
    }

    const documentFragment = new DOMParser().parseFromString(await response.text(), 'text/html');
    const layout = document.createDocumentFragment();
    Array.from(documentFragment.body.children).forEach((element) => {
        layout.append(document.importNode(element, true));
    });
    document.querySelector('#app-shell').replaceChildren(layout);
}

function initializeSharedControls() {
    const menuToggle = document.querySelector('.app-menu-toggle');
    const menuLinks = document.querySelector('.app-sidebar');
    const menuCloseButton = document.querySelector('.app-sidebar-close');
    const mobileBackdrop = document.querySelector('.app-sidebar-backdrop');
    const loginDialog = document.querySelector('#app-login-dialog');
    initializeAccountMenu({ loginDialog, onOpenLogin: () => { setMenuOpen(false); loginDialog.showModal(); document.querySelector('#app-login-email').focus(); } });

    function setMenuOpen(isOpen) {
        menuLinks.classList.toggle('is-open', isOpen);
        menuToggle.setAttribute('aria-expanded', String(isOpen));
        menuToggle.setAttribute('aria-label', translate(isOpen ? 'layout.closeMenu' : 'layout.openMenu'));
        menuLinks.setAttribute('aria-hidden', String(!isOpen && window.innerWidth < 1200));
        mobileBackdrop.classList.toggle('is-visible', isOpen);
        mobileBackdrop.setAttribute('aria-hidden', String(!isOpen));
        document.body.classList.toggle('app-sidebar-open', isOpen);
        if (isOpen) menuCloseButton.focus();
        else if (window.innerWidth < 1200) menuToggle.focus();
    }

    menuLinks.setAttribute('aria-hidden', String(window.innerWidth < 1200));
    menuToggle.addEventListener('click', () => setMenuOpen(!menuLinks.classList.contains('is-open')));
    menuCloseButton.addEventListener('click', () => setMenuOpen(false));
    mobileBackdrop.addEventListener('click', () => setMenuOpen(false));
    menuLinks.querySelectorAll('a[data-app-route]').forEach((link) => {
        link.addEventListener('click', () => setMenuOpen(false));
    });
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && menuLinks.classList.contains('is-open')) setMenuOpen(false);
    });

    document.querySelectorAll('.app-user-button, [data-open-login]').forEach((button) => {
        button.addEventListener('click', () => {
            setMenuOpen(false);
            loginDialog.showModal();
            document.querySelector('#app-login-email').focus();
        });
    });

    document.querySelector('[data-close-login]').addEventListener('click', () => loginDialog.close());
    loginDialog.addEventListener('click', (event) => {
        if (event.target === loginDialog) loginDialog.close();
    });
    loginDialog.querySelector('form').addEventListener('submit', (event) => {
        event.preventDefault();
        loginDialog.querySelector('.app-login-message').textContent = translate('login.unavailable');
    });

    window.addEventListener('resize', () => {
        if (window.innerWidth >= 1200 && menuLinks.classList.contains('is-open')) setMenuOpen(false);
        menuLinks.setAttribute('aria-hidden', String(window.innerWidth < 1200 && !menuLinks.classList.contains('is-open')));
    });
}

async function start() {
    try {
        await loadLayout();
        document.documentElement.lang = getLocale();
        applyTranslations();
        initializeSharedControls();
        await initializeRouter();
    } catch (error) {
        console.error('Nord Hub frontend could not start.', error);
        const shell = document.querySelector('#app-shell');
        shell.textContent = translate('layout.startError');
    }
}

void start();
