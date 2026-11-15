const { app, BrowserWindow, globalShortcut, ipcMain, dialog } = require('electron');
const fs = require('fs');
const path = require('path');

let mainWindow;
let shortcuts = {
  capture: 'CommandOrControl+Shift+5',
  export: 'CommandOrControl+Shift+E',
  open: 'CommandOrControl+Shift+O'
};

function settingsPath() {
  return path.join(app.getPath('userData'), 'settings.json');
}

function loadSettings() {
  try {
    const raw = fs.readFileSync(settingsPath(), 'utf8');
    const parsed = JSON.parse(raw);
    shortcuts = { ...shortcuts, ...(parsed.shortcuts || {}) };
  } catch (_) {
    // First launch: no settings yet.
  }
}

function saveSettings(nextShortcuts) {
  shortcuts = { ...shortcuts, ...nextShortcuts };
  fs.mkdirSync(app.getPath('userData'), { recursive: true });
  fs.writeFileSync(settingsPath(), JSON.stringify({ shortcuts }, null, 2));
}

function send(action) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.show();
    mainWindow.webContents.send('shortcut', action);
  }
}

function registerShortcuts() {
  globalShortcut.unregisterAll();
  for (const [action, accelerator] of Object.entries(shortcuts)) {
    if (!accelerator) continue;
    try {
      globalShortcut.register(accelerator, () => send(action));
    } catch (_) {
      // Invalid accelerators are reported inside the app settings screen.
    }
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 960,
    minHeight: 680,
    title: 'Mac Capture Studio',
    backgroundColor: '#f6f7f9',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'index.html'));
}

app.whenReady().then(() => {
  loadSettings();
  createWindow();
  registerShortcuts();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

ipcMain.handle('settings:get', () => ({ shortcuts }));

ipcMain.handle('settings:set-shortcuts', (_event, nextShortcuts) => {
  saveSettings(nextShortcuts);
  registerShortcuts();
  return { shortcuts };
});

ipcMain.handle('file:save-png', async (_event, dataUrl) => {
  const result = await dialog.showSaveDialog(mainWindow, {
    title: 'Export PNG',
    defaultPath: 'capture.png',
    filters: [{ name: 'PNG Image', extensions: ['png'] }]
  });
  if (result.canceled || !result.filePath) return { canceled: true };
  const base64 = dataUrl.replace(/^data:image\/png;base64,/, '');
  fs.writeFileSync(result.filePath, Buffer.from(base64, 'base64'));
  return { canceled: false, filePath: result.filePath };
});

ipcMain.handle('file:save-project', async (_event, project) => {
  const result = await dialog.showSaveDialog(mainWindow, {
    title: 'Save Project',
    defaultPath: 'capture-project.mcs.json',
    filters: [{ name: 'Mac Capture Studio Project', extensions: ['json'] }]
  });
  if (result.canceled || !result.filePath) return { canceled: true };
  fs.writeFileSync(result.filePath, JSON.stringify(project, null, 2));
  return { canceled: false, filePath: result.filePath };
});
