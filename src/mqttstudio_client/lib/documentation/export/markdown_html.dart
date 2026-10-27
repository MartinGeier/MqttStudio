import 'dart:convert';

// The Markdown of descriptions as HTML for the export: paragraphs, headings, lists, quotes, fenced code, and inline
// code, bold, italic and links. Raw HTML stays text, and links open only web and mail addresses or, written as
// [label](topic:path), the node of that path in the same export.
class MarkdownHtml {
  static final RegExp _fence = RegExp(r'^\s*(```|~~~)');
  static final RegExp _heading = RegExp(r'^\s*#{1,6}\s+(.*?)\s*#*\s*$');
  static final RegExp _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
  static final RegExp _numbered = RegExp(r'^\s*\d+[.)]\s+(.*)$');
  static final RegExp _quote = RegExp(r'^\s*>\s?(.*)$');
  static final RegExp _code = RegExp(r'`([^`]+)`');
  static final RegExp _link = RegExp(r'\[([^\]]+)\]\(([^)\s"]+)\)');
  static final RegExp _bareUrl = RegExp(r'(?<![\w/])(https?://[^\s<"\u0000]+?)([.,;:!?)]*)(?=\s|$|<|"|\u0000)');
  static final RegExp _bold = RegExp(r'\*\*(?=\S)(.+?)(?<=\S)\*\*|(?<!\w)__(?=\S)(.+?)(?<=\S)__(?!\w)');
  static final RegExp _italic = RegExp(r'(?<![*\w])\*(?=\S)(.+?)(?<=\S)\*(?![*\w])|(?<!\w)_(?=\S)(.+?)(?<=\S)_(?!\w)');
  static final RegExp _token = RegExp('\u0000(\\d+)\u0000');
  static const String topicScheme = 'topic:';

  // topicHref gives the anchor of a documented path, null when it is not in the export
  static String convert(String markdown, {String? Function(String path)? topicHref}) {
    var lines = const LineSplitter().convert(markdown.replaceAll('\u0000', '').trim());
    var out = StringBuffer();
    var paragraph = <String>[];
    var quote = <String>[];
    String? list;
    String inline(String text) => _inline(text, topicHref);

    void flush() {
      if (paragraph.isNotEmpty) {
        out.writeln('<p>${paragraph.map(inline).join('<br>')}</p>');
        paragraph.clear();
      }
      if (quote.isNotEmpty) {
        out.writeln('<blockquote>${quote.map(inline).join('<br>')}</blockquote>');
        quote.clear();
      }
      if (list != null) {
        out.writeln('</$list>');
        list = null;
      }
    }

    void listItem(String tag, String text) {
      if (list != tag) {
        flush();
        out.writeln('<$tag>');
        list = tag;
      }
      out.writeln('<li>${inline(text)}</li>');
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      Match? match;
      if (_fence.hasMatch(line)) {
        flush();
        var code = <String>[];
        for (i++; i < lines.length && !_fence.hasMatch(lines[i]); i++) {
          code.add(lines[i]);
        }
        out.writeln('<pre><code>${escape(code.join('\n'))}</code></pre>');
      } else if (line.trim().isEmpty) {
        flush();
      } else if ((match = _heading.firstMatch(line)) != null) {
        flush();
        out.writeln('<h4>${inline(match!.group(1)!)}</h4>');
      } else if ((match = _bullet.firstMatch(line)) != null) {
        listItem('ul', match!.group(1)!);
      } else if ((match = _numbered.firstMatch(line)) != null) {
        listItem('ol', match!.group(1)!);
      } else if ((match = _quote.firstMatch(line)) != null) {
        if (paragraph.isNotEmpty || list != null) {
          flush();
        }
        quote.add(match!.group(1)!);
      } else {
        if (quote.isNotEmpty || list != null) {
          flush();
        }
        paragraph.add(line.trim());
      }
    }
    flush();
    return out.toString();
  }

  // web and mail addresses only, never javascript: or data:
  static bool isSafeUrl(String url) => RegExp(r'^(https?:|mailto:)', caseSensitive: false).hasMatch(url.trim());

  static String escape(String text) => const HtmlEscape(HtmlEscapeMode.element).convert(text);

  static String attribute(String text) => const HtmlEscape(HtmlEscapeMode.attribute).convert(text);

  // code spans and links become placeholders first, so bold and italic never reach into them
  static String _inline(String text, String? Function(String path)? topicHref) {
    var tokens = <String>[];
    String keep(String html) {
      tokens.add(html);
      return '\u0000${tokens.length - 1}\u0000';
    }

    var html = text.replaceAllMapped(_code, (match) => keep('<code>${escape(match.group(1)!)}</code>'));
    html = html.replaceAllMapped(_link, (match) {
      var label = escape(match.group(1)!);
      var url = match.group(2)!;
      var href = url.startsWith(topicScheme) ? topicHref?.call(url.substring(topicScheme.length)) : url;
      if (href == null) {
        return keep(label);
      }
      return isSafeUrl(href) || href.startsWith('#') ? keep('<a href="${attribute(href)}">$label</a>') : keep(label);
    });
    html = escape(html).replaceAllMapped(_bareUrl, (match) {
      var url = match.group(1)!;
      return '${keep('<a href="$url">$url</a>')}${match.group(2)}';
    });
    html = html
        .replaceAllMapped(_bold, (match) => '<strong>${match.group(1) ?? match.group(2)}</strong>')
        .replaceAllMapped(_italic, (match) => '<em>${match.group(1) ?? match.group(2)}</em>');
    // a token can hold another one: a link's label can hold a code span
    while (_token.hasMatch(html)) {
      html = html.replaceAllMapped(_token, (match) => tokens[int.parse(match.group(1)!)]);
    }
    return html;
  }
}
