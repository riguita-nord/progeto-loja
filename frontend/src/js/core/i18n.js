import { emit } from './events.js';

const messages = {
    en: {
        layout: {
            tagline: 'Technology for new possibilities.',
            navigation: 'NAVIGATION',
            language: 'LANGUAGE',
            signIn: 'Sign in',
            openMenu: 'Open menu',
            closeMenu: 'Close menu',
            close: 'Close',
            search: 'Search',
            loading: 'Loading…',
            loadError: 'This page could not be loaded. Please try again.',
            startError: 'The application could not start. Please reload the page.',
            notFound: 'The page you requested does not exist.'
        },
        nav: {
            dashboard: 'Dashboard',
            workspaces: 'Workspaces',
            projects: 'Projects',
            documentation: 'Documentation',
            files: 'Files',
            calendar: 'Calendar',
            tasks: 'Tasks',
            settings: 'Settings'
        },
        login: {
            welcome: 'Welcome back',
            title: 'Sign in',
            email: 'Email',
            emailPlaceholder: 'name@example.com',
            password: 'Password',
            passwordPlaceholder: 'Your password',
            submit: 'Continue',
            unavailable: 'Authentication is not connected yet.'
        },
        dashboard: {
            previous: 'Previous slide',
            next: 'Next slide',
            chooseSlide: 'Choose a featured slide',
            showSlide: 'Show slide {number}',
            eyebrow: 'Nord-Lab Hub',
            title: 'Ideas brought to life with technology.',
            description: 'Discover thoughtful tools to make your everyday life simpler and more connected.',
            action: 'Discover more',
            slides: [
                {
                    label: 'Nord-Lab Hub',
                    title: 'Ideas brought to life with technology.',
                    description: 'Discover thoughtful tools to make your everyday life simpler and more connected.',
                    action: 'Discover more'
                },
                {
                    label: 'Solutions',
                    title: 'Your next step starts here.',
                    description: 'Explore tools and products made to support new possibilities.',
                    action: 'Explore solutions'
                },
                {
                    label: 'Community',
                    title: 'We grow better together.',
                    description: 'Join a community that shares curiosity, creativity and a desire to build.',
                    action: 'Learn more'
                }
            ]
        },
        modules: {
            intro: 'This area is ready to grow as the Nord Hub modules are developed.',
            workspaces: { title: 'Workspaces', description: 'Organizations and shared spaces in one place.' },
            projects: { title: 'Projects', description: 'Plan and follow project work with your team.' },
            documentation: { title: 'Documentation', description: 'A home for team knowledge and project notes.' },
            files: { title: 'Files', description: 'Shared files and resources for your workspace.' },
            calendar: { title: 'Calendar', description: 'Keep track of upcoming team events.' },
            tasks: { title: 'Tasks', description: 'A clear place for work that needs to get done.' },
            settings: { title: 'Settings', description: 'Personalize your Nord Hub experience.' }
        }
    },
    pt: {
        layout: {
            tagline: 'Tecnologia para novas possibilidades.',
            navigation: 'NAVEGAÇÃO',
            language: 'IDIOMA',
            signIn: 'Iniciar sessão',
            openMenu: 'Abrir menu',
            closeMenu: 'Fechar menu',
            close: 'Fechar',
            search: 'Pesquisar',
            loading: 'A carregar…',
            loadError: 'Não foi possível carregar esta página. Tenta novamente.',
            startError: 'Não foi possível iniciar a aplicação. Volta a carregar a página.',
            notFound: 'A página que procuras não existe.'
        },
        nav: {
            dashboard: 'Painel',
            workspaces: 'Espaços de trabalho',
            projects: 'Projetos',
            documentation: 'Documentação',
            files: 'Ficheiros',
            calendar: 'Calendário',
            tasks: 'Tarefas',
            settings: 'Definições'
        },
        login: {
            welcome: 'Bem-vindo de volta',
            title: 'Iniciar sessão',
            email: 'Email',
            emailPlaceholder: 'nome@exemplo.com',
            password: 'Palavra-passe',
            passwordPlaceholder: 'A tua palavra-passe',
            submit: 'Continuar',
            unavailable: 'A autenticação ainda não está ligada a um serviço.'
        },
        dashboard: {
            previous: 'Slide anterior',
            next: 'Próximo slide',
            chooseSlide: 'Escolher destaque',
            showSlide: 'Mostrar slide {number}',
            eyebrow: 'Nord-Lab Hub',
            title: 'Ideias que ganham vida com tecnologia.',
            description: 'Descobre ferramentas pensadas para tornar o teu dia a dia mais simples e mais conectado.',
            action: 'Descobrir mais',
            slides: [
                {
                    label: 'Nord-Lab Hub',
                    title: 'Ideias que ganham vida com tecnologia.',
                    description: 'Descobre ferramentas pensadas para tornar o teu dia a dia mais simples e mais conectado.',
                    action: 'Descobrir mais'
                },
                {
                    label: 'Soluções',
                    title: 'O próximo passo começa aqui.',
                    description: 'Explora ferramentas e produtos criados para acompanhar novas possibilidades.',
                    action: 'Explorar soluções'
                },
                {
                    label: 'Comunidade',
                    title: 'Crescemos melhor em conjunto.',
                    description: 'Junta-te a uma comunidade que partilha curiosidade, criatividade e vontade de criar.',
                    action: 'Saber mais'
                }
            ]
        },
        modules: {
            intro: 'Esta área está preparada para evoluir à medida que os módulos do Nord Hub forem desenvolvidos.',
            workspaces: { title: 'Espaços de trabalho', description: 'Organizações e espaços partilhados num só lugar.' },
            projects: { title: 'Projetos', description: 'Planeia e acompanha o trabalho dos projetos com a tua equipa.' },
            documentation: { title: 'Documentação', description: 'Um espaço para o conhecimento da equipa e notas dos projetos.' },
            files: { title: 'Ficheiros', description: 'Ficheiros e recursos partilhados no teu espaço de trabalho.' },
            calendar: { title: 'Calendário', description: 'Acompanha os próximos eventos da equipa.' },
            tasks: { title: 'Tarefas', description: 'Um espaço claro para organizar o trabalho por fazer.' },
            settings: { title: 'Definições', description: 'Personaliza a tua experiência no Nord Hub.' }
        }
    }
};

