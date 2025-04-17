// Patch for ComfyUI to use backend downloads instead of browser downloads
// This script intercepts the download buttons in the missing models dialog
// and redirects them to use our backend API

(function() {
  console.log('[MODEL_DOWNLOADER] Frontend patch initializing...');

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

  // Function to download model using backend API
  async function downloadModelWithBackend(url, folder, filename) {
    console.log(`[MODEL_DOWNLOADER] Downloading model: ${filename} to folder: ${folder} from URL: ${url}`);
    
    try {
      const response = await fetch('/api/download-model', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          url: url,
          folder: folder,
          filename: filename
        }),
      });
      
      console.log(`[MODEL_DOWNLOADER] Server response status: ${response.status}`);
      
      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Server responded with ${response.status}: ${errorText}`);
      }
      
      const result = await response.json();
      console.log('[MODEL_DOWNLOADER] Download result:', result);
      
      if (result.success) {
        console.log('[MODEL_DOWNLOADER] Model downloaded successfully!');
        alert(`Model ${filename} downloaded successfully!`);
        // Reload the workflow to use the newly downloaded model
        if (typeof app !== 'undefined' && app.graphToPrompt) {
          app.graphToPrompt();
        } else {
          console.error('[MODEL_DOWNLOADER] Cannot reload workflow: app or app.graphToPrompt is undefined');
          // Try to reload the page as a fallback
          window.location.reload();
        }
      } else {
        console.error('[MODEL_DOWNLOADER] Failed to download model:', result.error);
        alert(`Failed to download model: ${result.error}`);
      }
    } catch (error) {
      console.error('[MODEL_DOWNLOADER] Error downloading model:', error);
      alert(`Error downloading model: ${error.message}`);
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
                    patchDownloadButtons(dialog);
                    
                    // Also try to find buttons in any child dialogs
                    const childDialogs = dialog.querySelectorAll('.p-dialog-content, .dialog-content');
                    childDialogs.forEach(childDialog => {
                      console.log('[MODEL_DOWNLOADER] Found child dialog, patching buttons');
                      patchDownloadButtons(childDialog);
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
  
  // Function to patch download buttons
  function patchDownloadButtons(dialog) {
    console.log('[MODEL_DOWNLOADER] Looking for download buttons in dialog...');
    
    // Find all buttons in the dialog
    const buttons = dialog.querySelectorAll('button');
    console.log(`[MODEL_DOWNLOADER] Found ${buttons.length} buttons in dialog`);
    
    buttons.forEach(button => {
      // Check if this is a download button
      if (button.textContent && button.textContent.includes('Download')) {
        console.log('[MODEL_DOWNLOADER] Found download button:', button.textContent);
        
        // Try to find the model information
        let url, folder, filename;
        
        // Get URL from title attribute (specific to the PrimeVue button structure)
        url = button.getAttribute('title');
        console.log('[MODEL_DOWNLOADER] Button title URL:', url);
        
        // Find the model info in the parent listbox option
        const listItem = button.closest('li') || button.closest('.p-listbox-option');
        if (listItem) {
          // Look for the span with the model path
          const modelPathSpan = listItem.querySelector('span[title]');
          if (modelPathSpan) {
            const modelPathText = modelPathSpan.textContent;
            console.log('[MODEL_DOWNLOADER] Model path text:', modelPathText);
            
            // Parse the model path (format: "folder / filename")
            const parts = modelPathText.split(' / ');
            if (parts.length === 2) {
              folder = parts[0].trim();
              filename = parts[1].trim();
              console.log(`[MODEL_DOWNLOADER] Parsed path: folder=${folder}, filename=${filename}`);
            }
          }
        }
        
        // If we still don't have the info, try other methods
        if (!url || !folder || !filename) {
          // Try to extract from parent element text content
          const parentElement = button.closest('.flex') || button.closest('.p-listbox-option');
          if (parentElement) {
            const text = parentElement.textContent;
            console.log('[MODEL_DOWNLOADER] Parent text:', text);
            
            // Extract filename from text
            const filenameMatch = text.match(/([\w-]+\.(safetensors|ckpt|pt|bin|pth))/);
            if (filenameMatch) {
              filename = filenameMatch[1];
              console.log('[MODEL_DOWNLOADER] Extracted filename:', filename);
            }
            
            // Try to determine folder from context
            if (text.includes('checkpoint') || text.includes('checkpoints')) {
              folder = 'checkpoints';
            } else if (text.includes('vae')) {
              folder = 'vae';
            } else if (text.includes('lora')) {
              folder = 'loras';
            } else if (text.includes('embedding')) {
              folder = 'embeddings';
            } else if (text.includes('controlnet')) {
              folder = 'controlnet';
            } else if (text.includes('upscale')) {
              folder = 'upscale_models';
            }
          }
        }
        
        console.log(`[MODEL_DOWNLOADER] Final extracted data: filename=${filename}, folder=${folder}, url=${url}`);
        
        if (url && folder && filename) {
          console.log(`[MODEL_DOWNLOADER] Button has data: ${filename} in ${folder} from ${url}`);
          
          // Create a completely new click handler that replaces the original
          // This is more reliable than trying to modify the existing one
          const newClickHandler = function(event) {
            console.log('[MODEL_DOWNLOADER] Download button clicked');
            event.preventDefault();
            event.stopPropagation();
            
            if (isTrustedSource(url)) {
              console.log('[MODEL_DOWNLOADER] Using backend download for', filename);
              downloadModelWithBackend(url, folder, filename);
              return false;
            } else {
              console.log('[MODEL_DOWNLOADER] URL not trusted, falling back to browser download');
              return true; // Allow default behavior
            }
          };
          
          // Remove existing click handlers
          const clonedButton = button.cloneNode(true);
          button.parentNode.replaceChild(clonedButton, button);
          
          // Add our new click handler
          clonedButton.addEventListener('click', newClickHandler, true);
          
          // Mark as patched
          clonedButton.dataset.patched = 'true';
          
          console.log('[MODEL_DOWNLOADER] Button completely replaced with patched version');
        } else {
          console.log('[MODEL_DOWNLOADER] Button missing required data, using fallback method');
          
          // Fallback: Create a new button that completely replaces the original
          const clonedButton = button.cloneNode(true);
          button.parentNode.replaceChild(clonedButton, button);
          
          clonedButton.addEventListener('click', function(event) {
            console.log('[MODEL_DOWNLOADER] Fallback button clicked');
            
            // Try to extract URL from the button or its attributes
            let extractedUrl = clonedButton.getAttribute('title') || clonedButton.getAttribute('href');
            
            if (!extractedUrl) {
              console.log('[MODEL_DOWNLOADER] No URL found, allowing default behavior');
              return true;
            }
            
            // Try to extract filename from URL
            let extractedFilename = '';
            let extractedFolder = '';
            
            // Extract filename from URL
            const urlObj = new URL(extractedUrl);
            const pathParts = urlObj.pathname.split('/');
            extractedFilename = pathParts[pathParts.length - 1];
            
            // Clean up filename (remove query parameters)
            if (extractedFilename.includes('?')) {
              extractedFilename = extractedFilename.split('?')[0];
            }
            
            // Try to determine folder from context
            const parentText = clonedButton.closest('.flex') ? clonedButton.closest('.flex').textContent : '';
            if (parentText.includes('checkpoint') || parentText.includes('checkpoints')) {
              extractedFolder = 'checkpoints';
            } else if (parentText.includes('vae')) {
              extractedFolder = 'vae';
            } else if (extractedFilename.includes('vae')) {
              extractedFolder = 'vae';
            } else {
              extractedFolder = 'checkpoints'; // Default to checkpoints
            }
            
            console.log(`[MODEL_DOWNLOADER] Fallback extracted: ${extractedFilename} in ${extractedFolder} from ${extractedUrl}`);
            
            if (isTrustedSource(extractedUrl) && extractedFolder && extractedFilename) {
              downloadModelWithBackend(extractedUrl, extractedFolder, extractedFilename);
              event.preventDefault();
              event.stopPropagation();
              return false;
            }
            
            console.log('[MODEL_DOWNLOADER] Fallback extraction failed, allowing default behavior');
            return true;
          }, true);
          
          // Mark as patched
          clonedButton.dataset.patched = 'true';
          console.log('[MODEL_DOWNLOADER] Fallback button replacement complete');
        }
      }
    });
  }
  
  // Initialize the patch
  console.log('[MODEL_DOWNLOADER] Starting patch initialization');
  
  // Wait for the DOM to be fully loaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', patchMissingModelsDialog);
    console.log('[MODEL_DOWNLOADER] Waiting for DOMContentLoaded event');
  } else {
    patchMissingModelsDialog();
    console.log('[MODEL_DOWNLOADER] DOM already loaded, patching immediately');
  }
  
  console.log('[MODEL_DOWNLOADER] Frontend patch loaded successfully!');
})();

// Log that the patch has been loaded
console.log("ComfyUI backend download patch loaded");
