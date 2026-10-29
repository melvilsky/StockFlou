import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/features/generation/domain/metadata_generation_operation.dart';

void main() {
  group('MetadataGenerationContext', () {
    test('freezes fields and copyWith produces immutable copy', () {
      final initialDate = DateTime(2026, 10, 25);
      final ctx = MetadataGenerationContext(
        targetId: 'file-1',
        targetPath: '/photos/photo1.jpg',
        userContext: 'Studio portrait of a cat',
        apiKey: 'test-key',
        keywordCount: 20,
        isEditorial: true,
        city: 'Berlin',
        country: 'Germany',
        date: initialDate,
      );

      expect(ctx.targetId, 'file-1');
      expect(ctx.targetPath, '/photos/photo1.jpg');
      expect(ctx.userContext, 'Studio portrait of a cat');
      expect(ctx.apiKey, 'test-key');
      expect(ctx.keywordCount, 20);
      expect(ctx.isEditorial, isTrue);
      expect(ctx.city, 'Berlin');
      expect(ctx.country, 'Germany');
      expect(ctx.date, initialDate);

      final enriched = ctx.copyWith(city: 'Hamburg', country: 'Germany');

      expect(enriched.city, 'Hamburg');
      // Original remains untouched
      expect(ctx.city, 'Berlin');
      expect(ctx.targetPath, '/photos/photo1.jpg');
    });

    test('formattedUserContext trims and truncates to 150 chars max', () {
      const emptyCtx = MetadataGenerationContext(
        targetPath: '/p.jpg',
        userContext: '   ',
        apiKey: 'k',
        keywordCount: 15,
        isEditorial: false,
      );
      expect(emptyCtx.formattedUserContext, isNull);

      const shortCtx = MetadataGenerationContext(
        targetPath: '/p.jpg',
        userContext: '  Short description  ',
        apiKey: 'k',
        keywordCount: 15,
        isEditorial: false,
      );
      expect(shortCtx.formattedUserContext, 'Short description');

      final longText = 'A' * 160;
      final longCtx = MetadataGenerationContext(
        targetPath: '/p.jpg',
        userContext: longText,
        apiKey: 'k',
        keywordCount: 15,
        isEditorial: false,
      );
      final formatted = longCtx.formattedUserContext!;
      expect(formatted.length, 150);
      expect(formatted.endsWith('...'), isTrue);
      expect(formatted, '${'A' * 147}...');
    });

    test('formatFinalTitle formats editorial title with location and date', () {
      final date = DateTime(2026, 5, 12);
      final ctx = MetadataGenerationContext(
        targetPath: '/p.jpg',
        userContext: '',
        apiKey: 'k',
        keywordCount: 15,
        isEditorial: true,
        city: 'Everett',
        country: 'Washington',
        date: date,
      );

      final title = ctx.formatFinalTitle('Scenic mountain view');
      expect(title, 'Scenic mountain view - Everett, Washington. May 12 2026.');
    });

    test('formatFinalTitle keeps raw title when isEditorial is false', () {
      final ctx = MetadataGenerationContext(
        targetPath: '/p.jpg',
        userContext: '',
        apiKey: 'k',
        keywordCount: 15,
        isEditorial: false,
        city: 'Everett',
        country: 'Washington',
      );

      final title = ctx.formatFinalTitle('Scenic mountain view');
      expect(title, 'Scenic mountain view');
    });
  });

  group('appendEditorialToTitle', () {
    test('handles trailing period in title cleanly', () {
      final result = appendEditorialToTitle(
        title: 'Sunset over ocean.',
        city: 'San Diego',
        country: 'California',
        date: DateTime(2026, 7, 4),
      );
      expect(result, 'Sunset over ocean - San Diego, California. July 4 2026.');
    });

    test('does not duplicate suffix if already present', () {
      final date = DateTime(2026, 7, 4);
      final result1 = appendEditorialToTitle(
        title: 'Sunset over ocean',
        city: 'San Diego',
        country: 'California',
        date: date,
      );
      final result2 = appendEditorialToTitle(
        title: result1,
        city: 'San Diego',
        country: 'California',
        date: date,
      );
      expect(result2, result1);
    });

    test(
      'metadataTitleForWrite keeps editorial city and country in the title',
      () {
        final written = metadataTitleForWrite(
          title: 'Protest in the square',
          isEditorial: true,
          city: 'Berlin',
          country: 'Germany',
          editorialDateMillis: DateTime(2026, 10, 25).millisecondsSinceEpoch,
        );
        expect(
          written,
          'Protest in the square - Berlin, Germany. October 25 2026.',
        );

        final again = metadataTitleForWrite(
          title: written,
          isEditorial: true,
          city: 'Berlin',
          country: 'Germany',
          editorialDateMillis: DateTime(2026, 10, 25).millisecondsSinceEpoch,
        );
        expect(again, written);
      },
    );

    test('metadataTitleForWrite leaves a non-editorial title unchanged', () {
      expect(
        metadataTitleForWrite(
          title: 'Studio portrait',
          isEditorial: false,
          city: 'Berlin',
          country: 'Germany',
        ),
        'Studio portrait',
      );
    });

    test('formats title with city only or date only', () {
      final cityOnly = appendEditorialToTitle(
        title: 'Street musician',
        city: 'Prague',
        country: '',
        date: null,
      );
      expect(cityOnly, 'Street musician - Prague.');

      final dateOnly = appendEditorialToTitle(
        title: 'Street musician',
        city: '',
        country: '',
        date: DateTime(2026, 1, 1),
      );
      expect(dateOnly, 'Street musician. January 1 2026.');
    });
  });
}
