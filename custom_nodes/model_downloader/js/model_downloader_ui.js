// Model Downloader UI Component
// This file contains UI-related functions for the model downloader

(function() {
  // Create a container for download progress indicators
  function getOrCreateProgressContainer() {
    let container = document.getElementById('model-downloads-container');
    
    if (!container) {
      // Create the container
      container = document.createElement('div');
      container.id = 'model-downloads-container';
      container.style.position = 'fixed';
      container.style.bottom = '20px';
      container.style.right = '20px';
      container.style.width = '300px';
      container.style.maxHeight = '80vh';
      container.style.overflowY = 'auto';
      container.style.backgroundColor = 'rgba(30, 30, 30, 0.9)';
      container.style.borderRadius = '5px';
      container.style.padding = '10px';
      container.style.boxShadow = '0 0 10px rgba(0, 0, 0, 0.5)';
      container.style.zIndex = '9999';
      container.style.color = 'white';
      container.style.fontFamily = 'Arial, sans-serif';
      
      // Add a header
      const header = document.createElement('div');
      header.style.fontWeight = 'bold';
      header.style.marginBottom = '10px';
      header.style.borderBottom = '1px solid rgba(255, 255, 255, 0.3)';
      header.style.paddingBottom = '5px';
      header.textContent = 'Model Downloads';
      container.appendChild(header);
      
      // Add to the document
      document.body.appendChild(container);
    }
    
    return container;
  }
  
  // Create or update the progress UI for a download
  function createOrUpdateProgressUI(downloadId, downloadInfo) {
    console.log(`[MODEL_DOWNLOADER] Updating progress UI for ${downloadId}:`, downloadInfo);
    
    // Make sure the progress container is visible
    const container = getOrCreateProgressContainer();
    container.style.display = 'block';
    
    // Check if we already have a container for this download
    let progressContainer = document.getElementById(`download-progress-${downloadId}`);
    
    // If not, create one
    if (!progressContainer) {
      // Create the main container
      progressContainer = document.createElement('div');
      progressContainer.id = `download-progress-${downloadId}`;
      progressContainer.className = 'download-progress-item';
      progressContainer.style.cssText = 'margin-bottom: 10px; padding: 10px; background-color: #2d2d2d; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.2); position: relative;';
      
      // Create title element
      const titleElement = document.createElement('div');
      titleElement.className = 'progress-title';
      titleElement.style.cssText = 'font-weight: bold; margin-bottom: 5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;';
      progressContainer.appendChild(titleElement);
      
      // Create progress bar container
      const progressBarContainer = document.createElement('div');
      progressBarContainer.className = 'progress-bar-container';
      progressBarContainer.style.cssText = 'height: 20px; background-color: #444; border-radius: 3px; overflow: hidden; position: relative;';
      progressContainer.appendChild(progressBarContainer);
      
      // Create progress bar
      const progressBar = document.createElement('div');
      progressBar.className = 'progress-bar';
      progressBar.style.cssText = 'height: 100%; width: 0%; background-color: #4CAF50; transition: width 0.3s;';
      progressBarContainer.appendChild(progressBar);
      
      // Create info container
      const infoContainer = document.createElement('div');
      infoContainer.className = 'progress-info';
      infoContainer.style.cssText = 'display: flex; justify-content: space-between; margin-top: 5px; font-size: 12px;';
      progressContainer.appendChild(infoContainer);
      
      // Create percent element
      const percentElement = document.createElement('div');
      percentElement.className = 'progress-percent';
      percentElement.textContent = '0%';
      infoContainer.appendChild(percentElement);
      
      // Create size element
      const sizeElement = document.createElement('div');
      sizeElement.className = 'progress-size';
      sizeElement.textContent = '0 / 0 MB';
      infoContainer.appendChild(sizeElement);
      
      // Create status element
      const statusElement = document.createElement('div');
      statusElement.className = 'progress-status';
      statusElement.style.cssText = 'margin-top: 5px; font-size: 12px; color: #aaa;';
      statusElement.textContent = 'Starting download...';
      progressContainer.appendChild(statusElement);
      
      // Add to the progress container
      container.appendChild(progressContainer);
    }
    
    // Update the progress UI with the latest info
    const titleElement = progressContainer.querySelector('.progress-title');
    titleElement.textContent = `${downloadInfo.filename}`;
    titleElement.title = `${downloadInfo.folder} / ${downloadInfo.filename}`;
    
    const progressBar = progressContainer.querySelector('.progress-bar');
    progressBar.style.width = `${downloadInfo.percent}%`;
    
    // Change color based on status
    if (downloadInfo.status === 'error') {
      progressBar.style.backgroundColor = '#F44336'; // Red for error
    } else if (downloadInfo.status === 'completed') {
      progressBar.style.backgroundColor = '#2196F3'; // Blue for completed
    } else {
      progressBar.style.backgroundColor = '#4CAF50'; // Green for in progress
    }
    
    const percentElement = progressContainer.querySelector('.progress-percent');
    percentElement.textContent = `${Math.round(downloadInfo.percent)}%`;
    
    const sizeElement = progressContainer.querySelector('.progress-size');
    const downloadedMB = (downloadInfo.downloaded / (1024 * 1024)).toFixed(2);
    const totalMB = (downloadInfo.total_size / (1024 * 1024)).toFixed(2);
    sizeElement.textContent = `${downloadedMB} / ${totalMB} MB`;
    
    // Update status text
    const statusElement = progressContainer.querySelector('.progress-status');
    if (downloadInfo.status === 'error') {
      statusElement.textContent = `Error: ${downloadInfo.error || 'Unknown error'}`;
      statusElement.style.color = '#F44336';
    } else if (downloadInfo.status === 'completed') {
      statusElement.textContent = 'Download completed!';
      statusElement.style.color = '#2196F3';
    } else if (downloadInfo.status === 'downloading') {
      if (downloadInfo.percent > 0) {
        statusElement.textContent = 'Downloading...';
      } else {
        statusElement.textContent = 'Initializing download...';
      }
      statusElement.style.color = '#aaa';
    } else {
      statusElement.textContent = downloadInfo.status || 'Starting download...';
      statusElement.style.color = '#aaa';
    }
    
    // If download is completed or errored, add a close button and set a timeout to remove it
    if ((downloadInfo.status === 'completed' || downloadInfo.status === 'error') && !progressContainer.querySelector('.close-button')) {
      const closeButton = document.createElement('div');
      closeButton.className = 'close-button';
      closeButton.innerHTML = '&times;';
      closeButton.style.cssText = 'position: absolute; top: 5px; right: 5px; cursor: pointer; font-size: 16px; color: #aaa;';
      closeButton.addEventListener('click', () => {
        progressContainer.remove();
        delete window.modelDownloader.activeDownloads[downloadId];
        
        // If there are no more downloads, hide the container
        const container = document.getElementById('model-downloads-container');
        if (container && container.querySelectorAll('.download-progress-item').length === 0) {
          container.style.display = 'none';
        }
      });
      progressContainer.appendChild(closeButton);
      
      // Auto-remove after 60 seconds
      setTimeout(() => {
        if (progressContainer.parentNode) {
          progressContainer.remove();
          delete window.modelDownloader.activeDownloads[downloadId];
          
          // If there are no more downloads, hide the container
          const container = document.getElementById('model-downloads-container');
          if (container && container.querySelectorAll('.download-progress-item').length === 0) {
            container.style.display = 'none';
          }
        }
      }, 60000);
    }
    
    // Make the progress container visible by ensuring it's in the viewport
    const viewContainer = document.getElementById('model-downloads-container');
    if (viewContainer) {
      viewContainer.scrollIntoView({ behavior: 'smooth', block: 'end' });
    }
  }

  // Expose functions to global scope
  window.modelDownloaderUI = {
    getOrCreateProgressContainer: getOrCreateProgressContainer,
    createOrUpdateProgressUI: createOrUpdateProgressUI
  };
})();

console.log('[MODEL_DOWNLOADER] UI module loaded');
