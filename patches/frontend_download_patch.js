// Patch for ComfyUI to use backend downloads instead of browser downloads
// This script intercepts the download buttons in the missing models dialog
// and redirects them to use our backend API with progress tracking

(function() {
  console.log('[MODEL_DOWNLOADER] Frontend patch initializing...');

  // Store active downloads
  const activeDownloads = {};

  // Function to check if URL is from a trusted source
  function isTrustedSource(url) {
    const trustedDomains = [
      'civitai.com',
      'huggingface.co'
    ];
    
    try {
      const urlObj = new URL(url);
      const result = trustedDomains.some(domain => urlObj.hostname.includes(domain));
      console.log(`[MODEL_DOWNLOADER] URL check: ${url} is ${result ? 'trusted' : 'not trusted'}`);
      return result;
    } catch (e) {
      console.error('[MODEL_DOWNLOADER] Invalid URL:', url, e);
      return false;
    }
  }

  // Function to handle WebSocket messages for download progress
  function handleWebSocketMessage(event) {
    try {
      const message = JSON.parse(event.data);
      
      // Check if this is a model download progress message
      if (message.type === 'model_download_progress') {
        console.log('[MODEL_DOWNLOADER] Progress update:', message);
        
        const downloadId = message.download_id;
        if (activeDownloads[downloadId]) {
          const download = activeDownloads[downloadId];
          const { progressFill, progressText } = download;
          
          // Update the progress bar
          progressFill.style.width = `${message.percent}%`;
          
          // Format the size nicely
          const totalSizeMB = (message.total_size / (1024 * 1024)).toFixed(2);
          const downloadedMB = (message.downloaded / (1024 * 1024)).toFixed(2);
          
          // Update the progress text based on status
          if (message.status === 'downloading') {
            progressText.textContent = `Downloading: ${downloadedMB} MB / ${totalSizeMB} MB (${message.percent.toFixed(1)}%)`;
          } else if (message.status === 'completed') {
            progressText.textContent = `Download complete: ${totalSizeMB} MB`;
            progressFill.style.backgroundColor = '#2196F3'; // Blue for completion
            
            // After a delay, replace with a success message
            setTimeout(() => {
              if (download.progressContainer.parentNode) {
                const successMessage = document.createElement('div');
                successMessage.className = 'model-download-success';
                successMessage.style.color = '#4CAF50';
                successMessage.style.fontWeight = 'bold';
                successMessage.style.padding = '10px';
                successMessage.style.textAlign = 'center';
                successMessage.textContent = `${message.filename} downloaded successfully!`;
                
                download.progressContainer.parentNode.replaceChild(successMessage, download.progressContainer);
                
                // Remove from active downloads
                delete activeDownloads[downloadId];
                
                // Reload the workflow to use the newly downloaded model
                if (typeof app !== 'undefined' && app.graphToPrompt) {
                  setTimeout(() => {
                    app.graphToPrompt();
                  }, 1000);
                }
              }
            }, 3000);
          } else if (message.status === 'error') {
            progressText.textContent = `Error: ${message.error || 'Unknown error'}`;
            progressFill.style.backgroundColor = '#f44336'; // Red for error
          }
        }
      }
    } catch (error) {
      console.error('[MODEL_DOWNLOADER] Error handling WebSocket message:', error);
    }
  }
    
  // Function to set up WebSocket connection for progress updates
  function setupWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws`;
    
    try {
      // Check if ComfyUI already has a websocket connection we can use
      if (window.app && window.app.api && window.app.api.socket) {
        console.log('[MODEL_DOWNLOADER] Using existing ComfyUI WebSocket connection');
        // Add our message handler to the existing socket
        const originalOnMessage = window.app.api.socket.onmessage;
        window.app.api.socket.onmessage = function(event) {
          // Call the original handler
          if (originalOnMessage) {
            originalOnMessage.call(this, event);
          }
          // Call our handler
          handleWebSocketMessage(event);
        };
      } else {
        // Create our own WebSocket connection
        console.log('[MODEL_DOWNLOADER] Creating new WebSocket connection to', wsUrl);
        const socket = new WebSocket(wsUrl);
        socket.onmessage = handleWebSocketMessage;
        socket.onopen = () => console.log('[MODEL_DOWNLOADER] WebSocket connected');
        socket.onerror = (error) => console.error('[MODEL_DOWNLOADER] WebSocket error:', error);
        socket.onclose = () => console.log('[MODEL_DOWNLOADER] WebSocket disconnected');
      }
    } catch (error) {
      console.error('[MODEL_DOWNLOADER] Error setting up WebSocket:', error);
    }
  }

  // Function to intercept download button clicks
  function interceptDownloadButtons() {
    console.log('[MODEL_DOWNLOADER] Intercepting download buttons...');
    
    // Find all buttons in the missing models dialog
    const buttons = document.querySelectorAll('.p-dialog-content .p-button');
    
    buttons.forEach(button => {
      // Check if this is a download button
      if (button.textContent.includes('Download') || 
          button.classList.contains('p-button-success') ||
          button.getAttribute('aria-label')?.includes('download')) {
          
        console.log('[MODEL_DOWNLOADER] Found download button:', button);
        
        // Add our click handler
        button.addEventListener('click', handleDownloadClick);
      }
    });
  }

    // Function to handle download button clicks
    async function handleDownloadClick(event) {
      // Prevent the default action
      event.preventDefault();
      event.stopPropagation();
      
      console.log('[MODEL_DOWNLOADER] Download button clicked');
      
      // Find the URL, folder, and filename from the dialog
      const dialogContent = event.target.closest('.p-dialog-content');
      if (!dialogContent) {
        console.error('[MODEL_DOWNLOADER] Could not find dialog content');
        return;
      }
      
      // Find the URL from the button or nearby elements
      let url = '';
      let folder = '';
      let filename = '';
      
      // Try to get the URL from the button's href or data attribute
      if (event.target.href) {
        url = event.target.href;
      } else if (event.target.dataset.url) {
        url = event.target.dataset.url;
      } else if (event.target.getAttribute('href')) {
        url = event.target.getAttribute('href');
      }
      
      // If we couldn't find the URL directly, try to find it in the dialog content
      if (!url) {
        // Look for links in the dialog
        const links = dialogContent.querySelectorAll('a');
        for (const link of links) {
          if (link.href && (link.href.includes('civitai.com') || link.href.includes('huggingface.co'))) {
            url = link.href;
            break;
          }
        }
      }
      
      // Try to find the folder and filename from the dialog content
      const text = dialogContent.textContent;
      
      // Extract folder from text like "Folder: checkpoints"
      const folderMatch = text.match(/Folder:\s*([\w-]+)/);
      if (folderMatch && folderMatch[1]) {
        folder = folderMatch[1];
      }
      
      // Extract filename from text like "Filename: v1-5-pruned-emaonly.safetensors"
      const filenameMatch = text.match(/Filename:\s*([\w.-]+)/);
      if (filenameMatch && filenameMatch[1]) {
        filename = filenameMatch[1];
      }
      
      // If we still don't have the filename, try to extract it from the URL
      if (!filename && url) {
        const urlParts = url.split('/');
        filename = urlParts[urlParts.length - 1];
      }
      
      console.log(`[MODEL_DOWNLOADER] URL: ${url}, Folder: ${folder}, Filename: ${filename}`);
      
      if (!url || !folder || !filename) {
        console.error('[MODEL_DOWNLOADER] Missing required information for download');
        return;
      }
      
      // Create a progress element to replace the button
      const button = event.target;
      const buttonParent = button.parentElement;
      
      // Create a container for our progress display
      const progressContainer = document.createElement('div');
      progressContainer.className = 'model-download-progress';
      progressContainer.style.width = '100%';
      progressContainer.style.marginTop = '10px';
      progressContainer.style.marginBottom = '10px';
      
      // Create the progress bar
      const progressBar = document.createElement('div');
      progressBar.className = 'model-download-progress-bar';
      progressBar.style.width = '100%';
      progressBar.style.height = '20px';
      progressBar.style.backgroundColor = '#f0f0f0';
      progressBar.style.borderRadius = '4px';
      progressBar.style.overflow = 'hidden';
      
      // Create the progress fill
      const progressFill = document.createElement('div');
      progressFill.className = 'model-download-progress-fill';
      progressFill.style.width = '0%';
      progressFill.style.height = '100%';
      progressFill.style.backgroundColor = '#4CAF50';
      progressFill.style.transition = 'width 0.3s';
      
      // Create the progress text
      const progressText = document.createElement('div');
      progressText.className = 'model-download-progress-text';
      progressText.style.textAlign = 'center';
      progressText.style.marginTop = '5px';
      progressText.style.fontSize = '14px';
      progressText.textContent = 'Starting download...';
      
      // Add the elements to the container
      progressBar.appendChild(progressFill);
      progressContainer.appendChild(progressBar);
      progressContainer.appendChild(progressText);
      
      // Replace the button with our progress container
      buttonParent.replaceChild(progressContainer, button);
      
      // Make a request to our backend API to download the model
      try {
        const response = await fetch('/api/download-model', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            url,
            folder,
            filename
          })
        });
        
        const data = await response.json();
        
        if (data.success) {
          console.log('[MODEL_DOWNLOADER] Download started successfully, ID:', data.download_id);
          
          // Store the download info
          activeDownloads[data.download_id] = {
            progressFill,
            progressText,
            progressContainer,
            filename,
            folder
          };
        } else {
          console.error('[MODEL_DOWNLOADER] Download failed:', data.error);
          progressText.textContent = `Download failed: ${data.error}`;
          progressFill.style.backgroundColor = '#f44336'; // Red for error
        }
      } catch (error) {
        console.error('[MODEL_DOWNLOADER] Error starting download:', error);
        progressText.textContent = `Error: ${error.message}`;
        progressFill.style.backgroundColor = '#f44336'; // Red for error
      }
    }



    // Function to patch download buttons in the missing models dialog
    function patchMissingModelsDialog() {
      console.log('[MODEL_DOWNLOADER] Setting up observer for missing models dialog...');
      
      // Watch for the missing models dialog to appear
      const observer = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
          if (mutation.addedNodes.length) {
            for (const node of mutation.addedNodes) {
              if (node.nodeType === Node.ELEMENT_NODE) {
                // Look for elements that might contain the missing models dialog
                // The class name might vary depending on ComfyUI version
                const dialog = node.querySelector('.missing-models-dialog') || 
                              node.querySelector('.comfy-missing-models') || 
                              node.querySelector('.p-dialog-content') || 
                              (node.classList && (node.classList.contains('missing-models-dialog') || 
                                                 node.classList.contains('p-dialog'))) ? node : null;
                
                if (dialog) {
                  console.log('[MODEL_DOWNLOADER] Found potential dialog:', dialog);
                  
                  // Check if it's actually a missing models dialog by looking for text content
                  if (dialog.textContent && dialog.textContent.includes('Missing Models')) {
                    console.log('[MODEL_DOWNLOADER] Confirmed missing models dialog!');
                    
                    // Give a short delay to ensure all elements are rendered
                    setTimeout(() => {
                      interceptDownloadButtons();
                      
                      // Also try to find buttons in any child dialogs
                      const childDialogs = dialog.querySelectorAll('.p-dialog-content, .dialog-content');
                      childDialogs.forEach(childDialog => {
                        console.log('[MODEL_DOWNLOADER] Found child dialog, patching buttons');
                        interceptDownloadButtons();
                      });
                    }, 100);
                  }
                }
              }
            }
          }
        }
      });
      
      // Start observing the document body for changes
      observer.observe(document.body, { childList: true, subtree: true });
      console.log('[MODEL_DOWNLOADER] Observer started');
    }
    

  // Function to patch missing models dialog
  function patchMissingModelsDialog() {
    console.log('[MODEL_DOWNLOADER] Setting up observer for missing models dialog...');
    
    // Watch for the missing models dialog to appear
    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.addedNodes.length) {
          for (const node of mutation.addedNodes) {
            if (node.nodeType === Node.ELEMENT_NODE) {
              // Look for elements that might contain the missing models dialog
              // The class name might vary depending on ComfyUI version
              const dialog = node.querySelector('.missing-models-dialog') || 
                            node.querySelector('.comfy-missing-models') || 
                            node.querySelector('.p-dialog-content') || 
                            (node.classList && (node.classList.contains('missing-models-dialog') || 
                                               node.classList.contains('p-dialog'))) ? node : null;
              
              if (dialog) {
                console.log('[MODEL_DOWNLOADER] Found potential dialog:', dialog);
                
                // Check if it's actually a missing models dialog by looking for text content
                if (dialog.textContent && dialog.textContent.includes('Missing Models')) {
                  console.log('[MODEL_DOWNLOADER] Confirmed missing models dialog!');
                  
                  // Give a short delay to ensure all elements are rendered
                  setTimeout(() => {
                    interceptDownloadButtons();
                    
                    // Also try to find buttons in any child dialogs
                    const childDialogs = dialog.querySelectorAll('.p-dialog-content, .dialog-content');
                    childDialogs.forEach(childDialog => {
                      console.log('[MODEL_DOWNLOADER] Found child dialog, patching buttons');
                      interceptDownloadButtons();
                    });
                  }, 100);
                }
              }
            }
          }
        }
      }
    });
    
    // Start observing the document body for changes
    observer.observe(document.body, { childList: true, subtree: true });
    console.log('[MODEL_DOWNLOADER] Observer started');
  }

  // Main initialization function
  function initModelDownloader() {
    console.log('[MODEL_DOWNLOADER] Initializing model downloader patch...');
    
    // Setup WebSocket for progress updates
    setupWebSocket();
    
    // Initialize the dialog observer
    patchMissingModelsDialog();
    
    console.log('[MODEL_DOWNLOADER] Model downloader patch initialized');
  }

  // Start the initialization when the document is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initModelDownloader);
  } else {
    initModelDownloader();
  }

  console.log('[MODEL_DOWNLOADER] Frontend patch loaded');
})();

// Log that the patch has been loaded
console.log("ComfyUI backend download patch loaded with progress tracking");
