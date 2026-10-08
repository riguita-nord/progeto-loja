export const routeRegistry = new Map([
    ['/dashboard', { module: 'dashboard', titleKey: 'nav.dashboard', page: 'dashboard.html', styles: 'dashboard.css', load: () => import('../pages/dashboard.js') }],
    ['/workspaces', { module: 'workspaces', titleKey: 'nav.workspaces', page: 'workspaces.html', styles: 'info-page.css', load: () => import('../pages/workspaces.js') }],
    ['/projects', { module: 'projects', titleKey: 'nav.projects', page: 'projects.html', styles: 'info-page.css', load: () => import('../pages/projects.js') }],
    ['/documentation', { module: 'documentation', titleKey: 'nav.documentation', page: 'documentation.html', styles: 'info-page.css', load: () => import('../pages/documentation.js') }],
    ['/files', { module: 'files', titleKey: 'nav.files', page: 'files.html', styles: 'info-page.css', load: () => import('../pages/files.js') }],
    ['/calendar', { module: 'calendar', titleKey: 'nav.calendar', page: 'calendar.html', styles: 'info-page.css', load: () => import('../pages/calendar.js') }],
    ['/tasks', { module: 'tasks', titleKey: 'nav.tasks', page: 'tasks.html', styles: 'info-page.css', load: () => import('../pages/tasks.js') }],
    ['/settings', { module: 'settings', titleKey: 'nav.settings', page: 'settings.html', styles: 'info-page.css', load: () => import('../pages/settings.js') }]
]);

export function loadModule(route) {
    if (!route || typeof route.load !== 'function') {
        throw new TypeError('A registered route with a lazy module loader is required.');
    }
    return route.load();
}
