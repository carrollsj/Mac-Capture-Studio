const canvas = document.getElementById('editorCanvas');
const ctx = canvas.getContext('2d');
const captureBtn = document.getElementById('captureBtn');
const toolGrid = document.getElementById('toolGrid');
const colorInput = document.getElementById('colorInput');
const widthInput = document.getElementById('widthInput');
const fontInput = document.getElementById('fontInput');
const undoBtn = document.getElementById('undoBtn');
const redoBtn = document.getElementById('redoBtn');
const clearBtn = document.getElementById('clearBtn');
const resetBtn = document.getElementById('resetBtn');
const copyBtn = document.getElementById('copyBtn');
const exportBtn = document.getElementById('exportBtn');
const recordBtn = document.getElementById('recordBtn');
const stopRecordBtn = document.getElementById('stopRecordBtn');
const saveProjectBtn = document.getElementById('saveProjectBtn');
const loadProjectInput = document.getElementById('loadProjectInput');
const settingsBtn = document.getElementById('settingsBtn');
const settingsDialog = document.getElementById('settingsDialog');
const saveHotkeysBtn = document.getElementById('saveHotkeysBtn');
const statusText = document.getElementById('statusText');
const modeLabel = document.getElementById('modeLabel');
const emptyState = document.getElementById('emptyState');

const state = {
  tool: 'select',
  baseDataUrl: '',
  baseImage: null,
  annotations: [],
  undone: [],
  drawing: false,
  draft: null,
  recorder: null,
  recordingChunks: [],
  shortcuts: {
    capture: 'CommandOrControl+Shift+5',
    export: 'CommandOrControl+Shift+E',
    open: 'CommandOrControl+Shift+O'
  }
};

const tools = {
  select: 'Select',
  pen: 'Pen',
  highlight: 'Highlighter',
  arrow: 'Arrow',
  line: 'Line',
  rect: 'Rectangle',
  ellipse: 'Ellipse',
  text: 'Text',
  pixelate: 'Pixelate',
  crop: 'Crop'
};

function setStatus(message) {
  statusText.textContent = message;
}

function setTool(tool) {
  state.tool = tool;
  modeLabel.textContent = tools[tool] || 'Ready';
  [...toolGrid.querySelectorAll('button')].forEach((button) => {
    button.classList.toggle('active', button.dataset.tool === tool);
  });
}

function pointerPosition(event) {
  const rect = canvas.getBoundingClientRect();
  return {
    x: ((event.clientX - rect.left) / rect.width) * canvas.width,
    y: ((event.clientY - rect.top) / rect.height) * canvas.height
  };
}

function drawArrow(context, item) {
  const headLength = Math.max(14, item.width * 4);
  const angle = Math.atan2(item.y2 - item.y1, item.x2 - item.x1);
  context.beginPath();
  context.moveTo(item.x1, item.y1);
  context.lineTo(item.x2, item.y2);
  context.stroke();
  context.beginPath();
  context.moveTo(item.x2, item.y2);
  context.lineTo(item.x2 - headLength * Math.cos(angle - Math.PI / 6), item.y2 - headLength * Math.sin(angle - Math.PI / 6));
  context.lineTo(item.x2 - headLength * Math.cos(angle + Math.PI / 6), item.y2 - headLength * Math.sin(angle + Math.PI / 6));
  context.closePath();
  context.fill();
}

function pixelate(context, item) {
  const x = Math.min(item.x1, item.x2);
  const y = Math.min(item.y1, item.y2);
  const width = Math.abs(item.x2 - item.x1);
  const height = Math.abs(item.y2 - item.y1);
  if (width < 2 || height < 2) return;
  const sample = Math.max(8, item.width * 3);
  const off = document.createElement('canvas');
  off.width = Math.max(1, Math.ceil(width / sample));
  off.height = Math.max(1, Math.ceil(height / sample));
  const offCtx = off.getContext('2d');
  offCtx.imageSmoothingEnabled = false;
  offCtx.drawImage(canvas, x, y, width, height, 0, 0, off.width, off.height);
  context.imageSmoothingEnabled = false;
  context.drawImage(off, 0, 0, off.width, off.height, x, y, width, height);
  context.imageSmoothingEnabled = true;
}

