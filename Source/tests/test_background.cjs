const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const script = fs.readFileSync(path.join(__dirname, '../YouTube 字幕总结 Extension/Resources/background.js'), 'utf8');

function setup({ granted = true, changed = false, cookieFailure = false } = {}) {
  let click;
  const sent = [], updates = [], titles = [];
  const source = 'https://www.youtube.com/watch?v=fixture';
  const browser = {
    action: {
      onClicked: { addListener(fn) { click = fn; } },
      async setBadgeBackgroundColor() {}, async setBadgeText() {},
      async setTitle(value) { titles.push(value.title); }
    },
    permissions: { async request(details) { assert.equal(details.permissions[0], 'cookies'); return granted; } },
    cookies: {
      async getAllCookieStores() { return [{ id: 'current-profile', tabIds: [3] }]; },
      async getAll(details) {
        assert.equal(details.url, 'https://www.youtube.com/');
        assert.equal(details.storeId, 'current-profile');
        if (cookieFailure) throw Error('permission denied');
        return [
          { domain: '.youtube.com', path: '/', name: 'test', value: 'fixture', secure: true, httpOnly: true },
          { domain: '.chatgpt.com', path: '/', name: 'exclude', value: 'fixture' },
          { domain: '.youtube.com.evil.test', path: '/', name: 'exclude', value: 'fixture' },
          { domain: '.youtube.com', path: '/', name: 'invalid', value: 'line\nbreak' }
        ];
      }
    },
    runtime: {
      connectNative() { return { onMessage: { addListener() {} }, onDisconnect: { addListener() {} } }; },
      async sendNativeMessage(id, payload) { sent.push(payload); return { ok: true }; }
    },
    tabs: {
      async get() { return { url: changed ? source + '&t=5' : source }; },
      async update(id, data) { updates.push({ id, ...data }); }
    }
  };
  const context = vm.createContext({ browser, URL, setTimeout: () => 1, clearTimeout() {} });
  vm.runInContext(script, context);
  return { context, sent, updates, titles, click: () => click({ id: 3, url: source }) };
}

(async () => {
  let test = setup();
  await test.click();
  assert.equal(test.sent.length, 1);
  assert.equal(test.sent[0].cookies.length, 1);
  assert.equal(test.sent[0].cookies[0].domain, '.youtube.com');
  assert.equal(test.sent[0].cookies[0].httpOnly, true);
  assert.equal(test.sent[0].cookies[0].expirationDate, 0);
  await test.context.handleNativeMessage({ jobId: test.sent[0].jobId, ok: true, chunk: 'text', total: 1, sequence: 0 });
  assert.equal(test.updates[0].url, 'https://chatgpt.com/');

  test = setup({ granted: false });
  await test.click();
  assert.equal(test.sent[0].cookies.length, 0);
  assert(test.titles.some(title => title.includes('未允许')));

  test = setup({ cookieFailure: true });
  await test.click();
  assert.equal(test.sent[0].cookies.length, 0);
  assert(test.titles.some(title => title.includes('无法读取')));

  test = setup({ changed: true });
  await test.click();
  await test.context.handleNativeMessage({ jobId: test.sent[0].jobId, ok: true, chunk: 'text', total: 1, sequence: 0 });
  assert.equal(test.updates.length, 0);
  assert(test.titles.some(title => title.includes('原视频标签页已改变')));

  test = setup();
  await test.click();
  await test.click();
  assert.equal(test.sent.length, 1);
  console.log('浏览器流程 5 项检查通过：域名限制、权限拒绝、读取失败、跳转保护、防重复。');
})().catch(error => { console.error(error); process.exitCode = 1; });
