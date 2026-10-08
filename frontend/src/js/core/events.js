const listeners = new Map();

export function on(eventName, listener) {
    const eventListeners = listeners.get(eventName) ?? new Set();
    eventListeners.add(listener);
    listeners.set(eventName, eventListeners);

    return () => {
        eventListeners.delete(listener);
        if (eventListeners.size === 0) listeners.delete(eventName);
    };
}

export function emit(eventName, detail) {
    listeners.get(eventName)?.forEach((listener) => listener(detail));
}
