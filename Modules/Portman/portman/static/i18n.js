/* Also injected by MacToys, so an older, already-running daemon can use the
   bundled translations without restarting tunnels or replacing its files. */
(function (root) {
  'use strict';
  if (root.MacToysPortman) return;
  const english = {
    'Portman · 端口映射': 'Portman · Port Forwarding',
    'Portman 首页': 'Portman home',
    '本机工作空间': 'Local workspace',
    '端口映射': 'Port Forwarding',
    'SSH 主机': 'SSH Hosts',
    '命令行速查': 'CLI Reference',
    '正在连接本机': 'Connecting locally',
    '工作空间': 'Workspace',
    '让连接，各就各位。': 'Port forwarding',
    '在一个地方管理本地转发与 SSH 隧道。': 'Manage local forwarding and SSH tunnels.',
    '新建映射': 'New mapping',
    '全部映射': 'All mappings',
    '已保存的连接': 'Saved connections',
    '运行中': 'Running',
    '转发已建立': 'Forwarding active',
    '需要关注': 'Needs attention',
    '连接中或等待重试': 'Connecting or retrying',
    '已停止': 'Stopped',
    '随时可以重新启动': 'Ready to restart',
    '映射筛选': 'Filter mappings',
    '搜索映射': 'Search mappings',
    '搜索名称、主机或端口…': 'Search name, host, or port…',
    '从第一条连接开始': 'Create your first mapping',
    '把远端服务带到本机，或将流量转发到指定地址。': 'Access a remote service locally or forward traffic to another address.',
    '＋ 新建映射': '＋ New mapping',
    '例如': 'Example',
    '本机 :18000': 'Local :18000',
    '配置自动保存 · 关闭页面后继续运行': 'Saved automatically · Connections stay active after closing this page',
    '仅管理 Portman 创建的映射': 'Only manages mappings created by Portman',
    '关闭新建映射': 'Close new mapping',
    '映射名称': 'Mapping name',
    '例如：远程 Jupyter': 'e.g. Remote Jupyter',
    '连接方式': 'Connection type',
    'SSH · 远端服务映射到本机': 'SSH · Remote service to local',
    'TCP · 直接转发': 'TCP · Direct forwarding',
    'SSH · 本机服务映射到远端': 'SSH · Local service to remote',
    'SSH 端口': 'SSH port',
    '使用配置': 'Config',
    '本机监听地址': 'Local listen address',
    '目标地址（从 SSH 主机访问）': 'Target address (from SSH host)',
    '复用本机 SSH 配置中的密钥与跳板机。支持主机别名、IP 和 IPv6。': 'Uses keys and jump hosts from your SSH config. Supports aliases, IP addresses, and IPv6.',
    '保存后立即启动': 'Start after saving',
    '取消': 'Cancel',
    '创建映射': 'Create mapping',
    '详情': 'Details',
    '关闭详情': 'Close details',
    '关闭': 'Close',
    '删除映射': 'Delete mapping',
    '取消删除': 'Cancel deletion',
    '停止并删除': 'Stop and delete',
    '正在连接': 'Connecting',
    '等待重试': 'Retrying',
    '请运行 portman gui 重新打开管理界面。': 'Run portman gui to reopen the interface.',
    '请求失败': 'Request failed',
    '本机监听': 'Local listener',
    '本机侧目标': 'Local target',
    '远端侧目标': 'Remote target',
    '目标服务': 'Target service',
    '检查': 'Check',
    '日志': 'Logs',
    '编辑': 'Edit',
    '重启': 'Restart',
    'Ⅱ 停止': 'Ⅱ Stop',
    '▷ 启动': '▷ Start',
    '删除': 'Delete',
    '没有符合条件的映射。': 'No matching mappings.',
    '本机服务已连接': 'Local service connected',
    '本机服务未连接': 'Local service disconnected',
    '远端监听地址（SSH 主机）': 'Remote listen address (SSH host)',
    '目标地址（从本机访问）': 'Target address (from this Mac)',
    '目标支持 IP、普通主机名和 IPv6（格式：[::1]:8000）。主机名由本机 DNS 解析。': 'Accepts IP addresses, hostnames, and IPv6 ([::1]:8000). Hostnames use local DNS.',
    '将本机可访问的服务转发到 SSH 主机。远端监听范围由服务器的 GatewayPorts 设置决定。': 'Forward a locally accessible service to the SSH host. Its GatewayPorts setting controls remote binding.',
    '关闭编辑映射': 'Close edit mapping',
    '编辑映射': 'Edit mapping',
    '保存修改': 'Save changes',
    '正在保存与连接…': 'Saving and connecting…',
    '映射已启动': 'Mapping started',
    '映射已保存': 'Mapping saved',
    '配置已保存，连接状态请查看列表': 'Saved. Check the list for connection status.',
    '暂无日志': 'No logs yet',
    '未验证': 'Not checked',
    '可连接': 'Reachable',
    '失败': 'Failed',
    '监听端口和 SSH 连接正常，不代表目标应用已经可用。如需验证 HTTP 服务，可在 CLI 使用 check --http-path /。': 'An open listener and SSH connection do not verify the target application. Use check --http-path / in the CLI to test HTTP.',
    '检查 SSH 连接与本机目标。完整路径需要从 SSH 主机侧访问远端监听端口验证。': 'Checks SSH and the local target. Verify the full route by accessing the remote listener from the SSH host.',
    '检查监听端口和目标的 TCP 连接。应用响应可通过 CLI 的 check --http-path / 验证。': 'Checks TCP connectivity to the listener and target. Use check --http-path / in the CLI to test an application response.',
    '检查已完成': 'Check complete',
    '检查失败': 'Check failed',
    '映射已停止': 'Mapping stopped',
    '连接状态已更新': 'Connection status updated',
    '映射已删除': 'Mapping deleted',
    '读取本机 SSH 配置中的主机别名。新建映射时也可以直接填写 IP 或主机名。': 'Hosts from your local SSH config. You can also enter an IP address or hostname when creating a mapping.',
    '尚未配置主机别名': 'No SSH aliases configured',
    'GUI 与 CLI 共用相同配置，修改后自动同步。': 'The GUI and CLI share the same configuration.',
    '关闭页面后映射继续运行。停止全部后台连接：': 'Mappings stay active when this page closes. Stop all background connections: ',
    '；下次启动会恢复已启用的映射。': '. Enabled mappings resume on the next launch.'
  };
  // Translate only UI text. Names, addresses, host aliases, logs, and user-entered
  // values are deliberately excluded. Dynamic templates are scoped to their UI.
  function translate(text, context = '') {
    const clean = text.trim();
    if (context === 'user') return text;
    if (context === 'title') return text.replace(/ · 日志$/, ' · Logs').replace(/ · 连接检查$/, ' · Connection check');
    if (Object.prototype.hasOwnProperty.call(english, clean)) return text.replace(clean, english[clean]);
    if (context === 'endpoint') return text.replace(/^远端监听 · /, 'Remote listener · ');
    if (context === 'meta') return text.replace(/^(\d+) 次连接/, '$1 connections')
      .replace(/^SSH 加密连接 · 断线自动重连/, 'SSH · Automatic reconnection')
      .replace(/ · 最近检查已返回$/, ' · Last check returned').replace(/ · 最近检查失败$/, ' · Last check failed');
    if (context === 'delete') return text.replace(/^“(.*)”将停止转发，并从已保存的映射中移除。$/s,
      (_, name) => `“${name}” will stop forwarding and be removed from saved mappings.`);
    if (context === 'check') return text.replace(/^监听端口：/m, 'Listener: ').replace(/^目标端口：/m, 'Target: ')
      .replace(/(?<=：|: )(未验证|可连接|失败)/g, name => english[name]);
    if (context === 'cli') return text.replace('# 远端 Jupyter → 本机', '# Remote Jupyter → local')
      .replace('# 直接 TCP 转发', '# Direct TCP forwarding');
    return text;
  }
  if (typeof module !== 'undefined' && module.exports) { module.exports = { english, translate }; return; }
  let language = String(root.MacToysLanguage || navigator.language).startsWith('zh') ? 'zh-Hans' : 'en';
  const originalText = new WeakMap(), originalAttributes = new WeakMap();
  function context(element) {
    if (element.closest('.endpoint small')) return 'endpoint';
    if (element.closest('.card-meta')) return 'meta';
    if (element.closest('#delete-text')) return 'delete';
    if (element.closest('#detail-title')) return ['SSH 主机', '命令行速查'].includes(element.textContent) ? '' : 'title';
    if (element.closest('#detail-content pre')) {
      const text = element.textContent, title = document.getElementById('detail-title').textContent;
      if (['命令行速查', 'CLI Reference'].includes(title) && text.startsWith('portman list')) return 'cli';
      if (/( · 连接检查| · Connection check)$/.test(title) && /^(监听端口：|Listener: )/.test(text)) return 'check';
      return 'user';
    }
    if (element.closest('.card-identity h3,.host-chip,.card-error,.endpoint code,.route-connector,input,textarea,script,style')) return 'user';
    return '';
  }
  function updateText(node) {
    if (!node.parentElement) return;
    const kind = context(node.parentElement);
    if (kind === 'user') return;
    const old = originalText.get(node);
    const source = old && node.nodeValue === old.display ? old.source : node.nodeValue;
    const display = language === 'en' ? translate(source, kind) : source;
    originalText.set(node, { source, display });
    if (node.nodeValue !== display) node.nodeValue = display;
  }
  function updateAttributes(element) {
    for (const name of ['placeholder', 'aria-label', 'title']) {
      if (!element.hasAttribute(name)) continue;
      let saved = originalAttributes.get(element);
      if (!saved) { saved = {}; originalAttributes.set(element, saved); }
      const value = element.getAttribute(name), old = saved[name];
      const source = old && value === old.display ? old.source : value;
      const display = language === 'en' ? translate(source) : source;
      saved[name] = { source, display };
      if (value !== display) element.setAttribute(name, display);
    }
  }
  function walk(node) {
    if (node.nodeType === Node.TEXT_NODE) { updateText(node); return; }
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    updateAttributes(node);
    for (const child of node.childNodes) walk(child);
  }
  root.MacToysPortman = {
    setLanguage(value) {
      language = value.startsWith('zh') ? 'zh-Hans' : 'en';
      if (document.documentElement) { document.documentElement.lang = language; walk(document.documentElement); }
    }
  };
  function start() {
    root.MacToysPortman.setLanguage(language);
    new MutationObserver(changes => {
      for (const change of changes) {
        if (change.type === 'childList') for (const node of change.addedNodes) { if (node.isConnected) walk(node); }
        else if (change.type === 'characterData') updateText(change.target);
        else if (change.type === 'attributes') updateAttributes(change.target);
      }
    }).observe(document.documentElement, { subtree: true, childList: true, characterData: true, attributes: true,
      attributeFilter: ['placeholder', 'aria-label', 'title'] });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})(typeof window === 'undefined' ? globalThis : window);
