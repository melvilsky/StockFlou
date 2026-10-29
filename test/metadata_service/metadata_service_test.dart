import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/core/services/metadata_service.dart';

/// Records the arguments passed to the fake process runner so tests can
/// assert on the exact command line the service builds.
class _FakeRunner {
  _FakeRunner(this._response);

  final Future<ProcessResult> Function(String executable, List<String> args)
  _response;

  final List<String> capturedExecutable = [];
  final List<List<String>> capturedArgs = [];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    capturedExecutable.add(executable);
    capturedArgs.add(List<String>.of(arguments));
    return _response(executable, arguments);
  }

  List<String> get lastArgs => capturedArgs.last;
}

ProcessResult _ok(String stdout, {String stderr = ''}) =>
    ProcessResult(1, 0, stdout, stderr);

ProcessResult _fail(int exitCode, String stderr) =>
    ProcessResult(1, exitCode, '', stderr);

String _jsonTags(Map<String, Object?> tags) {
  final data = <String, Object?>{'SourceFile': '/fake/file.jpg', ...tags};
  return jsonEncode(<dynamic>[data]);
}

void main() {
  group('writeMetadataDetailed argument building', () {
    test(
      'description == null does not include description change args',
      () async {
        final runner = _FakeRunner(
          (executable, args) async => _ok('1 image files updated'),
        );

        final result = await MetadataService.writeMetadataDetailed(
          filePath: '/dir/file.jpg',
          title: 'T',
          keywords: 'k1, k2',
          description: null,
          runProcess: runner.call,
        );

        expect(result.success, isTrue);
        final args = runner.lastArgs;
        expect(args.where((a) => a.startsWith('-Caption-Abstract=')), isEmpty);
        expect(args.where((a) => a.startsWith('-Description=')), isEmpty);
        expect(args.where((a) => a.startsWith('-ImageDescription=')), isEmpty);
        // Title and keywords are still written.
        expect(args, contains('-ObjectName=T'));
        expect(args, contains('-Title=T'));
        expect(args, contains('-Keywords=k1'));
        expect(args, contains('-Subject=k2'));
        expect(args.last, '/dir/file.jpg');
      },
    );

    test(
      "description == '' clears every description field used by writes",
      () async {
        final runner = _FakeRunner(
          (executable, args) async => _ok('1 image files updated'),
        );

        final result = await MetadataService.writeMetadataDetailed(
          filePath: '/dir/file.jpg',
          title: 'T',
          keywords: '',
          description: '',
          runProcess: runner.call,
        );

        expect(result.success, isTrue);
        expect(
          runner.lastArgs,
          containsAllInOrder(<String>[
            '-Caption-Abstract=',
            '-Description=',
            '-ImageDescription=',
          ]),
        );
      },
    );

    test(
      'non-empty description is written whole with Unicode, quotes, newline',
      () async {
        const value = '«цитата» "quoted" line1\nline2';
        final runner = _FakeRunner(
          (executable, args) async => _ok('1 image files updated'),
        );

        final result = await MetadataService.writeMetadataDetailed(
          filePath: '/dir/file.jpg',
          title: 'Титл',
          keywords: '',
          description: value,
          runProcess: runner.call,
        );

        expect(result.success, isTrue);
        expect(runner.capturedExecutable, ['exiftool']);
        final args = runner.lastArgs;
        // Each description field keeps the value as a single argument.
        expect(
          args.where((a) => a.startsWith('-Caption-Abstract=')),
          equals(['-Caption-Abstract=$value']),
        );
        expect(
          args.where((a) => a.startsWith('-Description=')),
          equals(['-Description=$value']),
        );
        expect(
          args.where((a) => a.startsWith('-ImageDescription=')),
          equals(['-ImageDescription=$value']),
        );
      },
    );

    test(
      'path with spaces and special characters stays one argument',
      () async {
        const path = '/Users/u/My Photos/фото (1) [final].jpg';
        final runner = _FakeRunner(
          (executable, args) async => _ok('1 image files updated'),
        );

        await MetadataService.writeMetadataDetailed(
          filePath: path,
          title: 'T',
          keywords: '',
          runProcess: runner.call,
        );

        expect(runner.lastArgs.last, path);
        expect(runner.lastArgs.where((a) => a == path).length, 1);
      },
    );

    test(
      'shoot date is written as a calendar date and omitted when null',
      () async {
        final runner = _FakeRunner(
          (executable, args) async => _ok('1 image files updated'),
        );

        await MetadataService.writeMetadataDetailed(
          filePath: '/dir/file.jpg',
          title: 'T',
          keywords: '',
          shootDate: DateTime(2026, 10, 25, 14, 30),
          runProcess: runner.call,
        );

        expect(runner.lastArgs, contains('-IPTC:DateCreated=2026:10:25'));
        expect(
          runner.lastArgs,
          contains('-XMP-photoshop:DateCreated=2026:10:25'),
        );
        expect(
          runner.lastArgs.where((a) => a.startsWith('-DateTimeOriginal')),
          isEmpty,
        );

        await MetadataService.writeMetadataDetailed(
          filePath: '/dir/file.jpg',
          title: 'T',
          keywords: '',
          runProcess: runner.call,
        );
        expect(
          runner.lastArgs.where((a) => a.contains('DateCreated')),
          isEmpty,
        );
      },
    );

    test('city and country are written, and omitted when null', () async {
      final runner = _FakeRunner(
        (executable, args) async => _ok('1 image files updated'),
      );

      await MetadataService.writeMetadataDetailed(
        filePath: '/dir/file.jpg',
        title: 'T',
        keywords: '',
        city: 'São Paulo',
        country: 'Brazil',
        runProcess: runner.call,
      );

      expect(runner.lastArgs, contains('-IPTC:City=São Paulo'));
      expect(runner.lastArgs, contains('-XMP-photoshop:City=São Paulo'));
      expect(
        runner.lastArgs,
        contains('-IPTC:Country-PrimaryLocationName=Brazil'),
      );
      expect(runner.lastArgs, contains('-XMP-photoshop:Country=Brazil'));

      await MetadataService.writeMetadataDetailed(
        filePath: '/dir/file.jpg',
        title: 'T',
        keywords: '',
        runProcess: runner.call,
      );
      expect(
        runner.lastArgs.where(
          (a) => a.contains('City') || a.contains('Country'),
        ),
        isEmpty,
      );
    });

    test('keyword phrase order is preserved, empty items dropped', () async {
      final runner = _FakeRunner(
        (executable, args) async => _ok('1 image files updated'),
      );

      await MetadataService.writeMetadataDetailed(
        filePath: '/dir/file.jpg',
        title: 'T',
        keywords: 'nested phrase, , city,  ',
        runProcess: runner.call,
      );

      final args = runner.lastArgs;
      // Existing keywords are cleared first, then written individually
      // in the input order.
      expect(
        args.where((a) => a.startsWith('-Keywords=')),
        equals(['-Keywords=', '-Keywords=nested phrase', '-Keywords=city']),
      );
      expect(
        args.where((a) => a.startsWith('-Subject=')),
        equals(['-Subject=', '-Subject=nested phrase', '-Subject=city']),
      );
    });
  });

  group('writeMetadataDetailed result reporting', () {
    test('non-zero exit code fails with the ExifTool reason', () async {
      final runner = _FakeRunner(
        (executable, args) async => _fail(1, 'Error: Bad data field\n'),
      );

      final result = await MetadataService.writeMetadataDetailed(
        filePath: '/dir/file.jpg',
        title: 'T',
        keywords: '',
        runProcess: runner.call,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Error: Bad data field'));
    });

    test('non-zero exit code without stderr reports the exit code', () async {
      final runner = _FakeRunner((executable, args) async => _fail(2, ''));

      final result = await MetadataService.writeMetadataDetailed(
        filePath: '/dir/file.jpg',
        title: 'T',
        keywords: '',
        runProcess: runner.call,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, 'exiftool exited with code 2');
    });

    test('exit code 0 with a warning in stderr stays a success', () async {
      final runner = _FakeRunner(
        (executable, args) async =>
            _ok('1 image files updated', stderr: 'Warning: minor issue\n'),
      );

      final result = await MetadataService.writeMetadataDetailed(
        filePath: '/dir/file.jpg',
        title: 'T',
        keywords: '',
        runProcess: runner.call,
      );

      expect(result.success, isTrue);
      expect(result.errorMessage, isNull);
    });

    test('unlaunchable exiftool fails with the OS message', () async {
      final runner = _FakeRunner(
        (executable, args) =>
            throw const ProcessException('exiftool', [], 'No such file', 2),
      );

      final result = await MetadataService.writeMetadataDetailed(
        filePath: '/dir/file.jpg',
        title: 'T',
        keywords: '',
        runProcess: runner.call,
      );

      expect(result.success, isFalse);
      expect(
        result.errorMessage,
        contains('Failed to run exiftool: No such file'),
      );
    });
  });

  group('readMetadata parsing', () {
    test(
      'prefers the non-empty XMP value, degrades to IPTC, then EXIF',
      () async {
        final runner = _FakeRunner(
          (executable, args) async => _ok(
            _jsonTags(const <String, Object?>{
              'XMP:Title': 'xmp title',
              'IPTC:ObjectName': 'iptc title',
              'XMP:Description': 'xmp desc',
              'IPTC:Caption-Abstract': 'iptc desc',
              'EXIF:ImageDescription': 'exif desc',
              'XMP:Subject': <String>['xmp k1', 'xmp k2'],
              'IPTC:Keywords': <String>['iptc k1'],
            }),
          ),
        );

        final result = await MetadataService.readMetadata(
          filePath: '/fake/file.jpg',
          runProcess: runner.call,
        );

        expect(result.success, isTrue);
        expect(result.title, 'xmp title');
        expect(result.description, 'xmp desc');
        expect(result.keywords, ['xmp k1', 'xmp k2']);
      },
    );

    test('falls back to IPTC when XMP has no value', () async {
      final runner = _FakeRunner(
        (executable, args) async => _ok(
          _jsonTags(const <String, Object?>{
            'IPTC:ObjectName': 'Object Name',
            'IPTC:Caption-Abstract': 'Caption line',
            'IPTC:Keywords': <String>['a', 'two words', 'c'],
          }),
        ),
      );

      final result = await MetadataService.readMetadata(
        filePath: '/fake/file.jpg',
        runProcess: runner.call,
      );

      expect(result.success, isTrue);
      expect(result.title, 'Object Name');
      expect(result.description, 'Caption line');
      // Multi-word phrases stay one item, order preserved.
      expect(result.keywords, ['a', 'two words', 'c']);
    });

    test(
      'falls back to EXIF ImageDescription when IPTC/XMP are empty',
      () async {
        final runner = _FakeRunner(
          (executable, args) async => _ok(
            _jsonTags(const <String, Object?>{
              'EXIF:ImageDescription': 'Only EXIF',
            }),
          ),
        );

        final result = await MetadataService.readMetadata(
          filePath: '/fake/file.jpg',
          runProcess: runner.call,
        );

        expect(result.success, isTrue);
        expect(result.description, 'Only EXIF');
        expect(result.title, isNull);
        expect(result.keywords, isEmpty);
      },
    );

    test('single string keyword value becomes one keyword item', () async {
      final runner = _FakeRunner(
        (executable, args) async => _ok(
          _jsonTags(const <String, Object?>{'IPTC:Keywords': 'single phrase'}),
        ),
      );

      final result = await MetadataService.readMetadata(
        filePath: '/fake/file.jpg',
        runProcess: runner.call,
      );

      expect(result.success, isTrue);
      expect(result.keywords, ['single phrase']);
    });

    test(
      'file without core metadata reads as success with empty fields',
      () async {
        final runner = _FakeRunner(
          (executable, args) async => _ok(
            jsonEncode(<dynamic>[
              {'SourceFile': '/fake/file.jpg'},
            ]),
          ),
        );

        final result = await MetadataService.readMetadata(
          filePath: '/fake/file.jpg',
          runProcess: runner.call,
        );

        expect(result.success, isTrue);
        expect(result.title, isNull);
        expect(result.description, isNull);
        expect(result.keywords, isEmpty);
        expect(result.errorMessage, isNull);
      },
    );

    test('corrupt JSON output fails', () async {
      final runner = _FakeRunner(
        (executable, args) async => _ok('[{"SourceFile":'),
      );

      final result = await MetadataService.readMetadata(
        filePath: '/fake/file.jpg',
        runProcess: runner.call,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
    });

    test('unexpected root type fails', () async {
      final runner = _FakeRunner(
        (executable, args) async => _ok('{"SourceFile": "/fake/file.jpg"}'),
      );

      final result = await MetadataService.readMetadata(
        filePath: '/fake/file.jpg',
        runProcess: runner.call,
      );

      expect(result.success, isFalse);
    });

    test('empty result list instead of the file data fails', () async {
      final runner = _FakeRunner((executable, args) async => _ok('[]'));

      final result = await MetadataService.readMetadata(
        filePath: '/fake/file.jpg',
        runProcess: runner.call,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
    });

    test('non-zero exit code with ExifTool error message fails', () async {
      final runner = _FakeRunner(
        (executable, args) async =>
            _fail(1, 'Error: File not found - /x/y.jpg'),
      );

      final result = await MetadataService.readMetadata(
        filePath: '/x/y.jpg',
        runProcess: runner.call,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('File not found'));
    });

    test('unlaunchable exiftool fails', () async {
      final runner = _FakeRunner(
        (executable, args) =>
            throw const ProcessException('exiftool', [], 'No such file', 2),
      );

      final result = await MetadataService.readMetadata(
        filePath: '/fake/file.jpg',
        runProcess: runner.call,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('No such file'));
    });

    test('read command is JSON, grouped, and never writes', () async {
      final runner = _FakeRunner((executable, args) async => _ok('[]'));

      await MetadataService.readMetadata(
        filePath: '/dir/some file.jpg',
        runProcess: runner.call,
      );

      final args = runner.lastArgs;
      expect(args.first, '-json');
      expect(args, contains('-G0'));
      expect(
        args.where((a) => a.startsWith('-')),
        everyElement((String a) => !a.contains('=')),
      );
      expect(args, isNot(contains('-overwrite_original')));
      // File path with a space is passed as one argument.
      expect(args.last, '/dir/some file.jpg');
    });
  });

  group('legacy writeMetadata compatibility', () {
    test('returns true when the detailed result succeeds', () async {
      final runner = _FakeRunner(
        (executable, args) async => _ok('1 image files updated'),
      );

      final ok = await MetadataService.writeMetadata(
        filePath: '/dir/file.jpg',
        title: 'T',
        keywords: 'k',
        runProcess: runner.call,
      );

      expect(ok, isTrue);
    });

    test('returns false when the detailed result fails', () async {
      final runner = _FakeRunner(
        (executable, args) async => _fail(3, 'Error: cannot write\n'),
      );

      final ok = await MetadataService.writeMetadata(
        filePath: '/dir/file.jpg',
        title: 'T',
        keywords: 'k',
        runProcess: runner.call,
      );

      expect(ok, isFalse);
    });
  });
}
