'use strict';
const $ = (id) => document.getElementById(id);
const embedded = new URLSearchParams(location.search).get('embedded') === '1';
if (embedded) document.documentElement.classList.add('mactoys');
let token = new URLSearchParams(location.hash.slice(1)).get('token') || sessionStorage.getItem('portman-token') || '';
if (token) sessionStorage.setItem('portman-token', token);
if (location.hash) history.replaceState(null, '', embedded ? '/?embedded=1' : '/');
window.addEventListener('hashchange', () => {
  const supplied = new URLSearchParams(location.hash.slice(1)).get('token');
  if (supplied) {
    token = supplied; sessionStorage.setItem('portman-token', token);
    history.replaceState(null, '', embedded ? '/?embedded=1' : '/'); refresh(); loadAliases();
  }
});
let mappings = [], aliases = [], filter = 'all', editing = null, deleting = null, busy = false, refreshing = false;
let renderedMarkup = null;
const statusNames = { running: '运行中', stopped: '已停止', starting: '正在连接', retrying: '等待重试' };
const modeNames = { tcp: 'TCP', 'ssh-local': 'SSH LOCAL', 'ssh-remote': 'SSH REVERSE' };
const escapeHTML = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

async function api(path, data) {
  const r = await fetch('/api/' + path, { method: data === undefined ? 'GET' : 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: data === undefined ? undefined : JSON.stringify(data), cache: 'no-store' });
  const result = await r.json();
  if (!r.ok) throw new Error(r.status === 401 ? '请运行 portman gui 重新打开管理界面。' : (result.error || '请求失败'));
  return result;
}
function toast(message) {
  $('toast').textContent = message; $('toast').hidden = false;
  clearTimeout(toast.timer); toast.timer = setTimeout(() => { $('toast').hidden = true; }, 4200);
}
function bytes(n) { return n < 1024 ? n + ' B' : n < 1048576 ? (n / 1024).toFixed(1) + ' KB' : (n / 1048576).toFixed(1) + ' MB'; }
function render() {
  $('total').textContent = $('nav-count').textContent = mappings.length;
  $('running').textContent = mappings.filter(m => m.status === 'running').length;
  $('stopped').textContent = mappings.filter(m => m.status === 'stopped').length;
  $('attention').textContent = mappings.filter(m => ['starting', 'retrying'].includes(m.status)).length;
  const q = $('search').value.toLowerCase();
  const visible = mappings.filter(m => (filter === 'all' || m.status === filter) && [m.name, m.listen, m.target, m.via].join(' ').toLowerCase().includes(q));
  $('empty').hidden = mappings.length !== 0;
  const markup = visible.map(m => {
    const e = escapeHTML, reverse = m.mode === 'ssh-remote';
    return `<article class="mapping-card" data-id="${e(m.id)}"><div class="card-top"><div class="card-identity"><h3>${e(m.name)}</h3><span class="mode-tag">${modeNames[m.mode]}</span></div><span class="status ${e(m.status)}"><i class="dot ${m.status === 'running' ? 'green' : ['starting','retrying'].includes(m.status) ? 'amber' : 'gray'}"></i>${statusNames[m.status] || e(m.status)}</span></div>
      <div class="route"><div class="endpoint"><small>${reverse ? '远端监听 · ' + e(m.via) : '本机监听'}</small><code>${e(m.listen)}</code></div><div class="route-connector">── <span>${m.via ? e(m.via) : 'DIRECT TCP'}</span> →</div><div class="endpoint"><small>${reverse ? '本机侧目标' : m.mode === 'ssh-local' ? '远端侧目标' : '目标服务'}</small><code>${e(m.target)}</code></div></div>
      ${m.error && m.status !== 'stopped' ? `<div class="card-error">${e(m.error)}</div>` : ''}
      <div class="card-bottom"><span class="card-meta">${m.mode === 'tcp' ? `${m.connections} 次连接 · ↑ ${bytes(m.bytes_up)} · ↓ ${bytes(m.bytes_down)}` : 'SSH 加密连接 · 断线自动重连'}${m.last_check ? ' · 最近检查' + (m.last_check.ok ? '已返回' : '失败') : ''}</span><div class="card-actions">
      <button data-action="check">检查</button><button data-action="logs">日志</button><button data-action="edit">编辑</button><button data-action="restart" ${m.status === 'stopped' ? 'hidden' : ''}>重启</button><button class="toggle" data-action="${m.enabled ? 'stop' : 'start'}">${m.enabled ? 'Ⅱ 停止' : '▷ 启动'}</button><button class="delete" data-action="remove">删除</button></div></div></article>`;
  }).join('') || (mappings.length ? '<div class="no-results">没有符合条件的映射。</div>' : '');
  const list = $('mapping-list');
  if (markup !== renderedMarkup) {
    const focused = list.contains(document.activeElement) ? document.activeElement : null;
    const oldId = focused?.closest('[data-id]')?.dataset.id;
    const oldAction = focused?.dataset.action;
    list.innerHTML = markup; renderedMarkup = markup;
    if (oldId && oldAction) {
      const replacement = [...list.querySelectorAll('button[data-action]')].find(b => b.dataset.action === oldAction && b.closest('[data-id]').dataset.id === oldId);
      if (replacement && !replacement.hidden) replacement.focus({ preventScroll: true });
    }
  }
  list.querySelectorAll('button').forEach(b => { b.disabled = busy; });
}
async function refresh() {
  if (refreshing) return;
  refreshing = true;
  try {
    mappings = (await api('mappings')).mappings;
    $('connection-dot').classList.remove('error'); $('connection-text').textContent = '本机服务已连接';
    $('error-banner').hidden = true; render();
  } catch (e) {
    $('connection-dot').classList.add('error'); $('connection-text').textContent = '本机服务未连接';
    $('error-banner').textContent = e.message; $('error-banner').hidden = false;
  } finally { refreshing = false; }
}
async function loadAliases() {
  try { aliases = (await api('aliases')).aliases; $('ssh-aliases').innerHTML = aliases.map(v => `<option value="${escapeHTML(v)}"></option>`).join(''); }
  catch (_) { /* The dashboard shows connection errors through refresh(). */ }
}
function updateMode() {
  const mode = $('map-mode').value;
  $('ssh-fields').hidden = mode === 'tcp'; $('map-via').required = mode !== 'tcp';
  $('listen-label').textContent = mode === 'ssh-remote' ? '远端监听地址（SSH 主机）' : '本机监听地址';
  $('target-label').textContent = mode === 'ssh-local' ? '目标地址（从 SSH 主机访问）' : '目标地址（从本机访问）';
  $('mode-hint').textContent = mode === 'tcp' ? '目标支持 IP、普通主机名和 IPv6（格式：[::1]:8000）。主机名由本机 DNS 解析。' : mode === 'ssh-remote' ? '将本机可访问的服务转发到 SSH 主机。远端监听范围由服务器的 GatewayPorts 设置决定。' : '复用本机 SSH 配置中的密钥与跳板机。支持主机别名、IP 和 IPv6。';
}
function openForm(m = null) {
  editing = m; $('mapping-form').reset();
  $('mapping-dialog').querySelector('.eyebrow').textContent = m ? 'EDIT CONNECTION' : 'NEW CONNECTION';
  $('mapping-dialog').querySelector('.close').setAttribute('aria-label', m ? '关闭编辑映射' : '关闭新建映射');
  $('form-title').textContent = m ? '编辑映射' : '新建映射';
  $('save-mapping').textContent = m ? '保存修改' : '创建映射';
  $('map-name').value = m?.name || ''; $('map-mode').value = m?.mode || 'ssh-local';
  $('map-via').value = m?.via || ''; $('map-ssh-port').value = m?.ssh_port || '';
  $('map-listen').value = m?.listen || '127.0.0.1:'; $('map-target').value = m?.target || '';
  $('start-field').hidden = !!m; $('form-error').hidden = true;
  updateMode(); $('mapping-dialog').showModal(); $('map-name').focus(); loadAliases();
}
function detail(title, html) { $('detail-title').textContent = title; $('detail-content').innerHTML = html; $('detail-dialog').showModal(); }
document.querySelectorAll('.new-mapping').forEach(b => b.addEventListener('click', () => openForm()));
document.querySelectorAll('dialog .close').forEach(b => b.addEventListener('click', () => b.closest('dialog').close()));
$('map-mode').addEventListener('change', updateMode);
$('search').addEventListener('input', render);
document.querySelectorAll('[data-filter]').forEach(b => b.addEventListener('click', () => {
  filter = b.dataset.filter;
  document.querySelectorAll('[data-filter]').forEach(x => { x.classList.toggle('active', x === b); x.setAttribute('aria-selected', x === b ? 'true' : 'false'); }); render();
}));
$('mapping-form').addEventListener('submit', async ev => {
  ev.preventDefault(); if (busy) return;
  const mode = $('map-mode').value;
  const spec = { name: $('map-name').value.trim(), mode, listen: $('map-listen').value.trim(), target: $('map-target').value.trim(),
    via: mode === 'tcp' ? '' : $('map-via').value.trim(), ssh_port: mode === 'tcp' || !$('map-ssh-port').value ? null : Number($('map-ssh-port').value) };
  busy = true; $('save-mapping').disabled = true; $('save-mapping').textContent = '正在保存与连接…'; $('form-error').hidden = true;
  try {
    const result = await api(editing ? 'edit' : 'add', editing ? { name: editing.id, spec } : { spec, start: $('map-start').checked });
    $('mapping-dialog').close();
    toast(result.status === 'running' ? '映射已启动' : result.status === 'stopped' ? '映射已保存' : '配置已保存，连接状态请查看列表');
  } catch (e) { $('form-error').textContent = e.message; $('form-error').hidden = false; }
  finally { busy = false; $('save-mapping').disabled = false; $('save-mapping').textContent = editing ? '保存修改' : '创建映射'; await refresh(); }
});
$('mapping-list').addEventListener('click', async ev => {
  const button = ev.target.closest('button[data-action]'); if (!button || busy) return;
  const m = mappings.find(x => x.id === button.closest('[data-id]').dataset.id); if (!m) return;
  const action = button.dataset.action;
  if (action === 'edit') return openForm(m);
  if (action === 'remove') { deleting = m; $('delete-text').textContent = `“${m.name}”将停止转发，并从已保存的映射中移除。`; return $('delete-dialog').showModal(); }
  busy = true; button.disabled = true;
  try {
    if (action === 'logs') { const result = await api('logs?' + new URLSearchParams({ name: m.id })); detail(m.name + ' · 日志', `<pre>${escapeHTML(result.lines.join('\n') || '暂无日志')}</pre>`); }
    else if (action === 'check') {
      const r = await api('check', { name: m.id });
      const value = v => v === null ? '未验证' : v ? '可连接' : '失败';
      const notes = m.mode === 'ssh-local' ? '监听端口和 SSH 连接正常，不代表目标应用已经可用。如需验证 HTTP 服务，可在 CLI 使用 check --http-path /。' : m.mode === 'ssh-remote' ? '检查 SSH 连接与本机目标。完整路径需要从 SSH 主机侧访问远端监听端口验证。' : '检查监听端口和目标的 TCP 连接。应用响应可通过 CLI 的 check --http-path / 验证。';
      detail(m.name + ' · 连接检查', `<p>${r.ok ? '检查已完成' : '检查失败'}</p><pre>监听端口：${value(r.listener_tcp)}\n目标端口：${value(r.target_tcp)}</pre><p>${escapeHTML(notes)}</p>${!r.ok ? `<div class="error-banner">${escapeHTML(r.message)}</div>` : ''}`);
    } else { await api(action, { name: m.id }); toast(action === 'stop' ? '映射已停止' : '连接状态已更新'); }
  } catch (e) { toast(e.message); }
  finally { busy = false; await refresh(); }
});
$('confirm-delete').addEventListener('click', async () => {
  if (!deleting || busy) return; busy = true; $('confirm-delete').disabled = true;
  try { await api('remove', { name: deleting.id }); $('delete-dialog').close(); toast('映射已删除'); }
  catch (e) { toast(e.message); }
  finally { busy = false; $('confirm-delete').disabled = false; await refresh(); }
});
$('nav-all').addEventListener('click', () => { document.querySelector('[data-filter="all"]').click(); $('search').value = ''; render(); });
$('nav-hosts').addEventListener('click', async () => { await loadAliases(); detail('SSH 主机', `<p>读取本机 SSH 配置中的主机别名。新建映射时也可以直接填写 IP 或主机名。</p><div class="host-list">${aliases.map(x => `<span class="host-chip">${escapeHTML(x)}</span>`).join('') || '<span>尚未配置主机别名</span>'}</div>`); });
$('nav-help').addEventListener('click', () => detail('命令行速查', '<p>GUI 与 CLI 共用相同配置，修改后自动同步。</p><pre>portman list\n\n# 远端 Jupyter → 本机\nportman add jupyter --listen 18000 \\\n  --target 127.0.0.1:8000 --via my-server\n\n# 直接 TCP 转发\nportman add local-api --listen 18080 \\\n  --target localhost:8080\n\nportman stop jupyter\nportman start jupyter\nportman logs jupyter\nportman check jupyter --http-path /\nportman list --json</pre><p>关闭页面后映射继续运行。停止全部后台连接：<code>portman daemon stop</code>；下次启动会恢复已启用的映射。</p>'));
refresh(); loadAliases(); setInterval(() => { if (!document.hidden && !busy) refresh(); }, 2500);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