let currentLocale = readStoredLocale();

function readStoredLocale() {
    try {
        const savedLocale = window.localStorage.getItem('nord-hub-locale');
        return savedLocale === 'en' ? 'en' : 'pt';
    } catch (error) {
        console.warn('Could not read the saved language preference.', error);
        return 'pt';
    }
}

export function getLocale() {
    return currentLocale;
}

export function translate(key) {
    const value = key.split('.').reduce((entry, part) => entry?.[part], messages[currentLocale]);
    return value ?? key;
}

export function setLocale(locale) {
    if (!Object.hasOwn(messages, locale)) {
        throw new RangeError(`Unsupported language: ${locale}`);
    }

    currentLocale = locale;
    try {
        window.localStorage.setItem('nord-hub-locale', locale);
    } catch (error) {
        console.warn('Could not save the language preference.', error);
    }
    document.documentElement.lang = locale;
    emit('locale:change', locale);
}

export function applyTranslations(root = document) {
    root.querySelectorAll('[data-i18n]').forEach((element) => {
        const message = translate(element.dataset.i18n);
        if (element.children.length > 0 && element.matches('.nav-link')) {
            const label = element.querySelector('span');
            if (label) label.textContent = message;
        } else {
            element.textContent = message;
        }
    });

    root.querySelectorAll('[data-i18n-aria-label]').forEach((element) => {
        element.setAttribute('aria-label', translate(element.dataset.i18nAriaLabel));
    });
    root.querySelectorAll('[data-i18n-placeholder]').forEach((element) => {
        element.setAttribute('placeholder', translate(element.dataset.i18nPlaceholder));
    });
}
