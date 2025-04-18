// ComfyUI Model Downloader Frontend Patch
// This script is the main entry point for the model downloader frontend patch
// It loads the core component and initializes the downloader

(function() {
  // Initialize the global modelDownloader object if it doesn't exist
  if (!window.modelDownloader) {
    window.modelDownloader = {
      activeDownloads: {}
    };
  }
  
  // Define a function to dynamically load JavaScript files with proper error handling
  function loadScript(url, callback) {
    console.log(`[MODEL_DOWNLOADER] Loading script from: ${url}`);
    const script = document.createElement('script');
    script.type = 'text/javascript';
    script.src = url;
    script.onload = function() {
      console.log(`[MODEL_DOWNLOADER] Successfully loaded: ${url}`);
      if (typeof callback === 'function') callback();
    };
    script.onerror = function(error) {
      console.error(`[MODEL_DOWNLOADER] Error loading script from ${url}:`, error);
    };
    document.head.appendChild(script);
  }

  // Determine the base path for loading modules
  function getBasePath() {
    // Try to find the current script path
    const scripts = document.getElementsByTagName('script');
    for (const script of scripts) {
      if (script.src && script.src.includes('backend_download.js')) {
        return script.src.substring(0, script.src.lastIndexOf('/') + 1);
      }
    }
    
    // If not found, try to find any model_downloader script
    for (const script of scripts) {
      if (script.src && script.src.includes('model_downloader')) {
        return script.src.substring(0, script.src.lastIndexOf('/') + 1);
      }
    }
    
    // Fallback to extensions path based on current URL
    const currentUrl = window.location.href;
    const urlObj = new URL(currentUrl);
    return `${urlObj.protocol}//${urlObj.host}/extensions/model_downloader/`;
  }

  // Load the core module and initialize the downloader
  function loadCoreModule() {
    const basePath = getBasePath();
    const corePath = basePath + 'model_downloader_core.js';
    
    loadScript(corePath, function() {
      // Initialize the downloader once loaded
      if (window.modelDownloader && typeof window.modelDownloader.initialize === 'function') {
        console.log('[MODEL_DOWNLOADER] Initializing model downloader...');
        window.modelDownloader.initialize();
      } else {
        console.error('[MODEL_DOWNLOADER] Failed to initialize - core module not properly loaded');
      }
    });
  }
  
  // Start loading the core module
  loadCoreModule();
})();