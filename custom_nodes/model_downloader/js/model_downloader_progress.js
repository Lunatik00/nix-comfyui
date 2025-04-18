// Model Downloader Progress Tracking
// This file handles WebSocket connections and polling for download progress

(function() {
  // Polling interval for download progress (in milliseconds)
  const POLLING_INTERVAL = 1000;
  
  // Map to store polling intervals for each download
  const pollingIntervals = {};
  
  // Function to poll download progress via API
  async function pollDownloadProgress(downloadId) {
    try {
      // First try the specific download progress endpoint
      const response = await fetch(`/api/download-progress/${downloadId}`);
      
      if (response.ok) {
        const data = await response.json();
        console.log('[MODEL_DOWNLOADER] Polled progress data:', data);
        
        if (data.success && data.download) {
          // Update the UI with the latest progress
          window.modelDownloader.activeDownloads[downloadId] = data.download;
          window.modelDownloaderUI.createOrUpdateProgressUI(downloadId, data.download);
          
          // If download is completed or errored, stop polling
          if (data.download.status === 'completed' || data.download.status === 'error') {
            console.log(`[MODEL_DOWNLOADER] Download ${downloadId} ${data.download.status}, stopping polling`);
            clearInterval(pollingIntervals[downloadId]);
            delete pollingIntervals[downloadId];
          }
          return; // Successfully got the data, no need to try other methods
        }
      } else {
        console.log(`[MODEL_DOWNLOADER] Progress endpoint returned ${response.status}, trying fallback...`);
      }
      
      // If the specific endpoint failed, try the list endpoint
      const listResponse = await fetch('/api/downloads');
      if (listResponse.ok) {
        const listData = await listResponse.json();
        console.log('[MODEL_DOWNLOADER] Downloads list data:', listData);
        
        if (listData.success && listData.downloads && listData.downloads[downloadId]) {
          // Update the UI with the data from the list
          window.modelDownloader.activeDownloads[downloadId] = listData.downloads[downloadId];
          window.modelDownloaderUI.createOrUpdateProgressUI(downloadId, listData.downloads[downloadId]);
          
          // If download is completed or errored, stop polling
          if (listData.downloads[downloadId].status === 'completed' || 
              listData.downloads[downloadId].status === 'error') {
            console.log(`[MODEL_DOWNLOADER] Download ${downloadId} ${listData.downloads[downloadId].status}, stopping polling`);
            clearInterval(pollingIntervals[downloadId]);
            delete pollingIntervals[downloadId];
          }
        }
      } else {
        console.error(`[MODEL_DOWNLOADER] Error fetching downloads list: ${listResponse.status}`);
        
        // If both endpoints failed, update the UI to show we're still waiting
        // This prevents the UI from appearing frozen
        if (window.modelDownloader.activeDownloads[downloadId]) {
          // Increment a counter to show progress is still being tracked
          window.modelDownloader.activeDownloads[downloadId].pollingAttempts = 
            (window.modelDownloader.activeDownloads[downloadId].pollingAttempts || 0) + 1;
          
          // Update the status message to show we're still trying
          if (window.modelDownloader.activeDownloads[downloadId].pollingAttempts % 5 === 0) {
            window.modelDownloaderUI.createOrUpdateProgressUI(downloadId, window.modelDownloader.activeDownloads[downloadId]);
          }
        }
      }
    } catch (error) {
      console.error('[MODEL_DOWNLOADER] Error polling download progress:', error);
    }
  }
  
  // Setup WebSocket listener for progress updates
  function setupWebSocketListener() {
    console.log('[MODEL_DOWNLOADER] Setting up WebSocket listener for progress updates');
    
    // Try to get the ComfyUI socket
    let comfySocket = null;
    
    // Function to hook into the ComfyUI WebSocket
    const hookIntoComfySocket = () => {
      // ComfyUI's socket might be available in different places depending on the version
      if (typeof app !== 'undefined') {
        if (app.socket) {
          comfySocket = app.socket;
          console.log('[MODEL_DOWNLOADER] Found ComfyUI socket in app.socket');
        } else if (app.api && app.api.socket) {
          comfySocket = app.api.socket;
          console.log('[MODEL_DOWNLOADER] Found ComfyUI socket in app.api.socket');
        }
      } else if (window.app) {
        if (window.app.socket) {
          comfySocket = window.app.socket;
          console.log('[MODEL_DOWNLOADER] Found ComfyUI socket in window.app.socket');
        } else if (window.app.api && window.app.api.socket) {
          comfySocket = window.app.api.socket;
          console.log('[MODEL_DOWNLOADER] Found ComfyUI socket in window.app.api.socket');
        }
      }
      
      // If we found a socket, hook into it
      if (comfySocket) {
        // Preserve the original message handler
        const originalOnMessage = comfySocket.onmessage;
        
        // Replace with our handler that also processes download progress messages
        comfySocket.onmessage = function(event) {
          // Call the original handler first
          if (originalOnMessage) {
            originalOnMessage.call(comfySocket, event);
          }
          
          // Process our custom messages
          try {
            const message = JSON.parse(event.data);
            
            if (message.type === 'model_download_progress') {
              console.log('[MODEL_DOWNLOADER] Received progress update:', message);
              
              // Store the download info
              window.modelDownloader.activeDownloads[message.download_id] = {
                filename: message.filename,
                folder: message.folder,
                total_size: message.total_size,
                downloaded: message.downloaded,
                percent: message.percent,
                status: message.status,
                error: message.error
              };
              
              // Update the UI
              window.modelDownloaderUI.createOrUpdateProgressUI(message.download_id, window.modelDownloader.activeDownloads[message.download_id]);
            }
          } catch (e) {
            // Ignore parsing errors, might not be JSON
            console.log('[MODEL_DOWNLOADER] Error parsing WebSocket message:', e);
          }
        };
        
        console.log('[MODEL_DOWNLOADER] Successfully hooked into ComfyUI WebSocket');
        return true;
      }
      
      return false;
    };
    
    // Try to hook into the socket immediately
    let hooked = hookIntoComfySocket();
    
    // If we couldn't hook in, try again after a delay
    if (!hooked) {
      console.log('[MODEL_DOWNLOADER] ComfyUI socket not found, will retry in 1 second...');
      
      // Try again after a delay, and keep trying every second for up to 10 seconds
      let attempts = 0;
      const maxAttempts = 10;
      
      const retryInterval = setInterval(() => {
        attempts++;
        console.log(`[MODEL_DOWNLOADER] Retry attempt ${attempts}/${maxAttempts} to find ComfyUI socket...`);
        
        hooked = hookIntoComfySocket();
        
        if (hooked || attempts >= maxAttempts) {
          clearInterval(retryInterval);
          if (!hooked) {
            console.warn('[MODEL_DOWNLOADER] Could not hook into ComfyUI WebSocket after multiple attempts. Falling back to polling for progress updates.');
          }
        }
      }, 1000);
    }
  }

  // Start polling for progress updates
  function startPolling(downloadId) {
    if (!pollingIntervals[downloadId]) {
      console.log(`[MODEL_DOWNLOADER] Starting polling for download progress: ${downloadId}`);
      pollingIntervals[downloadId] = setInterval(() => {
        pollDownloadProgress(downloadId);
      }, POLLING_INTERVAL);
      
      // Initial poll immediately
      pollDownloadProgress(downloadId);
      
      // Set a timeout to stop polling after 30 minutes (failsafe)
      setTimeout(() => {
        if (pollingIntervals[downloadId]) {
          console.log(`[MODEL_DOWNLOADER] Stopping polling for ${downloadId} (timeout)`);
          clearInterval(pollingIntervals[downloadId]);
          delete pollingIntervals[downloadId];
          
          // Update the UI to show timeout
          if (window.modelDownloader.activeDownloads[downloadId]) {
            window.modelDownloader.activeDownloads[downloadId].status = 'timeout';
            window.modelDownloader.activeDownloads[downloadId].error = 'Download timed out after 30 minutes';
            window.modelDownloaderUI.createOrUpdateProgressUI(downloadId, window.modelDownloader.activeDownloads[downloadId]);
          }
        }
      }, 30 * 60 * 1000);
    }
  }

  // Stop polling for a specific download
  function stopPolling(downloadId) {
    if (pollingIntervals[downloadId]) {
      clearInterval(pollingIntervals[downloadId]);
      delete pollingIntervals[downloadId];
      console.log(`[MODEL_DOWNLOADER] Stopped polling for ${downloadId}`);
    }
  }

  // Expose functions to global scope
  window.modelDownloaderProgress = {
    pollDownloadProgress: pollDownloadProgress,
    setupWebSocketListener: setupWebSocketListener,
    startPolling: startPolling,
    stopPolling: stopPolling
  };
})();

console.log('[MODEL_DOWNLOADER] Progress tracking module loaded');
