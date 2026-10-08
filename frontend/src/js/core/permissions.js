export function isActionAvailable(uiCapabilities, capability) {
    return uiCapabilities?.includes(capability) ?? false;
}
