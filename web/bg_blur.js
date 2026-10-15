/**
 * Background Blur using MediaPipe Selfie Segmentation
 * 
 * This script:
 * 1. Captures the raw camera video stream
 * 2. Runs each frame through MediaPipe Selfie Segmentation model
 * 3. Draws blurred background + sharp person onto a canvas
 * 4. Exposes the canvas stream for Flutter to use
 *
 * Called from Flutter via dart:js:
 *   - window.startBgBlur(blurAmount)  → starts background blur
 *   - window.stopBgBlur()             → stops and restores original camera
 */

(function () {
  // --- Intercept RTCPeerConnection to apply blur to outgoing WebRTC streams ---
  window._rtcPeerConnections = window._rtcPeerConnections || [];
  const OrigPeerConnection = window.RTCPeerConnection;
  if (!window._rtcPeerConnectionPatched && OrigPeerConnection) {
    window.RTCPeerConnection = function(...args) {
      const pc = new OrigPeerConnection(...args);
      window._rtcPeerConnections.push(pc);
      pc.addEventListener('signalingstatechange', () => {
        if (pc.signalingState === 'closed') {
          window._rtcPeerConnections = window._rtcPeerConnections.filter(p => p !== pc);
        }
      });
      return pc;
    };
    window.RTCPeerConnection.prototype = OrigPeerConnection.prototype;
    window._rtcPeerConnectionPatched = true;
  }

  function _replaceWebRTCVideoTrack(newTrack) {
    if (!newTrack || !window._rtcPeerConnections) return;
    for (const pc of window._rtcPeerConnections) {
      if (pc.signalingState === 'closed') continue;
      const senders = pc.getSenders();
      for (const sender of senders) {
        if (sender.track && sender.track.kind === 'video' && sender.track !== newTrack) {
          sender.replaceTrack(newTrack).catch(e => console.error('BgBlur RTCPeerConnection error:', e));
        }
      }
    }
  }

  let _segmentation = null;
  let _animFrameId = null;
  let _uiVideoElement = null;
  let _hiddenVideo = null;
  let _canvas = null;
  let _ctx = null;
  let _offscreen = null;
  let _offCtx = null;
  let _maskCanvas = null;
  let _maskCtx = null;
  let _blurAmount = 15;
  let _running = false;
  let _originalStream = null;
  let _processedStream = null;
  let _bgType = 'blur';
  let _bgImage = null;
  let _enforcerInterval = null;
  let _isPreviewMode = false;
  let _frameCount = 0;
  let _isLowLight = false;

  window.setBgPreviewMode = function(isPreview) {
    _isPreviewMode = isPreview;
    if (_isPreviewMode && _originalStream) {
      const origTrack = _originalStream.getVideoTracks()[0];
      if (origTrack) _replaceWebRTCVideoTrack(origTrack);
    }
  };

  window.setBgTheme = function(type, value) {
    _bgType = type;
    if (type === 'blur') {
      _blurAmount = value || 15;
    } else if (type === 'image') {
      _bgImage = new Image();
      _bgImage.crossOrigin = 'anonymous';
      _bgImage.src = value;
    }
  };

  // Deep search for video elements including shadow DOMs
  function _getAllVideoElements(root) {
    let videos = [];
    if (!root) return videos;
    if (root.tagName === 'VIDEO') videos.push(root);
    
    if (root.shadowRoot) {
      videos = videos.concat(_getAllVideoElements(root.shadowRoot));
    }
    
    const children = root.children || root.childNodes;
    if (children) {
      for (let i = 0; i < children.length; i++) {
        videos = videos.concat(_getAllVideoElements(children[i]));
      }
    }
    return videos;
  }

  function _findLocalVideoElement() {
    const allVideos = _getAllVideoElements(document.body);
    let validVideos = allVideos.filter(v => v.srcObject && v.srcObject.getVideoTracks().length > 0);
    
    if (validVideos.length === 0) return null;

    // Prefer local video element (muted or volume === 0)
    let localMutedVideos = validVideos.filter(v => v.muted || v.volume === 0);
    if (localMutedVideos.length > 0) {
      validVideos = localMutedVideos;
    }

    // Sort by left coordinate descending (furthest right first)
    validVideos.sort((a, b) => b.getBoundingClientRect().left - a.getBoundingClientRect().left);
    
    return validVideos[0];
  }

  function _onResults(results) {
    if (!_running || !_canvas || !_ctx) return;

    const w = results.image.width;
    const h = results.image.height;

    if (_canvas.width !== w) _canvas.width = w;
    if (_canvas.height !== h) _canvas.height = h;

    if (!_offscreen) {
      _offscreen = document.createElement('canvas');
      _offCtx = _offscreen.getContext('2d');
    }
    if (_offscreen.width !== w) _offscreen.width = w;
    if (_offscreen.height !== h) _offscreen.height = h;

    if (!_maskCanvas) {
      _maskCanvas = document.createElement('canvas');
      _maskCtx = _maskCanvas.getContext('2d');
    }
    if (_maskCanvas.width !== w) _maskCanvas.width = w;
    if (_maskCanvas.height !== h) _maskCanvas.height = h;

    // 1. Draw raw segmentationMask to _maskCanvas and apply pixel binary thresholding
    _maskCtx.clearRect(0, 0, w, h);
    _maskCtx.drawImage(results.segmentationMask, 0, 0, w, h);

    // Guaranteed Binary Threshold: Converts all person/hand pixels (>12% confidence) to 100% solid opaque (255),
    // and background to 100% transparent (0). Eliminates translucent arm/hand ghosting rectangles!
    try {
      const imgData = _maskCtx.getImageData(0, 0, w, h);
      const d = imgData.data;
      const len = d.length;
      for (let i = 0; i < len; i += 4) {
        const val = d[i + 3] > 0 ? d[i + 3] : d[i];
        if (val > 30) {
          d[i] = 255;
          d[i + 1] = 255;
          d[i + 2] = 255;
          d[i + 3] = 255;
        } else {
          d[i] = 0;
          d[i + 1] = 0;
          d[i + 2] = 0;
          d[i + 3] = 0;
        }
      }
      _maskCtx.putImageData(imgData, 0, 0);
    } catch (e) {}

    // 2. Render Background onto Main Canvas
    _ctx.save();
    if (_bgType === 'image' && _bgImage && _bgImage.complete) {
      const imgRatio = _bgImage.width / _bgImage.height;
      const canvasRatio = w / h;
      let drawW = w;
      let drawH = h;
      let drawX = 0;
      let drawY = 0;
      
      if (imgRatio > canvasRatio) {
        drawW = h * imgRatio;
        drawX = (w - drawW) / 2;
      } else {
        drawH = w / imgRatio;
        drawY = (h - drawH) / 2;
      }
      _ctx.drawImage(_bgImage, drawX, drawY, drawW, drawH);
    } else {
      _ctx.filter = `blur(${_blurAmount}px)` + (_isLowLight ? ' brightness(1.2) contrast(1.05)' : '');
      _ctx.drawImage(results.image, -10, -10, w + 20, h + 20);
      _ctx.filter = 'none';
    }

    // 3. Render Person (Foreground) and apply sharpened mask
    _offCtx.clearRect(0, 0, w, h);
    if (_isLowLight) _offCtx.filter = 'brightness(1.2) contrast(1.05)';
    _offCtx.drawImage(results.image, 0, 0, w, h);
    _offCtx.filter = 'none';

    _offCtx.globalCompositeOperation = 'destination-in';
    _offCtx.drawImage(_maskCanvas, 0, 0, w, h);
    _offCtx.globalCompositeOperation = 'source-over';

    // 4. Layer clean Person over Background
    _ctx.drawImage(_offscreen, 0, 0, w, h);
    _ctx.restore();
  }

  async function _processLoop() {
    if (!_running || !_segmentation || !_hiddenVideo) return;
    
    if (_hiddenVideo.readyState >= 2) {
      try {
        await _segmentation.send({ image: _hiddenVideo });
      } catch (e) {}
    }
    _animFrameId = requestAnimationFrame(_processLoop);
  }

  window.startBgBlur = async function (blurAmount) {
    if (_running) return;
    _blurAmount = blurAmount || 15;
    _bgType = 'blur';

    if (typeof SelfieSegmentation === 'undefined') {
      console.warn('BgBlur: MediaPipe SelfieSegmentation not loaded.');
      if (window._onBgBlurReady) window._onBgBlurReady(false);
      return;
    }

    _uiVideoElement = _findLocalVideoElement();
    if (!_uiVideoElement) {
      console.warn('BgBlur: No local video element found.');
      if (window._onBgBlurReady) window._onBgBlurReady(false);
      return;
    }

    if (!_originalStream || (_uiVideoElement.srcObject && _uiVideoElement.srcObject !== _processedStream)) {
      _originalStream = _uiVideoElement.srcObject;
    }

    // Create a hidden video element to read the raw camera stream un-disturbed
    _hiddenVideo = document.createElement('video');
    _hiddenVideo.srcObject = _originalStream;
    _hiddenVideo.autoplay = true;
    _hiddenVideo.muted = true;
    _hiddenVideo.playsInline = true;
    _hiddenVideo.style.display = 'none';
    document.body.appendChild(_hiddenVideo);

    // Create the offscreen canvas to process the video
    _canvas = document.createElement('canvas');
    _ctx = _canvas.getContext('2d');
    
    _offscreen = document.createElement('canvas');
    _offCtx = _offscreen.getContext('2d');

    _segmentation = new SelfieSegmentation({
      locateFile: (file) => `https://cdn.jsdelivr.net/npm/@mediapipe/selfie_segmentation/${file}`,
    });
    _segmentation.setOptions({
      modelSelection: 1,
      selfieMode: false,
    });
    _segmentation.onResults(_onResults);

    _running = true;
    _processLoop();

    if (_enforcerInterval) clearInterval(_enforcerInterval);
    _enforcerInterval = setInterval(() => {
      if (!_running || !_processedStream) return;
      
      if (_isPreviewMode) {
        if (_originalStream) {
          const origTrack = _originalStream.getVideoTracks()[0];
          if (origTrack) _replaceWebRTCVideoTrack(origTrack);
        }
      } else {
        const processedTrack = _processedStream.getVideoTracks()[0];
        if (processedTrack) {
          _replaceWebRTCVideoTrack(processedTrack);
        }
      }

      // Check if Flutter overwrote the UI video element with a new raw camera stream (e.g. after camera toggle)
      if (_uiVideoElement && _uiVideoElement.srcObject && _uiVideoElement.srcObject !== _processedStream) {
        const newRawStream = _uiVideoElement.srcObject;
        if (newRawStream.getVideoTracks().length > 0) {
          _originalStream = newRawStream;
          if (_hiddenVideo) _hiddenVideo.srcObject = _originalStream;
          // Force the UI back to our processed stream
          _uiVideoElement.srcObject = _processedStream;
        }
      }
    }, 1000);

    // Give it a moment to process the first frame, then pipe the blurred canvas stream into the UI!
    setTimeout(() => {
      if (_running && _canvas) {
        _processedStream = _canvas.captureStream(30);
        // Overwrite the Flutter UI's video feed with our blurred canvas stream
        _uiVideoElement.srcObject = _processedStream;
        
        // Also overwrite the WebRTC outgoing stream so remote participants see the blur!
        const newTrack = _processedStream.getVideoTracks()[0];
        _replaceWebRTCVideoTrack(newTrack);

        if (window._onBgBlurReady) window._onBgBlurReady(true);
      }
    }, 800);
  };

  window.stopBgBlur = function () {
    _running = false;
    if (_animFrameId) {
      cancelAnimationFrame(_animFrameId);
      _animFrameId = null;
    }
    if (_enforcerInterval) {
      clearInterval(_enforcerInterval);
      _enforcerInterval = null;
    }
    if (_segmentation) {
      _segmentation.close();
      _segmentation = null;
    }
    
    // Restore the original camera stream to the UI
    if (_uiVideoElement && _originalStream) {
      _uiVideoElement.srcObject = _originalStream;
      
      // Restore WebRTC stream to remote participants
      const originalTrack = _originalStream.getVideoTracks()[0];
      if (originalTrack) {
        _replaceWebRTCVideoTrack(originalTrack);
      }
    }
    
    if (_hiddenVideo && _hiddenVideo.parentNode) {
      _hiddenVideo.parentNode.removeChild(_hiddenVideo);
    }
    
    _hiddenVideo = null;
    _canvas = null;
    _ctx = null;
    _offscreen = null;
    _offCtx = null;
    _maskCanvas = null;
    _maskCtx = null;
    _uiVideoElement = null;
    _originalStream = null;
    _processedStream = null;
  };

  window.isBgBlurAvailable = function () {
    return typeof SelfieSegmentation !== 'undefined';
  };
  window.setBgBlurReadyCallback = function(callback) {
    window._onBgBlurReady = callback;
  };

})();
