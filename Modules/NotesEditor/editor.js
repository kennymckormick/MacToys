import { Editor, rootCtx, defaultValueCtx, editorViewCtx, editorViewOptionsCtx } from '@milkdown/kit/core';
import { commonmark, toggleStrongCommand, toggleEmphasisCommand, wrapInHeadingCommand, wrapInBulletListCommand,
  wrapInOrderedListCommand, wrapInBlockquoteCommand, createCodeBlockCommand, turnIntoTextCommand } from '@milkdown/kit/preset/commonmark';
import { gfm } from '@milkdown/kit/preset/gfm';
import { history } from '@milkdown/kit/plugin/history';
import { clipboard } from '@milkdown/kit/plugin/clipboard';
import { getMarkdown, replaceAll, callCommand } from '@milkdown/kit/utils';
import { TextSelection } from '@milkdown/kit/prose/state';

let editor, current = null, suppressed = false, sourceMode = false, cachedMarkdown = "";
const source = document.querySelector('#source');
const surface = document.querySelector('#editor');
const toolbar = document.querySelector('#toolbar');
const errorBox = document.querySelector('#error');
const labels = {
  en: ['Heading', 'Bold', 'Italic', 'Bullet list', 'Numbered list', 'Quote', 'Code block', 'Markdown source', 'Rich text', 'Editor could not load. Your saved note is unchanged.'],
  zh: ['标题', '加粗', '斜体', '无序列表', '有序列表', '引用', '代码块', 'Markdown 源码', '所见即所得', '编辑器加载失败，已保存的笔记保持不变。']
};
let words = labels.en;
function post(value) { window.webkit?.messageHandlers?.notes?.postMessage(value); }
function markdown() { return sourceMode ? source.value : editor.action(getMarkdown()); }
function snapshot() { return current ? { type: 'change', id: current.id, epoch: current.epoch, markdown: cachedMarkdown } : null; }
function changed() { if (!suppressed && current) { cachedMarkdown = markdown(); post(snapshot()); } }
function fail() { errorBox.hidden = false; errorBox.textContent = words[9]; post({ type: 'error' }); }
const ready = Editor.make().config(ctx => {
  ctx.set(rootCtx, surface); ctx.set(defaultValueCtx, '');
  ctx.update(editorViewOptionsCtx, options => ({ ...options,
    // Publish every document transaction immediately. Disk writes are debounced in the native store.
    dispatchTransaction(transaction) {
      const result = this.state.applyTransaction(transaction);
      this.updateState(result.state);
      if (result.transactions.some(item => item.docChanged) && editor) changed();
    },
    handleDOMEvents: {
      click(view, event) {
        const link = event.target.closest?.('a');
        if (link) { event.preventDefault(); post({ type: 'link', url: link.getAttribute('href') }); return true; }
        const task = event.target.closest?.('li[data-item-type="task"]');
        if (task && event.clientX < task.getBoundingClientRect().left) {
          const pos = view.posAtDOM(task, 0), $pos = view.state.doc.resolve(pos);
          for (let depth = $pos.depth; depth > 0; depth--) {
            const node = $pos.node(depth);
            if (node.type.name === 'list_item' && node.attrs.checked != null) {
              view.dispatch(view.state.tr.setNodeMarkup($pos.before(depth), null, { ...node.attrs, checked: !node.attrs.checked })); return true;
            }
          }
        }
        return false;
      },
      drop(_view, event) { if (event.dataTransfer?.files.length) { event.preventDefault(); return true; } return false; }
    }
  }));
}).use(commonmark).use(gfm).use(history).use(clipboard).create().then(value => {
  editor = value; post({ type: 'ready' });
}).catch(fail);

function run(command, value) {
  if (!editor || sourceMode) return false;
  editor.action(ctx => ctx.get(editorViewCtx).focus());
  return editor.action(callCommand(command.key, value));
}
function buildToolbar(language) {
  words = language.startsWith('zh') ? labels.zh : labels.en;
  document.documentElement.lang = language; toolbar.replaceChildren();
  const commands = [
    ['H', () => editor.action(ctx => ctx.get(editorViewCtx).state.selection.$from.parent.type.name) === 'heading' ? run(turnIntoTextCommand) : run(wrapInHeadingCommand, 2)], ['B', () => run(toggleStrongCommand)],
    ['I', () => run(toggleEmphasisCommand)], ['•', () => run(wrapInBulletListCommand)],
    ['1.', () => run(wrapInOrderedListCommand)], ['❯', () => run(wrapInBlockquoteCommand)],
    ['{ }', () => run(createCodeBlockCommand)]
  ];
  commands.forEach(([text, action], index) => {
    const button = document.createElement('button'); button.textContent = text;
    button.title = words[index]; button.setAttribute('aria-label', words[index]);
    button.disabled = sourceMode; button.addEventListener('mousedown', event => event.preventDefault());
    button.addEventListener('click', action); toolbar.append(button);
  });
  const toggle = document.createElement('button'); toggle.id = 'source-toggle';
  toggle.textContent = sourceMode ? 'Aa' : '</>'; toggle.title = words[sourceMode ? 8 : 7];
  toggle.setAttribute('aria-label', toggle.title); toggle.setAttribute('aria-pressed', String(sourceMode));
  toggle.addEventListener('click', () => setSource(!sourceMode)); toolbar.append(toggle);
}
function setSource(enabled) {
  if (enabled === sourceMode || !editor) return;
  suppressed = true;
  try {
    if (enabled) source.value = markdown();
    else editor.action(replaceAll(source.value, true));
    sourceMode = enabled; source.hidden = !enabled; surface.hidden = enabled;
    buildToolbar(current?.language || 'en');
  } finally { suppressed = false; }
  changed();
}
source.addEventListener('input', changed);
source.addEventListener('keydown', event => {
  if (event.key === 'Tab') { event.preventDefault(); source.setRangeText('  ', source.selectionStart, source.selectionEnd, 'end'); changed(); }
});
window.MacToysNotes = {
  async load(value) {
    await ready; if (!editor) return false;
    suppressed = true;
    try {
      current = value; cachedMarkdown = value.markdown; errorBox.hidden = true;
      source.value = value.markdown;
      editor.action(replaceAll(value.markdown, true));
      buildToolbar(value.language || 'en');
      // Loaded Markdown is kept verbatim until an actual edit occurs.
      return true;
    } catch { fail(); return false; }
    finally { suppressed = false; }
  },
  snapshot, setSource,
  // Small bridge also used by the offscreen WebKit regression checks. No filesystem or network access.
  command(name) {
    const commands = { bold: toggleStrongCommand, italic: toggleEmphasisCommand, bullet: wrapInBulletListCommand,
      numbered: wrapInOrderedListCommand, quote: wrapInBlockquoteCommand, code: createCodeBlockCommand, paragraph: turnIntoTextCommand };
    return commands[name] ? run(commands[name]) : false;
  },
  select(from, to = from) { editor.action(ctx => { const view = ctx.get(editorViewCtx); view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, from, to))); }); },
  insert(text) { editor.action(ctx => { const view = ctx.get(editorViewCtx); view.dispatch(view.state.tr.insertText(text)); }); }
};
