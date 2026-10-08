export function mountInfoPage(container) {
    if (!container.querySelector('[data-module-page]')) {
        throw new Error('Module page markup is missing its data-module-page root.');
    }
}
