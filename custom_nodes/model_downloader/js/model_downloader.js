// ComfyUI Model Downloader Extension
// Only log initialization message in non-production environments
if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
    console.log("[MODEL_DOWNLOADER] Loading model downloader extension...");
}

// Register message handler as early as possible
function registerMessageHandler() {
    try {
        // Try first method: Using API extension system
        if (window.api && typeof window.api.registerExtension === 'function') {
            // Register with ComfyUI API extension system
            window.api.registerExtension({
                name: "model_downloader",
                init() {
                    // Register message types with API
                    
                    // Add the type directly to API registered types so it doesn't error
                    if (!window.api.reportedUnknownMessageTypes) {
                        window.api.reportedUnknownMessageTypes = new Set();
                    }
                    
                    // Register our custom message type by adding it to the API's reported set
                    window.api.reportedUnknownMessageTypes.add('model_download_progress');
                    
                    // Register a standard event listener (ComfyUI extended API)
                    window.api.addEventListener("model_download_progress", function(data) {
                        // Forward to our event handler function if available
                        if (window.modelDownloader && typeof window.modelDownloader.handleMessageEvent === 'function') {
                            window.modelDownloader.handleMessageEvent(data);
                        }
                    });
                }
            });
        }
        
        // Try second method: Using custom API message handler (newer ComfyUI versions)
        if (window.app && typeof window.app.registerMessageHandler === 'function') {
            window.app.registerMessageHandler('model_download_progress', function(event) {
                // Forward to our event handler function if available
                if (window.modelDownloader && typeof window.modelDownloader.handleMessageEvent === 'function') {
                    window.modelDownloader.handleMessageEvent(event);
                }
            });
        }
        
        // Try third method: Direct WebSocket monkey patching (older ComfyUI versions)
        function patchWebSocket() {
            if (window.app && window.app.socket && window.app.socket instanceof WebSocket) {
                // Add the message type to the registered set to prevent the error
                if (window.api && window.api.reportedUnknownMessageTypes instanceof Set) {
                    window.api.reportedUnknownMessageTypes.add('model_download_progress');
                }
                
                const originalOnMessage = window.app.socket.onmessage;
                window.app.socket.onmessage = function(event) {
                    // Call original first
                    if (originalOnMessage) {
                        originalOnMessage.call(this, event);
                    }
                    
                    // Then handle for our own messages
                    try {
                        const message = JSON.parse(event.data);
                        if (message.type === 'model_download_progress') {
                            // Forward to our core handler function if available
                            if (window.modelDownloader && typeof window.modelDownloader.handleMessageEvent === 'function') {
                                window.modelDownloader.handleMessageEvent(message);
                            }
                            // Also forward it as a custom event
                            if (window.app && typeof window.app.dispatchEvent === 'function') {
                                window.app.dispatchEvent(new CustomEvent('model_download_progress', {detail: message}));
                            }
                        }
                    } catch (e) {
                        // Ignore JSON parse errors
                    }
                };
            } 
            // Also try the API socket if exists
            else if (window.app && window.app.api && window.app.api.socket && window.app.api.socket instanceof WebSocket) {
                // Add the message type to the registered set to prevent the error
                if (window.app.api.reportedUnknownMessageTypes instanceof Set) {
                    window.app.api.reportedUnknownMessageTypes.add('model_download_progress');
                }
                
                const originalOnMessage = window.app.api.socket.onmessage;
                window.app.api.socket.onmessage = function(event) {
                    // Call original first
                    if (originalOnMessage) {
                        originalOnMessage.call(this, event);
                    }
                    
                    // Then handle for our own messages
                    try {
                        const message = JSON.parse(event.data);
                        if (message.type === 'model_download_progress') {
                            // Forward to our core handler function if available
                            if (window.modelDownloader && typeof window.modelDownloader.handleMessageEvent === 'function') {
                                window.modelDownloader.handleMessageEvent(message);
                            }
                            // Also forward it as a custom event
                            if (window.app && typeof window.app.dispatchEvent === 'function') {
                                window.app.dispatchEvent(new CustomEvent('model_download_progress', {detail: message}));
                            }
                        }
                    } catch (e) {
                        // Ignore JSON parse errors
                    }
                };
            }
            else {
                // Try again later when app is fully loaded
                setTimeout(patchWebSocket, 500);
            }
        }
        
        // Start WebSocket patching process
        patchWebSocket();
        
    } catch (error) {
        console.error('[MODEL_DOWNLOADER] Error registering message handler:', error);
    }
}

// Create and load the main downloader script using a script tag
function loadMainScript() {
    // Get the current script path to determine the base path
    const scripts = document.getElementsByTagName('script');
    let basePath = '';
    
    // Find the current script
    for (const script of scripts) {
        if (script.src && script.src.includes('model_downloader.js')) {
            basePath = script.src.substring(0, script.src.lastIndexOf('/') + 1);
            console.log('[MODEL_DOWNLOADER] Found script path:', script.src);
            break;
        }
    }
    
    // If path not found, use relative path
    if (!basePath) {
        // Try to derive it from the current page URL
        const currentUrl = window.location.href;
        const urlObj = new URL(currentUrl);
        
        // First try with /extensions/ path which is how ComfyUI serves custom node files
        basePath = `${urlObj.protocol}//${urlObj.host}/extensions/model_downloader/`;
        console.log('[MODEL_DOWNLOADER] Using extensions path:', basePath);
    }
    
    // Create a script element for the main downloader script
    const script = document.createElement('script');
    script.type = 'text/javascript';
    script.src = basePath + 'backend_download.js';
    script.onload = function() {
        console.log('[MODEL_DOWNLOADER] Main downloader script loaded');
    };
    script.onerror = function(error) {
        console.error('[MODEL_DOWNLOADER] Error loading main script:', error);
    };
    
    // Append the script to the document head
    document.head.appendChild(script);
}

// Initialize the extension
function registerModelDownloader() {
    // Register message handler first
    registerMessageHandler();
    
    // Then load the main script
    loadMainScript();
}

// Wait for DOMContentLoaded to ensure the document is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', registerModelDownloader);
} else {
    registerModelDownloader();
}
