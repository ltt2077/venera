import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';

void main() {
  test('saved chapter and group map to the reader chapter index', () {
    const chapters = ComicChapters.grouped({
      'Main': {'1': 'First', '2': 'Second'},
      'Extras': {'extra-1': 'Extra 1', 'extra-2': 'Extra 2'},
    });
    final index = chapters.resolveSavedChapter(2, 2);
    expect(index, 4);
    expect(chapters.ids.elementAt(index - 1), 'extra-2');
  });

  test('saved positions remain valid when the source changes its chapters', () {
    const grouped = ComicChapters.grouped({
      'Main': {'1': 'First', '2': 'Second'},
      'Extras': {'extra-1': 'Extra 1'},
    });
    expect(grouped.resolveSavedChapter(4, 2), 3);
    expect(grouped.resolveSavedChapter(10, 7), 3);
    expect(const ComicChapters({'1': 'First'}).resolveSavedChapter(5, 2), 1);
    expect(const ComicChapters.grouped({}).resolveSavedChapter(5, 2), 1);
  });
}