function drawAnnotation(context, item) {
  context.save();
  context.lineCap = 'round';
  context.lineJoin = 'round';
  context.strokeStyle = item.color;
  context.fillStyle = item.color;
  context.lineWidth = item.width;

  if (item.type === 'pen' || item.type === 'highlight') {
    context.globalAlpha = item.type === 'highlight' ? 0.34 : 1;
    context.globalCompositeOperation = item.type === 'highlight' ? 'multiply' : 'source-over';
    context.beginPath();
    item.points.forEach((point, index) => {
      if (index === 0) context.moveTo(point.x, point.y);
      else context.lineTo(point.x, point.y);
    });
    context.stroke();
  }

  if (item.type === 'line') {
    context.beginPath();
    context.moveTo(item.x1, item.y1);
    context.lineTo(item.x2, item.y2);
    context.stroke();
  }

  if (item.type === 'arrow') drawArrow(context, item);

  if (item.type === 'rect') {
    context.strokeRect(item.x1, item.y1, item.x2 - item.x1, item.y2 - item.y1);
  }

  if (item.type === 'ellipse') {
    context.beginPath();
    context.ellipse((item.x1 + item.x2) / 2, (item.y1 + item.y2) / 2, Math.abs(item.x2 - item.x1) / 2, Math.abs(item.y2 - item.y1) / 2, 0, 0, Math.PI * 2);
    context.stroke();
  }

  if (item.type === 'text') {
    context.font = `${item.size}px system-ui, -apple-system, BlinkMacSystemFont, sans-serif`;
    context.textBaseline = 'top';
    context.fillText(item.text, item.x, item.y);
  }

  if (item.type === 'pixelate') pixelate(context, item);

  if (item.type === 'crop') {
    context.setLineDash([10, 8]);
    context.strokeStyle = '#111827';
    context.strokeRect(item.x1, item.y1, item.x2 - item.x1, item.y2 - item.y1);
  }

  context.restore();
}

function render(includeDraft = true) {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  if (state.baseImage) {
    ctx.drawImage(state.baseImage, 0, 0, canvas.width, canvas.height);
  } else {
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
  }
  state.annotations.forEach((item) => drawAnnotation(ctx, item));
  if (includeDraft && state.draft) drawAnnotation(ctx, state.draft);
  emptyState.hidden = Boolean(state.baseImage);
}

function pushAnnotation(item) {
  state.annotations.push(item);
  state.undone = [];
  render();
}

function loadBaseImage(dataUrl) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => {
      canvas.width = image.naturalWidth;
      canvas.height = image.naturalHeight;
      state.baseImage = image;
      state.baseDataUrl = dataUrl;
      state.annotations = [];
      state.undone = [];
      setStatus(`${image.naturalWidth} × ${image.naturalHeight}`);
      render();
      resolve();
    };
    image.onerror = reject;
    image.src = dataUrl;
  });
}

async function captureScreen() {
  if (!navigator.mediaDevices?.getDisplayMedia) {
    setStatus('Screen capture is not available in this browser');
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getDisplayMedia({
      video: { cursor: 'always' },
      audio: false
    });
    const video = document.createElement('video');
    video.srcObject = stream;
    await video.play();
    await new Promise((resolve) => requestAnimationFrame(resolve));
    const frame = document.createElement('canvas');
    frame.width = video.videoWidth;
    frame.height = video.videoHeight;
    frame.getContext('2d').drawImage(video, 0, 0);
    stream.getTracks().forEach((track) => track.stop());
    await loadBaseImage(frame.toDataURL('image/png'));
  } catch (error) {
    setStatus(error.name === 'NotAllowedError' ? 'Capture canceled or permission denied' : `Capture failed: ${error.message}`);
  }
}

function exportDataUrl() {
  render(false);
  const dataUrl = canvas.toDataURL('image/png');
  render();
  return dataUrl;
}

async function exportPng() {
  if (!state.baseImage) return setStatus('Capture an image before exporting');
  const dataUrl = exportDataUrl();
  if (window.macCapture?.savePng) {
    const result = await window.macCapture.savePng(dataUrl);
    if (!result.canceled) setStatus(`Exported ${result.filePath}`);
    return;
  }
  const link = document.createElement('a');
  link.href = dataUrl;
  link.download = 'capture.png';
  link.click();
  setStatus('PNG exported');
}

