// ComfyUI Model Downloader Extension
// Only log initialization message in non-production environments
if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
    console.log("[MODEL_DOWNLOADER] Loading model downloader extension...");
}

// Register message handler as early as possible
function registerMessageHandler() {
    try {
        // Register the model_download_progress message type in all possible ways
        // to ensure compatibility with different ComfyUI versions
        
        // Method 1: Add to the reportedUnknownMessageTypes set if it exists
        if (window.api && typeof window.api.reportedUnknownMessageTypes !== 'undefined') {
            if (!(window.api.reportedUnknownMessageTypes instanceof Set)) {
                window.api.reportedUnknownMessageTypes = new Set();
            }
            window.api.reportedUnknownMessageTypes.add('model_download_progress');
        }
        
        // Method 2: Using API extension system (newer ComfyUI versions)
        if (window.api && typeof window.api.registerExtension === 'function') {
            window.api.registerExtension({
                name: "model_downloader",
                init() {
                    window.api.addEventListener("model_download_progress", function(data) {
                        // Forward to our event handler function if available
                        if (window.modelDownloader && typeof window.modelDownloader.handleMessageEvent === 'function') {
                            window.modelDownloader.handleMessageEvent(data);
                        }
                    });
                }
            });
        }
        
        // Method 3: Using custom API message handler (alternative newer ComfyUI versions)
        if (window.app && typeof window.app.registerMessageHandler === 'function') {
            window.app.registerMessageHandler('model_download_progress', function(event) {
                if (window.modelDownloader && typeof window.modelDownloader.handleMessageEvent === 'function') {
                    window.modelDownloader.handleMessageEvent(event);
                }
            });
        }
        
        // Method 4: Direct WebSocket patching (fallback for older ComfyUI versions)
        function patchWebSocket() {
            // Find the WebSocket object to patch
            let socket = null;
            let socketParent = null;
            
            if (window.app && window.app.socket && window.app.socket instanceof WebSocket) {
                socket = window.app.socket;
                socketParent = window.app;
            } else if (window.app && window.app.api && window.app.api.socket && window.app.api.socket instanceof WebSocket) {
                socket = window.app.api.socket;
                socketParent = window.app.api;
            }
            
            // If we found a socket, patch its onmessage handler
            if (socket) {
                const originalOnMessage = socket.onmessage;
                socket.onmessage = function(event) {
                    // Call original handler first
                    if (originalOnMessage) {
                        originalOnMessage.call(this, event);
                    }
                    
                    // Then handle for our own messages
                    try {
                        const message = JSON.parse(event.data);
                        if (message.type === 'model_download_progress') {
                            // Forward to our handler
                            if (window.modelDownloader && typeof window.modelDownloader.handleMessageEvent === 'function') {
                                window.modelDownloader.handleMessageEvent(message);
                            }
                        }
                    } catch (e) {
                        // Ignore JSON parse errors
                    }
                };
                console.log("[MODEL_DOWNLOADER] Successfully patched WebSocket handler");
            } else {
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
