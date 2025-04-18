// ComfyUI Model Downloader Extension
console.log("[MODEL_DOWNLOADER] Loading model downloader extension...");

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
    console.log("[MODEL_DOWNLOADER] Model downloader extension initializing...");
    loadMainScript();
    console.log("[MODEL_DOWNLOADER] Model downloader extension initialized");
}

// Wait for DOMContentLoaded to ensure the document is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', registerModelDownloader);
} else {
    registerModelDownloader();
}
