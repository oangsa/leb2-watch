import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

final class AssignmentDescriptionSanitizer {
  const AssignmentDescriptionSanitizer();

  String? toPlainText(String source) {
    final fragment = html_parser.parseFragment(source);
    final output = StringBuffer();
    for (final node in fragment.nodes) {
      _appendNode(node, output);
    }
    final normalized = _normalize(output.toString());
    return normalized.isEmpty ? null : normalized;
  }

  void _appendNode(Node node, StringBuffer output) {
    if (node is Text) {
      output.write(node.data);
      return;
    }
    if (node is! Element) {
      return;
    }
    final tag = node.localName;
    if (_discardedElements.contains(tag) || _isSemanticallyHidden(node)) {
      return;
    }
    if (tag == 'br') {
      output.write('\n');
      return;
    }
    if (tag == 'li') {
      _ensureLineStart(output);
      output.write('• ');
    } else if (_blockElements.contains(tag)) {
      _ensureParagraphBoundary(output);
    }
    for (final child in node.nodes) {
      _appendNode(child, output);
    }
    if (tag == 'li') {
      output.write('\n');
    } else if (_blockElements.contains(tag)) {
      _ensureParagraphBoundary(output);
    }
  }

  void _ensureLineStart(StringBuffer output) {
    if (output.isNotEmpty && !output.toString().endsWith('\n')) {
      output.write('\n');
    }
  }

  void _ensureParagraphBoundary(StringBuffer output) {
    if (output.isEmpty) {
      return;
    }
    final value = output.toString();
    if (value.endsWith('\n\n')) {
      return;
    }
    output.write(value.endsWith('\n') ? '\n' : '\n\n');
  }

  String _normalize(String value) {
    final lines = value
        .replaceAll('\u00a0', ' ')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.replaceAll(RegExp(r'[ \t\f]+'), ' ').trim())
        .toList();
    final normalized = <String>[];
    for (final line in lines) {
      if (line.isEmpty && (normalized.isEmpty || normalized.last.isEmpty)) {
        continue;
      }
      normalized.add(line);
    }
    while (normalized.isNotEmpty && normalized.last.isEmpty) {
      normalized.removeLast();
    }
    return normalized.join('\n');
  }

  @override
  String toString() => 'AssignmentDescriptionSanitizer(redacted: true)';
}

bool _isSemanticallyHidden(Element element) {
  if (element.attributes.containsKey('hidden')) {
    return true;
  }
  final ariaHidden = element.attributes['aria-hidden'];
  if (ariaHidden != null && ariaHidden.trim().toLowerCase() == 'true') {
    return true;
  }
  return _hasHiddenInlineStyle(element.attributes['style']);
}

bool _hasHiddenInlineStyle(String? source) {
  if (source == null) {
    return false;
  }
  final withoutComments = source.replaceAll(_cssComment, ' ');
  for (final declaration in withoutComments.split(';')) {
    final separator = declaration.indexOf(':');
    if (separator <= 0) {
      continue;
    }
    final property = declaration.substring(0, separator).trim().toLowerCase();
    final rawValue = declaration.substring(separator + 1);
    final important = rawValue.indexOf('!');
    final value = (important < 0 ? rawValue : rawValue.substring(0, important))
        .trim()
        .toLowerCase();
    if ((property == 'display' && value == 'none') ||
        (property == 'visibility' && value == 'hidden') ||
        (property == 'content-visibility' && value == 'hidden')) {
      return true;
    }
  }
  return false;
}

final _cssComment = RegExp(r'/\*.*?\*/', dotAll: true);
const _discardedElements = {
  'script',
  'style',
  'template',
  'noscript',
  'iframe',
  'object',
  'embed',
  'svg',
  'canvas',
};
const _blockElements = {
  'address',
  'article',
  'aside',
  'blockquote',
  'div',
  'dl',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'ul',
};
