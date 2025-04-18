// ComfyUI Model Downloader Frontend Patch
// This script is the main entry point for the model downloader frontend patch
// It loads the modular components and initializes the downloader

(function() {
  console.log('[MODEL_DOWNLOADER] Frontend patch initializing...');
  
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
      console.error(`[MODEL_DOWNLOADER] Error loading script ${url}:`, error);
    };
    document.head.appendChild(script);
  }

  // Load the modules in sequence
  function loadModules() {
    // Get the current script path to determine the base path
    const scripts = document.getElementsByTagName('script');
    let basePath = '';
    
    // First try to find the current script
    for (const script of scripts) {
      if (script.src && (script.src.includes('backend_download.js') || script.src.includes('model_downloader') || script.src.includes('download'))) {
        basePath = script.src.substring(0, script.src.lastIndexOf('/') + 1);
        console.log('[MODEL_DOWNLOADER] Found script path:', script.src);
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
      console.log('[MODEL_DOWNLOADER] Using ComfyUI extensions path:', basePath);
    }
    
    console.log('[MODEL_DOWNLOADER] Base path for modules:', basePath);
    
    // Load the UI module first with absolute paths
    const uiPath = basePath + 'model_downloader_ui.js';
    console.log('[MODEL_DOWNLOADER] Loading UI module from:', uiPath);
    loadScript(uiPath, function() {
      console.log('[MODEL_DOWNLOADER] UI module loaded, loading progress module...');
      
      // Then load the progress tracking module
      const progressPath = basePath + 'model_downloader_progress.js';
      console.log('[MODEL_DOWNLOADER] Loading progress module from:', progressPath);
      loadScript(progressPath, function() {
        console.log('[MODEL_DOWNLOADER] Progress module loaded, loading core module...');
        
        // Finally load the core module and initialize
        const corePath = basePath + 'model_downloader_core.js';
        console.log('[MODEL_DOWNLOADER] Loading core module from:', corePath);
        loadScript(corePath, function() {
          console.log('[MODEL_DOWNLOADER] All modules loaded, initializing...');
          
          // Initialize the downloader once all modules are loaded
          if (window.modelDownloader && window.modelDownloader.initialize) {
            window.modelDownloader.initialize();
          } else {
            console.error('[MODEL_DOWNLOADER] Failed to initialize: modelDownloader.initialize not found');
          }
        });
      });
    });
  }
    
  // Start loading modules
  loadModules();
  
  console.log('[MODEL_DOWNLOADER] Frontend patch loaded successfully!');
})();
