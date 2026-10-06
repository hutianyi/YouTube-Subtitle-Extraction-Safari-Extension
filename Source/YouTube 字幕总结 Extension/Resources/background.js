const NATIVE_APP_ID = "com.example.YouTubeSubtitleExtraction";
const JOB_TIMEOUT_MS = 4 * 60 * 1000;
const jobs = new Map();
const chunkBuckets = new Map();
const activeJobByTab = new Map();
let nativePort;

connectNativePort();

browser.action.onClicked.addListener(async (tab) => {
  const url = tab?.url || "";
  if (!isYouTubeVideoURL(url)) {
    await showFailure(tab?.id, "请先打开一个 YouTube 视频页面");
    return;
  }

  if (activeJobByTab.has(tab.id)) {
    await setProgress(tab.id, "…", "正在提取字幕，请稍候");
    return;
  }

  const jobId = createJobID();
  const timeout = setTimeout(() => {
    failJob(jobId, "字幕提取等待超时，请再试一次");
  }, JOB_TIMEOUT_MS);

  jobs.set(jobId, { sourceTabId: tab.id, sourceURL: url, timeout });
  activeJobByTab.set(tab.id, jobId);
  await setProgress(tab.id, "…", "正在提取字幕…");

  try {
    const response = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, {
      action: "extractAndSummarize",
      jobId,
      url
    });

    if (!response?.ok) {
      throw new Error(response?.error || "无法启动后台字幕助手");
    }
  } catch (error) {
    await failJob(jobId, readableError(error));
  }
});

function connectNativePort() {
  try {
    nativePort = browser.runtime.connectNative(NATIVE_APP_ID);
    nativePort.onMessage.addListener(handleNativeMessage);
    nativePort.onDisconnect.addListener(() => {
      nativePort = undefined;
      setTimeout(connectNativePort, 1000);
    });
  } catch {
    setTimeout(connectNativePort, 1000);
  }
}

async function handleNativeMessage(message) {
  const name = message?.name || message?.messageName;
  const data = message?.userInfo || message;
  if (name && name !== "subtitleResult") return;

  const jobId = data?.jobId;
  if (!jobId || !jobs.has(jobId)) return;

  if (data.manualFallback) {
    const job = finishJob(jobId);
    if (!job) return;
    await showManualFallback(job.sourceTabId, data.error || "自动字幕提取未完成");
    return;
  }

  if (!data.ok) {
    await failJob(jobId, data.error || "字幕提取失败");
    return;
  }

  const total = Number(data.total || 1);
  const sequence = Number(data.sequence || 0);
  if (!Number.isInteger(total) || total < 1 || !Number.isInteger(sequence)) {
    await failJob(jobId, "字幕结果格式不正确");
    return;
  }

  const bucket = chunkBuckets.get(jobId) || {
    total,
    pieces: new Array(total)
  };
  bucket.pieces[sequence] = String(data.chunk || "");
  chunkBuckets.set(jobId, bucket);

  if (bucket.pieces.filter((piece) => typeof piece === "string").length !== bucket.total) {
    return;
  }

  const job = finishJob(jobId);
  if (!job) return;
  await navigateSourceTabToChatGPT(job);
}

async function navigateSourceTabToChatGPT(job) {
  try {
    const tab = await browser.tabs.get(job.sourceTabId);
    if (tab.url !== job.sourceURL) {
      await showClipboardFallback(job.sourceTabId, "原视频标签页已改变，未自动跳转");
      return;
    }
    await browser.tabs.update(job.sourceTabId, { url: "https://chatgpt.com/" });
  } catch (error) {
    await showClipboardFallback(job.sourceTabId, readableError(error));
  }
}

function isYouTubeVideoURL(value) {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase().replace(/\.$/, "");
    if (host === "youtu.be" || host === "www.youtu.be") {
      return url.pathname.length > 1;
    }
    const allowed = new Set([
      "youtube.com",
      "www.youtube.com",
      "m.youtube.com",
      "music.youtube.com"
    ]);
    return allowed.has(host) && url.pathname === "/watch" && Boolean(url.searchParams.get("v"));
  } catch {
    return false;
  }
}

