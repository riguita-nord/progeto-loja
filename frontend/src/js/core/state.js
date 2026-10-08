const state = new Map();
const subscribers = new Map();

export function getState(key) {
    return state.get(key);
}

export function setState(key, value) {
    state.set(key, value);
    subscribers.get(key)?.forEach((subscriber) => subscriber(value));
}

export function subscribe(key, subscriber) {
    const keySubscribers = subscribers.get(key) ?? new Set();
    keySubscribers.add(subscriber);
    subscribers.set(key, keySubscribers);

    return () => {
        keySubscribers.delete(subscriber);
        if (keySubscribers.size === 0) subscribers.delete(key);
    };
}