async function copyPng() {
  if (!state.baseImage) return setStatus('Capture an image before copying');
  try {
    const blob = await (await fetch(exportDataUrl())).blob();
    await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
    setStatus('Copied PNG to clipboard');
  } catch (error) {
    setStatus(`Copy failed: ${error.message}`);
  }
}

async function startRecording() {
  if (!navigator.mediaDevices?.getDisplayMedia || !window.MediaRecorder) {
    setStatus('Screen recording is not available in this browser');
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getDisplayMedia({
      video: { cursor: 'always' },
      audio: true
    });
    state.recordingChunks = [];
    state.recorder = new MediaRecorder(stream, { mimeType: 'video/webm' });
    state.recorder.addEventListener('dataavailable', (event) => {
      if (event.data.size) state.recordingChunks.push(event.data);
    });
    state.recorder.addEventListener('stop', () => {
      stream.getTracks().forEach((track) => track.stop());
      const blob = new Blob(state.recordingChunks, { type: 'video/webm' });
      const link = document.createElement('a');
      link.href = URL.createObjectURL(blob);
      link.download = 'screen-recording.webm';
      link.click();
      URL.revokeObjectURL(link.href);
      state.recorder = null;
      recordBtn.disabled = false;
      stopRecordBtn.disabled = true;
      setStatus('Recording saved');
    });
    state.recorder.start();
    recordBtn.disabled = true;
    stopRecordBtn.disabled = false;
    setStatus('Recording...');
  } catch (error) {
    setStatus(error.name === 'NotAllowedError' ? 'Recording canceled or permission denied' : `Recording failed: ${error.message}`);
  }
}

function stopRecording() {
  if (state.recorder && state.recorder.state !== 'inactive') {
    state.recorder.stop();
  }
}

function cropTo(item) {
  const x = Math.max(0, Math.min(item.x1, item.x2));
  const y = Math.max(0, Math.min(item.y1, item.y2));
  const width = Math.min(canvas.width - x, Math.abs(item.x2 - item.x1));
  const height = Math.min(canvas.height - y, Math.abs(item.y2 - item.y1));
  if (width < 8 || height < 8) return render();
  render(false);
  const cropped = document.createElement('canvas');
  cropped.width = width;
  cropped.height = height;
  cropped.getContext('2d').drawImage(canvas, x, y, width, height, 0, 0, width, height);
  loadBaseImage(cropped.toDataURL('image/png'));
}

