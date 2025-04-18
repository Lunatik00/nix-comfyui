// Model Downloader Core Functionality
// This file contains the core functionality for downloading models

(function() {
  // Map to store active downloads
  const activeDownloads = {};
  
  // List of trusted domains for model downloads
  const trustedDomains = [
    'huggingface.co',
    'civitai.com',
    'github.com',
    'cdn.discordapp.com',
    'pixeldrain.com',
    'replicate.delivery'
  ];
  
  // Check if a URL is from a trusted domain
  function isTrustedDomain(url) {
    try {
      const urlObj = new URL(url);
      return trustedDomains.some(domain => urlObj.hostname === domain || urlObj.hostname.endsWith('.' + domain));
    } catch (e) {
      console.error('[MODEL_DOWNLOADER] Error parsing URL:', e);
      return false;
    }
  }
  
  // Function to download model using backend API
  async function downloadModelWithBackend(url, folder, filename) {
    console.log(`[MODEL_DOWNLOADER] Downloading model: ${filename} to folder: ${folder} from URL: ${url}`);
    
    // Create a unique download ID before we even start the request
    // This ensures we can show UI immediately
    const clientDownloadId = `${folder}_${filename}_${Date.now()}`;
    
    // Create an initial progress UI immediately
    const initialProgress = {
      filename: filename,
      folder: folder,
      total_size: 1000000, // Placeholder size until we get real data
      downloaded: 0,
      percent: 0,
      status: 'starting',
      client_id: clientDownloadId
    };
    
    // Store the download in our active downloads map
    activeDownloads[clientDownloadId] = initialProgress;
    
    // Show UI
    if (window.modelDownloaderUI && window.modelDownloaderUI.createOrUpdateProgressUI) {
      window.modelDownloaderUI.createOrUpdateProgressUI(clientDownloadId, initialProgress);
    } else {
      console.warn('[MODEL_DOWNLOADER] UI module not loaded, cannot show progress');
    }
    
    try {
      // Prepare request data
      const formData = new FormData();
      formData.append('url', url);
      formData.append('folder', folder);
      
      if (filename) {
        formData.append('filename', filename);
      }
      
      // Add client download ID so we can track this download
      formData.append('client_id', clientDownloadId);
      
      // Make the request
      const response = await fetch('/api/download-model', {
        method: 'POST',
        body: formData
      });
      
      console.log(`[MODEL_DOWNLOADER] Server response status: ${response.status}`);
      
      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Server responded with ${response.status}: ${errorText}`);
      }
      
      const result = await response.json();
      
      if (result.success) {
        console.log(`[MODEL_DOWNLOADER] Download started: ${result.filename}`);
        
        // Update the progress info
        activeDownloads[clientDownloadId].status = 'downloading';
        if (result.id) {
          activeDownloads[clientDownloadId].server_id = result.id;
        }
        if (result.filename) {
          activeDownloads[clientDownloadId].filename = result.filename;
        }
        
        // Update the UI
        if (window.modelDownloaderUI && window.modelDownloaderUI.createOrUpdateProgressUI) {
          window.modelDownloaderUI.createOrUpdateProgressUI(clientDownloadId, activeDownloads[clientDownloadId]);
        }
        
        // Start polling for progress
        if (window.modelDownloaderProgress && window.modelDownloaderProgress.startPolling) {
          window.modelDownloaderProgress.startPolling(clientDownloadId);
        }
      } else if (result.error) {
        throw new Error(result.error);
      }
      
      return result;
    } catch (error) {
      console.error('[MODEL_DOWNLOADER] Download error:', error);
      
      // Update UI to show error
      activeDownloads[clientDownloadId].status = 'error';
      activeDownloads[clientDownloadId].error = error.message;
      
      if (window.modelDownloaderUI && window.modelDownloaderUI.createOrUpdateProgressUI) {
        window.modelDownloaderUI.createOrUpdateProgressUI(clientDownloadId, activeDownloads[clientDownloadId]);
      }
      
      throw error;
    }
  }
  
  // Patch the download buttons in the missing models dialog
  function patchMissingModelButtons() {
    console.log('[MODEL_DOWNLOADER] Patching missing model buttons...');
    
    // Selectors for finding dialogs and buttons
    const dialogSelectors = [
      '.p-dialog.global-dialog',  // ComfyUI missing models dialog
      '.p-dialog',                // Any PrimeVue dialog
      '#nodes-modal',            // Old-style ComfyUI modal
      'div[role="dialog"]',      // Generic dialog role
      '.p-dialog-content',       // PrimeVue dialog content
      '.dialog'                  // Generic dialog class
    ];
    
    const buttonSelectors = [
      '.p-button[title*="http"]',                 // PrimeVue buttons with URL in title
      'button[title*="http"]',                    // Regular buttons with URL in title
      '.comfy-missing-models button',             // Buttons in missing models list
      '.p-listbox.comfy-missing-models .p-button', // ListBox buttons
      'button:not([data-model-downloader-patched])', // Any button not already patched
      '.p-button',                                // Any PrimeVue button
      'a.p-button',                              // PrimeVue button links
      '.p-dialog button'                         // Any button in a dialog
    ];
    
    // Combined selectors
    const dialogSelector = dialogSelectors.join(', ');
    const buttonSelector = buttonSelectors.join(', ');
    
    console.log('[MODEL_DOWNLOADER] Dialog selectors:', dialogSelector);
    console.log('[MODEL_DOWNLOADER] Button selectors:', buttonSelector);
    
    // Function to find and patch all download buttons
    function patchAllButtons() {
      console.log('[MODEL_DOWNLOADER] Scanning for missing model dialogs...');
      let patchedCount = 0;
      
      // Find all dialogs that could be missing models dialogs
      document.querySelectorAll(dialogSelector).forEach(dialog => {
        // Check if this looks like a missing models dialog
        if (dialog.textContent && dialog.textContent.includes('Missing Models')) {
          console.log('[MODEL_DOWNLOADER] Found Missing Models dialog:', dialog);
          
          // Find all potential download buttons in this dialog
          const buttons = dialog.querySelectorAll(buttonSelector);
          console.log(`[MODEL_DOWNLOADER] Found ${buttons.length} potential download buttons in dialog`);
          
          // Process each button
          buttons.forEach(button => {
            // Skip already patched buttons
            if (button.hasAttribute('data-model-downloader-patched')) {
              return;
            }
            
            // Check if this looks like a download button
            const buttonText = button.textContent || '';
            const buttonTitle = button.getAttribute('title') || '';
            
            // More permissive detection of download buttons
            // Either has 'Download' in text or is a button in a Missing Models dialog
            if (buttonText.includes('Download') || 
                (button.tagName === 'BUTTON' && dialog.textContent.includes('Missing Models'))) {
              console.log('[MODEL_DOWNLOADER] Found download button with text:', buttonText);
              console.log('[MODEL_DOWNLOADER] Found download button:', button);
              
              // Mark button as patched
              button.setAttribute('data-model-downloader-patched', 'true');
              
              // Extract information from the dialog
              let modelUrl = buttonTitle;
              let folderName = '';
              let fileName = '';
              
              // Try multiple sources to find the URL
              if (!modelUrl.includes('http')) {
                // Look for href attributes that might contain the URL
                const closestLink = button.closest('a[href]');
                if (closestLink && closestLink.href.includes('http')) {
                  modelUrl = closestLink.href;
                  console.log(`[MODEL_DOWNLOADER] Found URL in parent link: ${modelUrl}`);
                } else {
                  // Look for text that resembles a URL in the dialog
                  const dialogText = dialog.textContent;
                  const urlMatch = dialogText.match(/(https?:\/\/[^\s]+)/);
                  if (urlMatch) {
                    modelUrl = urlMatch[0];
                    console.log(`[MODEL_DOWNLOADER] Extracted URL from text: ${modelUrl}`);
                  }
                }
              }
              
              // Try to find the folder/filename information
              const listItem = button.closest('li');
              if (listItem) {
                // Look for a span with title that might contain path info
                const pathSpan = listItem.querySelector('span[title]');
                if (pathSpan) {
                  const pathText = pathSpan.textContent;
                  if (pathText && pathText.includes('/')) {
                    const parts = pathText.split('/');
                    folderName = parts[0].trim();
                    fileName = parts.slice(1).join('/').trim();
                    console.log(`[MODEL_DOWNLOADER] Extracted path: ${folderName}/${fileName}`);
                  }
                }
              }
              
              // If we still don't have a filename, extract from URL
              if (!fileName && modelUrl && modelUrl.includes('http')) {
                try {
                  const urlObj = new URL(modelUrl);
                  const pathParts = urlObj.pathname.split('/');
                  fileName = pathParts[pathParts.length - 1] || 'downloaded_model';
                  console.log(`[MODEL_DOWNLOADER] Extracted filename from URL: ${fileName}`);
                } catch (e) {
                  console.error('[MODEL_DOWNLOADER] Error parsing URL:', e);
                }
              }
              
              // Fallback for folder name
              if (!folderName) {
                // Look for common model folder names in the dialog text
                const dialogText = dialog.textContent.toLowerCase();
                const folderHints = ['checkpoints', 'loras', 'vae', 'upscale', 'controlnet', 'embedding', 'clip'];
                
                for (const hint of folderHints) {
                  if (dialogText.includes(hint)) {
                    folderName = hint;
                    console.log(`[MODEL_DOWNLOADER] Detected folder type from context: ${folderName}`);
                    break;
                  }
                }
              }
              
              // Store original button state and extracted info
              const originalOnClick = button.onclick;
              const originalText = button.textContent;
              
              // Store download info on the button element
              button.dataset.modelUrl = modelUrl;
              button.dataset.folderName = folderName;
              button.dataset.fileName = fileName;
              
              // Create download handler function
              const downloadHandler = function(e) {
                // Prevent default browser download behavior
                if (e) {
                  e.preventDefault();
                  e.stopPropagation();
                }
                
                console.log('[MODEL_DOWNLOADER] Download button clicked');
                console.log('[MODEL_DOWNLOADER] Button text:', button.textContent);
                console.log('[MODEL_DOWNLOADER] Button title:', button.title);
                console.log('[MODEL_DOWNLOADER] Button href:', button.href);
                console.log('[MODEL_DOWNLOADER] Button dataset:', button.dataset);
                
                // Get stored info from the button
                const url = button.dataset.modelUrl;
                let folder = button.dataset.folderName;
                let filename = button.dataset.fileName;
                
                // Show we're downloading
                button.textContent = 'Downloading...';
                button.disabled = true;
                
                // Prompt for missing info if needed
                if (!url) {
                  alert('Could not determine download URL. Please download manually.');
                  button.textContent = originalText;
                  button.disabled = false;
                  return;
                }
                
                if (!folder) {
                  folder = prompt('Please specify the model folder type:', 'checkpoints');
                  if (!folder) {
                    button.textContent = originalText;
                    button.disabled = false;
                    return;
                  }
                }
                
                // Call our backend download API
                downloadModelWithBackend(url, folder, filename)
                  .catch(error => {
                    console.error('[MODEL_DOWNLOADER] Download error:', error);
                    button.textContent = originalText;
                    button.disabled = false;
                    alert(`Download failed: ${error.message}`);
                  });
              };
              
              // Override the button's click behavior
              button.onclick = downloadHandler;
              
              // Also use an event listener as a backup approach
              button.addEventListener('click', downloadHandler, true);
              
              // Update button text
              button.textContent = 'Download with Model Downloader';
              
              // Count patched buttons
              patchedCount++;
            }
          });
        }
      });
      
      console.log(`[MODEL_DOWNLOADER] Patched ${patchedCount} download buttons`);
    }
    
    // Patch immediately once
    patchAllButtons();
    
    // Set up mutation observer to catch dynamically created dialogs
    const observer = new MutationObserver(function(mutations) {
      for (const mutation of mutations) {
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          for (const node of mutation.addedNodes) {
            if (node.nodeType === Node.ELEMENT_NODE) {
              // Check if this node or any of its children match our dialog selectors
              if ((node.matches && node.matches(dialogSelector)) || 
                  (node.querySelector && node.querySelector(dialogSelector))) {
                console.log('[MODEL_DOWNLOADER] New dialog detected via mutation observer:', node);
                patchAllButtons();
                return;
              }
              
              // Or if it has "Missing Models" in its text content
              if (node.textContent && node.textContent.includes('Missing Models')) {
                console.log('[MODEL_DOWNLOADER] Missing Models dialog detected via text content:', node);
                patchAllButtons();
                return;
              }
            }
          }
        }
      }
    });
    
    // Observe the entire document body for changes
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['style', 'class']
    });
    
    console.log('[MODEL_DOWNLOADER] Mutation observer set up for dialog detection');
    
    // Also poll occasionally for dialogs that might have been missed
    const pollInterval = setInterval(function() {
      const dialogs = document.querySelectorAll(dialogSelector);
      for (const dialog of dialogs) {
        if (dialog.textContent && dialog.textContent.includes('Missing Models')) {
          console.log('[MODEL_DOWNLOADER] Missing Models dialog found via polling');
          patchAllButtons();
          return;
        }
      }
    }, 2000); // Poll every 2 seconds
  }
  
  // Define initialize function
  function initialize() {
    console.log('[MODEL_DOWNLOADER] Initializing core module...');
    
    // Initialize the WebSocket listener for progress updates
    if (window.modelDownloaderProgress && window.modelDownloaderProgress.setupWebSocketListener) {
      window.modelDownloaderProgress.setupWebSocketListener();
    } else {
      console.warn('[MODEL_DOWNLOADER] Progress module not loaded or setupWebSocketListener not found');
    }
    
    // Patch the missing model buttons
    patchMissingModelButtons();
    
    // Check if DOM is already loaded
    if (document.readyState === 'loading') {
      // If not, wait for it to load
      document.addEventListener('DOMContentLoaded', () => {
        console.log('[MODEL_DOWNLOADER] DOM loaded, patching...');
        patchMissingModelButtons();
      });
    } else {
      console.log('[MODEL_DOWNLOADER] DOM already loaded, patching immediately');
      patchMissingModelButtons();
    }
    
    console.log('[MODEL_DOWNLOADER] Core module initialized successfully!');
    return true;
  }

  // Expose functions and data to global scope
  // First, create the core object
  window.modelDownloaderCore = {
    isTrustedDomain: isTrustedDomain,
    downloadModelWithBackend: downloadModelWithBackend,
    patchMissingModelButtons: patchMissingModelButtons,
    initialize: initialize
  };
  
  // Make sure modelDownloader exists before assigning to it
  if (!window.modelDownloader) {
    console.log('[MODEL_DOWNLOADER] Creating window.modelDownloader object');
    window.modelDownloader = {
      activeDownloads: {}
    };
  }
  
  // Add core functions to the main modelDownloader object
  Object.assign(window.modelDownloader, window.modelDownloaderCore);
  
  // Do NOT call initialize automatically - let backend_download.js call it
  console.log('[MODEL_DOWNLOADER] Core module loaded and ready');
})();

console.log('[MODEL_DOWNLOADER] Core module loaded');
