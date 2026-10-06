(() => {
  if (globalThis.__youtubeSubtitleSummaryInstalled) {
    return { ready: true };
  }
  globalThis.__youtubeSubtitleSummaryInstalled = true;

  browser.runtime.onMessage.addListener((message) => {
    if (message?.action !== "submitTranscript") {
      return undefined;
    }
    return submitTranscript(message.prompt, message.transcript);
  });

  return {
    ready: Boolean(document.body),
    error: document.body ? null : "ChatGPT 页面没有正常载入"
  };
})();

async function submitTranscript(prompt, transcript) {
  try {
    const editor = await waitForComposer(30000);
    const text = `${String(prompt || "这期节目讲了啥")}\n\n${String(transcript || "")}`.trim();
    if (!text) throw new Error("字幕内容为空");

    editor.focus();
    setEditorText(editor, text);
    await delay(300);

    const sendButton = await waitForSendButton(10000);
    if (sendButton.disabled || sendButton.getAttribute("aria-disabled") === "true") {
      throw new Error("ChatGPT 发送按钮当前不可用");
    }
    sendButton.click();
    return { ok: true };
  } catch (error) {
    return { ok: false, error: String(error?.message || error) };
  }
}

async function waitForComposer(timeoutMs) {
  const selectors = [
    "#prompt-textarea",
    "textarea[data-testid='prompt-textarea']",
    "div[contenteditable='true'][data-testid='prompt-textarea']",
    "div[contenteditable='true'][role='textbox']"
  ];

  return waitForElement(() => {
    for (const selector of selectors) {
      const element = document.querySelector(selector);
      if (element && isVisible(element)) return element;
    }
    return null;
  }, timeoutMs, "没有找到 ChatGPT 输入框，请确认已经登录");
}

async function waitForSendButton(timeoutMs) {
  const selectors = [
    "button[data-testid='send-button']",
    "button[aria-label*='Send']",
    "button[aria-label*='发送']"
  ];

  return waitForElement(() => {
    for (const selector of selectors) {
      const element = document.querySelector(selector);
      if (element && isVisible(element)) return element;
    }
    return null;
  }, timeoutMs, "没有找到 ChatGPT 发送按钮");
}

function setEditorText(editor, text) {
  if (editor instanceof HTMLTextAreaElement || editor instanceof HTMLInputElement) {
    const prototype = editor instanceof HTMLTextAreaElement
      ? HTMLTextAreaElement.prototype
      : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
    if (setter) setter.call(editor, text);
    else editor.value = text;
    editor.dispatchEvent(new Event("input", { bubbles: true }));
    editor.dispatchEvent(new Event("change", { bubbles: true }));
    return;
  }

  editor.replaceChildren();
  const lines = text.split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const paragraph = document.createElement("p");
    paragraph.textContent = lines[index] || "\u00A0";
    editor.appendChild(paragraph);
  }
  editor.dispatchEvent(new InputEvent("input", {
    bubbles: true,
    inputType: "insertText",
    data: text
  }));
}

function waitForElement(find, timeoutMs, errorMessage) {
  return new Promise((resolve, reject) => {
    const existing = find();
    if (existing) {
      resolve(existing);
      return;
    }

    const timeout = setTimeout(() => {
      observer.disconnect();
      reject(new Error(errorMessage));
    }, timeoutMs);

    const observer = new MutationObserver(() => {
      const found = find();
      if (!found) return;
      clearTimeout(timeout);
      observer.disconnect();
      resolve(found);
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  });
}

function isVisible(element) {
  const style = getComputedStyle(element);
  return style.visibility !== "hidden" && style.display !== "none";
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
