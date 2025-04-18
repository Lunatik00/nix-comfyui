// ComfyUI Model Downloader Frontend Patch
// This script is the main entry point for the model downloader frontend patch
// It loads the core component and initializes the downloader

(function() {
  // Initialize the global modelDownloader object
  window.modelDownloader = {
    activeDownloads: {}
  };
  
  // Define a function to dynamically load JavaScript files
  function loadScript(url, callback) {
    const script = document.createElement('script');
    script.type = 'text/javascript';
    script.src = url;
    script.onload = callback;
    script.onerror = (error) => {
      // Error loading script (silent in production)
    };
    document.head.appendChild(script);
  }

  // Load the core module
  function loadModules() {
    // Get the current script path to determine the base path
    const scripts = document.getElementsByTagName('script');
    let basePath = '';
    
    // First try to find the current script
    for (const script of scripts) {
      if (script.src && (script.src.includes('backend_download.js') || script.src.includes('model_downloader') || script.src.includes('download'))) {
        basePath = script.src.substring(0, script.src.lastIndexOf('/') + 1);
        break;
      }
    }
    
    // If still not found, determine base path from window location
    if (!basePath) {
      // Try to derive it from the current page URL
      const currentUrl = window.location.href;
      const urlObj = new URL(currentUrl);
      
      // Use the extensions path which is how ComfyUI serves custom node files
      basePath = `${urlObj.protocol}//${urlObj.host}/extensions/model_downloader/`;
    }
    
    // Load the core module
    const corePath = basePath + 'model_downloader_core.js';
    loadScript(corePath, function() {
      // Initialize the downloader once loaded
      if (window.modelDownloader && window.modelDownloader.initialize) {
        window.modelDownloader.initialize();
      }
    });
  }
    
  // Start loading modules
  loadModules();
})();