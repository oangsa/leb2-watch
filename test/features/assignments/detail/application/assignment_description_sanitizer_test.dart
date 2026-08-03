import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/detail/application/assignment_description_sanitizer.dart';

void main() {
  const sanitizer = AssignmentDescriptionSanitizer();

  test('keeps plain text and readable block, line, and list boundaries', () {
    expect(sanitizer.toPlainText('Plain text'), 'Plain text');
    expect(
      sanitizer.toPlainText(
        '<p>First</p><p>Second<br>line</p>'
        '<ul><li>One</li><li>Two</li></ul>',
      ),
      'First\n\nSecond\nline\n\n• One\n• Two',
    );
  });

  test('decodes named and numeric entities', () {
    expect(
      sanitizer.toPlainText('Tom &amp; Jerry &#x2014; &#169;'),
      'Tom & Jerry — ©',
    );
  });

  test(
    'preserves readable boundaries from visible inline to block content',
    () {
      expect(
        sanitizer.toPlainText('<a href="/ignored">before</a><p>after</p>'),
        'before\n\nafter',
      );
      expect(
        sanitizer.toPlainText('<span>before</span><div>after</div>'),
        'before\n\nafter',
      );
      expect(
        sanitizer.toPlainText(
          '<p>before</p><a href="/ignored">middle</a><p>after</p>',
        ),
        'before\n\nmiddle\n\nafter',
      );
    },
  );

  test(
    'keeps a block boundary across discarded hidden and embedded subtrees',
    () {
      expect(
        sanitizer.toPlainText(
          '<a href="/ignored">before</a>'
          '<span hidden>PRIVATE_HIDDEN</span>'
          '<iframe><b>PRIVATE_EMBEDDED</b></iframe>'
          '<p>after</p>',
        ),
        'before\n\nafter',
      );
    },
  );

  test('nested and empty blocks add no leading or duplicate blank lines', () {
    expect(sanitizer.toPlainText('<div><p>inside</p></div>'), 'inside');
    expect(sanitizer.toPlainText('<p></p><div>after</div>'), 'after');
    expect(
      sanitizer.toPlainText(
        '<span>before</span><div><p></p><section>after</section></div>',
      ),
      'before\n\nafter',
    );
    expect(
      sanitizer.toPlainText('<p>before</p><div></div><p>after</p>'),
      'before\n\nafter',
    );
  });

  test('discards active non-content elements and keeps inert anchor text', () {
    const source =
        '<p onclick="steal()">Safe<a href="javascript:steal()"> link</a>'
        '<script>SECRET_SCRIPT</script><style>SECRET_STYLE</style>'
        '<template>SECRET_TEMPLATE</template>'
        '<noscript>SECRET_NOSCRIPT</noscript><!-- SECRET_COMMENT -->'
        '<p>Tail';

    final result = sanitizer.toPlainText(source);

    expect(result, 'Safe link\n\nTail');
    expect(result, isNot(contains('SECRET')));
    expect(result, isNot(contains('javascript')));
    expect(result, isNot(contains('href')));
  });

  test(
    'discards nested boolean and aria hidden subtrees but keeps siblings',
    () {
      const source =
          '<p>Before</p>'
          '<div hidden><span>PRIVATE_NESTED</span></div>'
          '<span hidden="false">PRIVATE_BOOLEAN</span>'
          '<span aria-hidden=" TRUE "><b>PRIVATE_ARIA</b></span>'
          '<p aria-hidden="false">Visible aria</p>'
          '<p>After';

      final result = sanitizer.toPlainText(source);

      expect(result, 'Before\n\nVisible aria\n\nAfter');
      expect(result, isNot(contains('PRIVATE')));
    },
  );

  test(
    'discards robust inline hidden styles without hiding visible styles',
    () {
      const source =
          '<span style=" DISPLAY : NoNe !important ">PRIVATE_DISPLAY</span>'
          '<div style="visibility:\tHIDDEN;">PRIVATE_VISIBILITY</div>'
          '<p style="content-visibility : hidden">PRIVATE_CONTENT</p>'
          '<span style="display:/* comment */ none">PRIVATE_COMMENT</span>'
          '<span style="display:inline; visibility:visible">'
          'Visible style</span>';

      final result = sanitizer.toPlainText(source);

      expect(result, 'Visible style');
      expect(result, isNot(contains('PRIVATE')));
    },
  );

  test('discards embedded containers from a malformed visible fragment', () {
    const source =
        '<p>Before</p><iframe><b>PRIVATE_IFRAME</b></iframe>'
        '<object><span>PRIVATE_OBJECT</span></object>'
        '<embed src="private"><svg><text>PRIVATE_SVG</text></svg>'
        '<canvas>PRIVATE_CANVAS</canvas><p>After';

    final result = sanitizer.toPlainText(source);

    expect(result, 'Before\n\nAfter');
    expect(result, isNot(contains('PRIVATE')));
  });

  test(
    'returns null for empty or markup-only input without leaking source',
    () {
      expect(sanitizer.toPlainText(' \n '), isNull);
      expect(
        sanitizer.toPlainText('<script>private</script><!--private-->'),
        isNull,
      );
      expect(
        sanitizer.toString(),
        'AssignmentDescriptionSanitizer(redacted: true)',
      );
    },
  );
}
