// A small, forgiving HTML parser — the same algorithm as the iOS app's
// Support/HTMLDocument.swift, ported so both implementations behave identically
// and can be tested against the same fixtures.
//
// The browser has DOMParser built in, but this is used instead for two reasons:
// the Node tests need it with no dependencies, and matching the Swift version
// exactly means a fixture that passes there passes here.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.CDT = Object.assign(root.CDT || {}, factory());
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const VOID_ELEMENTS = new Set([
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
    'link', 'meta', 'param', 'source', 'track', 'wbr'
  ]);

  const RAW_TEXT_ELEMENTS = new Set(['script', 'style', 'textarea', 'title']);

  // Tags that implicitly close a previous sibling of the same kind.
  const IMPLICITLY_CLOSING = {
    li: ['li'],
    p: ['p'],
    tr: ['tr'],
    td: ['td', 'th'],
    th: ['td', 'th'],
    option: ['option'],
    dt: ['dt', 'dd'],
    dd: ['dt', 'dd']
  };

  const NAMED_ENTITIES = {
    amp: '&', lt: '<', gt: '>', quot: '"', apos: "'",
    nbsp: ' ', mdash: '—', ndash: '–', hellip: '…',
    rsquo: '’', lsquo: '‘', ldquo: '“', rdquo: '”'
  };

  function decodeEntities(input) {
    if (!input || input.indexOf('&') === -1) return input;
    return input.replace(/&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g, function (match, body) {
      const lower = body.toLowerCase();
      if (NAMED_ENTITIES[lower] !== undefined) return NAMED_ENTITIES[lower];
      if (body[0] === '#') {
        const code = body[1] === 'x' || body[1] === 'X'
          ? parseInt(body.slice(2), 16)
          : parseInt(body.slice(1), 10);
        if (Number.isFinite(code) && code > 0 && code <= 0x10ffff) {
          try { return String.fromCodePoint(code); } catch (_) { return match; }
        }
      }
      return match;
    });
  }

  class HTMLNode {
    constructor(kind, name, attributes) {
      this.kind = kind;                     // 'document' | 'element' | 'text'
      this.tagName = name || null;
      this.attributes = attributes || {};
      this.children = [];
      this.parent = null;
      this.value = '';                      // text nodes only
    }

    append(child) {
      child.parent = this;
      this.children.push(child);
    }

    attribute(name) {
      const value = this.attributes[String(name).toLowerCase()];
      return value === undefined ? null : value;
    }

    get classNames() {
      return (this.attribute('class') || '').split(/\s+/).filter(Boolean);
    }

    hasClass(name) {
      const wanted = String(name).toLowerCase();
      return this.classNames.some((c) => c.toLowerCase() === wanted);
    }

    // All text beneath this node, whitespace collapsed. Script and style are
    // skipped: their contents are code, not prose.
    get text() {
      const pieces = [];
      (function collect(node) {
        if (node.kind === 'text') { pieces.push(node.value); return; }
        if (node.kind === 'element' && (node.tagName === 'script' || node.tagName === 'style')) return;
        node.children.forEach(collect);
      })(this);
      return pieces.join(' ').replace(/ /g, ' ').split(/\s+/).filter(Boolean).join(' ');
    }

    get descendants() {
      const out = [];
      (function walk(node) {
        for (const child of node.children) { out.push(child); walk(child); }
      })(this);
      return out;
    }

    elements(tag) {
      const wanted = String(tag).toLowerCase();
      return this.descendants.filter((n) => n.tagName === wanted);
    }

    firstElement(tag) {
      return this.elements(tag)[0] || null;
    }

    elementsWhere(predicate) {
      return this.descendants.filter((n) => n.kind === 'element' && predicate(n));
    }

    // Direct element children — what table walking wants, so a nested table's
    // cells are not mistaken for this row's.
    childElements(tag) {
      const wanted = tag ? String(tag).toLowerCase() : null;
      return this.children.filter((n) => n.kind === 'element' && (!wanted || n.tagName === wanted));
    }

    isDescendantOf(ancestor) {
      let current = this.parent;
      while (current) {
        if (current === ancestor) return true;
        current = current.parent;
      }
      return false;
    }
  }

  function parse(html) {
    const source = String(html == null ? '' : html);
    const root = new HTMLNode('document');
    const stack = [root];
    let index = 0;
    let textStart = 0;

    function flushText(end) {
      if (end <= textStart) return;
      const decoded = decodeEntities(source.slice(textStart, end));
      if (!decoded.trim()) return;
      const node = new HTMLNode('text');
      node.value = decoded;
      stack[stack.length - 1].append(node);
    }

    function indexAfter(from, needle) {
      const found = source.toLowerCase().indexOf(needle.toLowerCase(), from);
      return found === -1 ? source.length : found + needle.length;
    }

    while (index < source.length) {
      if (source[index] !== '<') { index += 1; continue; }

      if (source.startsWith('<!--', index)) {
        flushText(index);
        index = indexAfter(index + 4, '-->');
        textStart = index;
        continue;
      }
      if (source.startsWith('<!', index)) {
        flushText(index);
        index = indexAfter(index + 2, '>');
        textStart = index;
        continue;
      }

      if (source.startsWith('</', index)) {
        flushText(index);
        const match = /^<\/\s*([a-zA-Z0-9:_-]*)/.exec(source.slice(index));
        const name = match ? match[1].toLowerCase() : '';
        const end = indexAfter(index, '>');
        if (name) {
          for (let depth = stack.length - 1; depth > 0; depth -= 1) {
            if (stack[depth].tagName === name) { stack.length = depth; break; }
          }
        }
        index = end;
        textStart = index;
        continue;
      }

      const open = /^<\s*([a-zA-Z][a-zA-Z0-9:_-]*)/.exec(source.slice(index));
      if (!open) { index += 1; continue; }   // a bare '<' in prose is text
      flushText(index);

      const name = open[1].toLowerCase();
      let cursor = index + open[0].length;
      const attributes = {};
      let selfClosing = false;

      while (cursor < source.length) {
        while (cursor < source.length && /\s/.test(source[cursor])) cursor += 1;
        if (cursor >= source.length) break;
        if (source[cursor] === '>') { cursor += 1; break; }
        if (source[cursor] === '/') { selfClosing = true; cursor += 1; continue; }

        let attrName = '';
        while (cursor < source.length && !/[\s=>/]/.test(source[cursor])) {
          attrName += source[cursor];
          cursor += 1;
        }
        if (!attrName) { cursor += 1; continue; }

        while (cursor < source.length && /\s/.test(source[cursor])) cursor += 1;
        let value = '';
        if (source[cursor] === '=') {
          cursor += 1;
          while (cursor < source.length && /\s/.test(source[cursor])) cursor += 1;
          const quote = source[cursor];
          if (quote === '"' || quote === "'") {
            cursor += 1;
            while (cursor < source.length && source[cursor] !== quote) { value += source[cursor]; cursor += 1; }
            if (cursor < source.length) cursor += 1;
          } else {
            while (cursor < source.length && !/[\s>]/.test(source[cursor])) { value += source[cursor]; cursor += 1; }
          }
        }
        attributes[attrName.toLowerCase()] = decodeEntities(value);
      }

      const closes = IMPLICITLY_CLOSING[name];
      if (closes) {
        for (let depth = stack.length - 1; depth > 0; depth -= 1) {
          if (closes.indexOf(stack[depth].tagName) !== -1) { stack.length = depth; break; }
        }
      }

      const element = new HTMLNode('element', name, attributes);
      stack[stack.length - 1].append(element);

      if (RAW_TEXT_ELEMENTS.has(name)) {
        const closing = '</' + name;
        const contentEnd = source.toLowerCase().indexOf(closing, cursor);
        const stop = contentEnd === -1 ? source.length : contentEnd;
        if (stop > cursor && (name === 'title' || name === 'textarea')) {
          const node = new HTMLNode('text');
          node.value = decodeEntities(source.slice(cursor, stop));
          element.append(node);
        }
        index = indexAfter(stop, '>');
        textStart = index;
        continue;
      }

      if (!selfClosing && !VOID_ELEMENTS.has(name)) stack.push(element);
      index = cursor;
      textStart = index;
    }

    flushText(source.length);
    return root;
  }

  function plainText(html) {
    const text = parse(html).text;
    return text || null;
  }

  return { HTMLNode, parseHTML: parse, decodeEntities, plainText };
}));
