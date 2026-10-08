import { translate } from '../core/i18n.js';

export function mount(container) {
    const slides = Array.from(container.querySelectorAll('.app-slide'));
    const indicators = Array.from(container.querySelectorAll('.app-slide-indicator'));
    const previous = container.querySelector('[data-slide-prev]');
    const next = container.querySelector('[data-slide-next]');
    const indicatorHandlers = [];
    indicators.forEach((indicator, index) => {
        indicator.setAttribute('aria-label', translate('dashboard.showSlide').replace('{number}', String(index + 1)));
    });
    let current = 0;

    function show(index) {
        current = (index + slides.length) % slides.length;
        slides.forEach((slide, slideIndex) => {
            const isActive = slideIndex === current;
            slide.classList.toggle('active', isActive);
            slide.setAttribute('aria-hidden', String(!isActive));
            indicators[slideIndex].classList.toggle('active', isActive);
            indicators[slideIndex].setAttribute('aria-current', String(isActive));
        });
    }

    const showPrevious = () => show(current - 1);
    const showNext = () => show(current + 1);
    previous.addEventListener('click', showPrevious);
    next.addEventListener('click', showNext);
    indicators.forEach((indicator, index) => {
        const handler = () => show(index);
        indicator.addEventListener('click', handler);
        indicatorHandlers.push(handler);
    });

    const timer = window.matchMedia('(prefers-reduced-motion: reduce)').matches
        ? null
        : window.setInterval(showNext, 6000);

    return {
        unmount() {
            if (timer !== null) window.clearInterval(timer);
            previous.removeEventListener('click', showPrevious);
            next.removeEventListener('click', showNext);
            indicators.forEach((indicator, index) => {
                indicator.removeEventListener('click', indicatorHandlers[index]);
            });
        }
    };
}
