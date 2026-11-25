// Bundled KernelSU WebUI JS bridge (mirrors kernelsu@3.0.2 API, zero CDN dependency)
let callbackCounter = 0;

function getUniqueCallbackName(prefix) {
  return `${prefix}_cb_${Date.now()}_${callbackCounter++}`;
}

export const hasKsuBridge = typeof window.ksu !== "undefined" && typeof window.ksu.exec === "function";

export function exec(command, options = {}) {
  return new Promise((resolve, reject) => {
    if (!hasKsuBridge) {
      reject(new Error("KernelSU bridge (window.ksu) unavailable"));
      return;
    }
    const cbName = getUniqueCallbackName("exec");
    window[cbName] = (errno, stdout, stderr) => {
      delete window[cbName];
      resolve({ errno, stdout, stderr });
    };
    try {
      window.ksu.exec(command, JSON.stringify(options), cbName);
    } catch (err) {
      delete window[cbName];
      reject(err);
    }
  });
}

export function toast(message) {
  if (typeof window.ksu !== "undefined" && typeof window.ksu.toast === "function") {
    window.ksu.toast(String(message));
  }
}

export function moduleInfo() {
  if (typeof window.ksu !== "undefined" && typeof window.ksu.moduleInfo === "function") {
    return window.ksu.moduleInfo();
  }
  return "";
}
