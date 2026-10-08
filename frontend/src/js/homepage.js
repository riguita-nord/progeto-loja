import { ApiError, request } from './core/api.js';

const menuToggle = document.querySelector('.menu-toggle');
const menuLinks = document.querySelector('.menu-links');
const sidebarClose = document.querySelector('.sidebar-close');
const backdrop = document.querySelector('.mobile-sidebar-backdrop');
const loginDialog = document.querySelector('#login-dialog');
const registrationDialog = document.querySelector('#register-dialog');
const loginButtons = document.querySelectorAll('.user-button, [data-open-login]');
const registrationButtons = document.querySelectorAll('[data-open-registration]');
const slides = Array.from(document.querySelectorAll('.slide'));
const indicators = Array.from(document.querySelectorAll('.slide-indicator'));

function setPublicMenuOpen(isOpen) {
    menuLinks.classList.toggle('is-open', isOpen);
    menuToggle.setAttribute('aria-expanded', String(isOpen));
    menuToggle.setAttribute('aria-label', isOpen ? 'Fechar menu' : 'Abrir menu');
    menuLinks.setAttribute('aria-hidden', String(!isOpen && window.innerWidth < 1200));
    backdrop.classList.toggle('is-visible', isOpen);
    backdrop.setAttribute('aria-hidden', String(!isOpen));
    document.body.classList.toggle('public-menu-open', isOpen);
    if (isOpen) sidebarClose.focus();
    else if (window.innerWidth < 1200) menuToggle.focus();
}

menuLinks.setAttribute('aria-hidden', String(window.innerWidth < 1200));
menuToggle.addEventListener('click', () => {
    setPublicMenuOpen(!menuLinks.classList.contains('is-open'));
});
sidebarClose.addEventListener('click', () => setPublicMenuOpen(false));
backdrop.addEventListener('click', () => setPublicMenuOpen(false));
menuLinks.querySelectorAll('.nav-link, .sidebar-search').forEach((link) => {
    link.addEventListener('click', () => setPublicMenuOpen(false));
});
document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && menuLinks.classList.contains('is-open')) setPublicMenuOpen(false);
});
window.addEventListener('resize', () => {
    if (window.innerWidth >= 1200 && menuLinks.classList.contains('is-open')) setPublicMenuOpen(false);
    menuLinks.setAttribute('aria-hidden', String(window.innerWidth < 1200 && !menuLinks.classList.contains('is-open')));
});

loginButtons.forEach((button) => {
    button.addEventListener('click', () => {
        setPublicMenuOpen(false);
        loginDialog.showModal();
        document.querySelector('#login-email').focus();
    });
});
registrationButtons.forEach((button) => {
    button.addEventListener('click', () => {
        setPublicMenuOpen(false);
        registrationDialog.showModal();
        document.querySelector('#register-name').focus();
    });
});
document.querySelector('[data-close-login]').addEventListener('click', () => loginDialog.close());
document.querySelector('[data-close-registration]').addEventListener('click', () => registrationDialog.close());
function displayAuthError(error, action) {
    if (error instanceof ApiError) {
        if (error.status === 409 && error.message.includes('Initial account setup')) {
            return 'O administrador ainda não concluiu a configuração inicial. Contacta-o para ativar o registo.';
        }
        if (error.status === 409) {
            return action === 'register'
                ? 'Já existe uma conta com este e-mail. Inicia sessão ou utiliza outro e-mail.'
                : 'Não foi possível concluir o pedido devido a um conflito.';
        }
        if (error.status === 400) {
            return 'Verifica os dados. A palavra-passe deve ter entre 12 e 128 caracteres.';
        }
        if (error.status === 401) {
            return 'O e-mail ou a palavra-passe estão incorretos.';
        }
        if (error.status === 429) {
            return 'Foram feitas demasiadas tentativas. Aguarda alguns minutos e tenta novamente.';
        }
        return error.message;
    }
    if (error instanceof TypeError) {
        return 'Não foi possível contactar o servidor. Confirma a ligação e tenta novamente.';
    }
    return 'Ocorreu um erro inesperado. Tenta novamente.';
}

function setFormBusy(form, isBusy) {
    const submit = form.querySelector('[type="submit"]');
    submit.disabled = isBusy;
    submit.setAttribute('aria-busy', String(isBusy));
}

loginDialog.addEventListener('click', (event) => {
    if (event.target === loginDialog) loginDialog.close();
});
registrationDialog.addEventListener('click', (event) => {
    if (event.target === registrationDialog) registrationDialog.close();
});
loginDialog.querySelector('form').addEventListener('submit', (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const message = form.querySelector('.login-message');
    const values = new FormData(form);
    message.textContent = '';
    setFormBusy(form, true);
    request('/auth/login', {
        method: 'POST',
        body: JSON.stringify({
            email: values.get('email'),
            password: values.get('password')
        })
    }).then(() => {
        window.location.assign('/app.html');
    }).catch((error) => {
        message.textContent = displayAuthError(error, 'login');
    }).finally(() => {
        setFormBusy(form, false);
    });
});
registrationDialog.querySelector('form').addEventListener('submit', (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const message = form.querySelector('.login-message');
    const values = new FormData(form);
    const email = values.get('email');
    message.textContent = '';
    setFormBusy(form, true);
    request('/auth/register', {
        method: 'POST',
        body: JSON.stringify({
            displayName: values.get('name'),
            email,
            password: values.get('password')
        })
    }).then(() => {
        registrationDialog.close();
        const loginForm = loginDialog.querySelector('form');
        loginForm.elements.email.value = email;
        loginForm.querySelector('.login-message').textContent = 'Conta criada com sucesso. Inicia sessão com a tua palavra-passe.';
        loginDialog.showModal();
        loginForm.elements.password.focus();
    }).catch((error) => {
        message.textContent = displayAuthError(error, 'register');
    }).finally(() => {
        setFormBusy(form, false);
    });
});

let activeSlide = 0;
function showSlide(index) {
    activeSlide = (index + slides.length) % slides.length;
    slides.forEach((slide, slideIndex) => {
        const isActive = slideIndex === activeSlide;
        slide.classList.toggle('active', isActive);
        slide.setAttribute('aria-hidden', String(!isActive));
        indicators[slideIndex].classList.toggle('active', isActive);
        indicators[slideIndex].setAttribute('aria-current', String(isActive));
    });
}

const previous = document.querySelector('[data-slide-prev]');
const next = document.querySelector('[data-slide-next]');
const showPrevious = () => showSlide(activeSlide - 1);
const showNext = () => showSlide(activeSlide + 1);
previous.addEventListener('click', showPrevious);
next.addEventListener('click', showNext);
indicators.forEach((indicator, index) => {
    indicator.addEventListener('click', () => showSlide(index));
});

if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    window.setInterval(showNext, 6000);
}
