part of 'reader.dart';

class ReaderWithLoading extends StatefulWidget {
  const ReaderWithLoading({
    super.key,
    required this.id,
    required this.sourceKey,
    this.initialEp,
    this.initialPage,
    this.resumeHistory,
  });

  final String id;

  final String sourceKey;

  final int? initialEp;

  final int? initialPage;

  final History? resumeHistory;

  @override
  State<ReaderWithLoading> createState() => _ReaderWithLoadingState();
}

class _ReaderWithLoadingState
    extends LoadingState<ReaderWithLoading, ReaderProps> {
  @override
  Widget buildContent(BuildContext context, ReaderProps data) {
    return Reader(
      type: data.type,
      cid: data.cid,
      name: data.name,
      chapters: data.chapters,
      history: data.history,
      initialChapter: widget.initialEp ?? data.history.ep,
      initialPage: widget.initialPage ?? data.history.page,
      initialChapterGroup: data.history.group,
      author: data.author,
      tags: data.tags,
    );
  }

  @override
  Future<Res<ReaderProps>> loadData() async {
    final type = ComicType.fromKey(widget.sourceKey);
    final comicSource = ComicSource.find(widget.sourceKey);
    final history =
        widget.resumeHistory ?? HistoryManager().find(widget.id, type);
    if (type == ComicType.local ||
        (comicSource != null && widget.resumeHistory != null)) {
      final localComic = LocalManager().find(widget.id, type);
      if (localComic != null &&
          (type == ComicType.local ||
              LocalManager().isDownloaded(
                widget.id,
                type,
                localComic.chapters?.resolveSavedChapter(
                      history!.ep,
                      history.group,
                    ) ??
                    1,
              ))) {
        return Res(
          ReaderProps(
            type: type,
            cid: widget.id,
            name: localComic.title,
            chapters: localComic.chapters,
            history:
                history ?? History.fromModel(model: localComic, ep: 0, page: 0),
            author: localComic.subtitle,
            tags: localComic.tags,
          ),
        );
      }
    }
    final loadComic = comicSource?.loadComicInfo;
    if (loadComic == null) return Res.error('Comic source is unavailable'.tl);
    try {
      final comic = await loadComic(widget.id);
      if (comic.error) {
        return Res.fromErrorRes(comic);
      }
      return Res(
        ReaderProps(
          type: type,
          cid: widget.id,
          name: comic.data.title,
          chapters: comic.data.chapters,
          history:
              history ?? History.fromModel(model: comic.data, ep: 0, page: 0),
          author: comic.data.findAuthor() ?? "",
          tags: comic.data.plainTags,
        ),
      );
    } catch (error) {
      return Res.error(error.toString());
    }
  }
}

class ReaderProps {
  final ComicType type;

  final String cid;

  final String name;

  final ComicChapters? chapters;

  final History history;

  final String author;

  final List<String> tags;

  const ReaderProps({
    required this.type,
    required this.cid,
    required this.name,
    required this.chapters,
    required this.history,
    required this.author,
    required this.tags,
  });
}
