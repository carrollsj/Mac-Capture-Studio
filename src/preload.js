const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('macCapture', {
  getSettings: () => ipcRenderer.invoke('settings:get'),
  setShortcuts: (shortcuts) => ipcRenderer.invoke('settings:set-shortcuts', shortcuts),
  savePng: (dataUrl) => ipcRenderer.invoke('file:save-png', dataUrl),
  saveProject: (project) => ipcRenderer.invoke('file:save-project', project),
  onShortcut: (callback) => ipcRenderer.on('shortcut', (_event, action) => callback(action))
});