function saveProject() {
  if (!state.baseImage) return setStatus('Capture an image before saving a project');
  const project = {
    version: 1,
    baseDataUrl: state.baseDataUrl,
    annotations: state.annotations
  };
  if (window.macCapture?.saveProject) {
    window.macCapture.saveProject(project).then((result) => {
      if (!result.canceled) setStatus(`Saved ${result.filePath}`);
    });
    return;
  }
  const blob = new Blob([JSON.stringify(project, null, 2)], { type: 'application/json' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = 'capture-project.mcs.json';
  link.click();
  URL.revokeObjectURL(link.href);
  setStatus('Project saved');
}

async function loadProject(file) {
  try {
    const project = JSON.parse(await file.text());
    await loadBaseImage(project.baseDataUrl);
    state.annotations = Array.isArray(project.annotations) ? project.annotations : [];
    state.undone = [];
    render();
    setStatus(`Loaded ${file.name}`);
  } catch (error) {
    setStatus(`Could not load project: ${error.message}`);
  }
}

function undo() {
  const item = state.annotations.pop();
  if (item) state.undone.push(item);
  render();
}

function redo() {
  const item = state.undone.pop();
  if (item) state.annotations.push(item);
  render();
}

function startDrawing(event) {
  if (!state.baseImage) return;
  const point = pointerPosition(event);
  state.drawing = true;
  const base = {
    type: state.tool,
    color: colorInput.value,
    width: Number(widthInput.value),
    x1: point.x,
    y1: point.y,
    x2: point.x,
    y2: point.y
  };

  if (state.tool === 'text') {
    const text = prompt('Text to add');
    state.drawing = false;
    if (text) pushAnnotation({ type: 'text', text, color: colorInput.value, size: Number(fontInput.value), x: point.x, y: point.y });
    return;
  }

  if (state.tool === 'pen' || state.tool === 'highlight') {
    state.draft = { type: state.tool, color: colorInput.value, width: Number(widthInput.value), points: [point] };
  } else {
    state.draft = base;
  }
  render();
}

function continueDrawing(event) {
  if (!state.drawing || !state.draft) return;
  const point = pointerPosition(event);
  if (state.draft.points) state.draft.points.push(point);
  else {
    state.draft.x2 = point.x;
    state.draft.y2 = point.y;
  }
  render();
}

function finishDrawing() {
  if (!state.drawing || !state.draft) return;
  state.drawing = false;
  const item = state.draft;
  state.draft = null;
  if (item.type === 'crop') return cropTo(item);
  if (item.points && item.points.length < 2) return render();
  pushAnnotation(item);
}

function clearMarkup() {
  state.annotations = [];
  state.undone = [];
  render();
}

function resetImage() {
  if (state.baseDataUrl) loadBaseImage(state.baseDataUrl);
}

function saveHotkeys(event) {
  event.preventDefault();
  const next = {};
  settingsDialog.querySelectorAll('[data-shortcut]').forEach((input) => {
    next[input.dataset.shortcut] = input.value.trim();
  });
  state.shortcuts = { ...state.shortcuts, ...next };
  localStorage.setItem('shortcuts', JSON.stringify(state.shortcuts));
  if (window.macCapture?.setShortcuts) window.macCapture.setShortcuts(state.shortcuts);
  settingsDialog.close();
  setStatus('Hotkeys updated');
}

function openSettings() {
  settingsDialog.querySelectorAll('[data-shortcut]').forEach((input) => {
    input.value = state.shortcuts[input.dataset.shortcut] || '';
  });
  settingsDialog.showModal();
}

function normalizeBrowserShortcut(event) {
  const parts = [];
  if (event.metaKey || event.ctrlKey) parts.push('CommandOrControl');
  if (event.altKey) parts.push('Alt');
  if (event.shiftKey) parts.push('Shift');
  const key = event.key.length === 1 ? event.key.toUpperCase() : event.key;
  if (!['Meta', 'Control', 'Alt', 'Shift'].includes(key)) parts.push(key);
  return parts.join('+');
}

function runShortcut(action) {
  if (action === 'capture') captureScreen();
  if (action === 'export') exportPng();
  if (action === 'open') window.focus();
}

async function initSettings() {
  const local = JSON.parse(localStorage.getItem('shortcuts') || '{}');
  state.shortcuts = { ...state.shortcuts, ...local };
  if (window.macCapture?.getSettings) {
    const settings = await window.macCapture.getSettings();
    state.shortcuts = { ...state.shortcuts, ...(settings.shortcuts || {}) };
  }
}

toolGrid.addEventListener('click', (event) => {
  const button = event.target.closest('button[data-tool]');
  if (button) setTool(button.dataset.tool);
});

captureBtn.addEventListener('click', captureScreen);
canvas.addEventListener('pointerdown', startDrawing);
canvas.addEventListener('pointermove', continueDrawing);
canvas.addEventListener('pointerup', finishDrawing);
canvas.addEventListener('pointerleave', finishDrawing);
undoBtn.addEventListener('click', undo);
redoBtn.addEventListener('click', redo);
clearBtn.addEventListener('click', clearMarkup);
resetBtn.addEventListener('click', resetImage);
copyBtn.addEventListener('click', copyPng);
exportBtn.addEventListener('click', exportPng);
recordBtn.addEventListener('click', startRecording);
stopRecordBtn.addEventListener('click', stopRecording);
saveProjectBtn.addEventListener('click', saveProject);
loadProjectInput.addEventListener('change', (event) => {
  const [file] = event.target.files;
  if (file) loadProject(file);
});
settingsBtn.addEventListener('click', openSettings);
saveHotkeysBtn.addEventListener('click', saveHotkeys);

window.addEventListener('keydown', (event) => {
  const shortcut = normalizeBrowserShortcut(event);
  const entry = Object.entries(state.shortcuts).find(([, value]) => value === shortcut);
  if (!entry) return;
  event.preventDefault();
  runShortcut(entry[0]);
});

if (window.macCapture?.onShortcut) {
  window.macCapture.onShortcut(runShortcut);
}

initSettings().then(() => {
  render();
  setStatus('Ready to capture');
});