async function openChatGPTAndSubmit(transcript) {
  const tab = await browser.tabs.create({ url: "https://chatgpt.com/", active: true });
  await waitForTabComplete(tab.id, 30000);

  await browser.scripting.executeScript({
    target: { tabId: tab.id },
    files: ["chatgpt-content.js"]
  });

  const response = await browser.tabs.sendMessage(tab.id, {
    action: "submitTranscript",
    prompt: "这期节目讲了什么",
    transcript
  });

  if (!response?.ok) {
    throw new Error(response?.error || "无法把字幕填写到 ChatGPT");
  }
}

function waitForTabComplete(tabId, timeoutMs) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      browser.tabs.onUpdated.removeListener(listener);
      reject(new Error("ChatGPT 页面打开超时"));
    }, timeoutMs);

    const listener = (updatedTabId, changeInfo) => {
      if (updatedTabId !== tabId || changeInfo.status !== "complete") return;
      clearTimeout(timeout);
      browser.tabs.onUpdated.removeListener(listener);
      resolve();
    };

    browser.tabs.onUpdated.addListener(listener);
    browser.tabs.get(tabId).then((current) => {
      if (current?.status !== "complete") return;
      clearTimeout(timeout);
      browser.tabs.onUpdated.removeListener(listener);
      resolve();
    }).catch(() => {});
  });
}

function createJobID() {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function finishJob(jobId) {
  const job = jobs.get(jobId);
  if (!job) return null;
  clearTimeout(job.timeout);
  jobs.delete(jobId);
  chunkBuckets.delete(jobId);
  activeJobByTab.delete(job.sourceTabId);
  return job;
}

async function failJob(jobId, message) {
  const job = finishJob(jobId);
  if (!job) return;
  await showFailure(job.sourceTabId, message);
}

async function setProgress(tabId, text, title) {
  if (typeof tabId !== "number") return;
  await browser.action.setBadgeBackgroundColor({ tabId, color: "#2563EB" });
  await browser.action.setBadgeText({ tabId, text });
  if (title) await browser.action.setTitle({ tabId, title });
}

async function showClipboardFallback(tabId, reason) {
  if (typeof tabId !== "number") return;
  await browser.action.setBadgeBackgroundColor({ tabId, color: "#A16207" });
  await browser.action.setBadgeText({ tabId, text: "⌘V" });
  await browser.action.setTitle({
    tabId,
    title: `完整提示词已复制，请在 ChatGPT 按 ⌘V。自动填写未完成：${reason}`
  });
}

async function showPromptReady(tabId) {
  if (typeof tabId !== "number") return;
  await browser.action.setBadgeBackgroundColor({ tabId, color: "#15803D" });
  await browser.action.setBadgeText({ tabId, text: "✓" });
  await browser.action.setTitle({
    tabId,
    title: "完整提示词已复制。请打开 ChatGPT 后按 ⌘V。"
  });
}

async function showManualFallback(tabId, reason) {
  if (typeof tabId !== "number") return;
  await browser.action.setBadgeBackgroundColor({ tabId, color: "#A16207" });
  await browser.action.setBadgeText({ tabId, text: "⌘V" });
  await browser.action.setTitle({
    tabId,
    title: `自动提取未完成；网址已复制，原脚本已打开。请在 Terminal 按 ⌘V。原因：${reason}`
  });
}

async function showFailure(tabId, message) {
  if (typeof tabId !== "number") return;
  await browser.action.setBadgeBackgroundColor({ tabId, color: "#B91C1C" });
  await browser.action.setBadgeText({ tabId, text: "!" });
  await browser.action.setTitle({ tabId, title: message });
}

function readableError(error) {
  const text = String(error?.message || error || "未知错误");
  return text.replace(/^Error:\s*/, "");
}
