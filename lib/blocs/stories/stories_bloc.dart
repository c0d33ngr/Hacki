import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hacki/config/locator.dart';
import 'package:hacki/models/models.dart';
import 'package:hacki/repositories/repositories.dart';

part 'stories_event.dart';

part 'stories_state.dart';

class StoriesBloc extends Bloc<StoriesEvent, StoriesState> {
  StoriesBloc({
    CacheRepository? cacheRepository,
    StoriesRepository? storiesRepository,
  })  : _cacheRepository = cacheRepository ?? locator.get<CacheRepository>(),
        _storiesRepository =
            storiesRepository ?? locator.get<StoriesRepository>(),
        super(const StoriesState.init()) {
    on<StoriesInitialize>(onInitialize);
    on<StoriesRefresh>(onRefresh);
    on<StoriesLoadMore>(onLoadMore);
    on<StoryLoaded>(onStoryLoaded);
    on<StoriesLoaded>(onStoriesLoaded);
    on<StoriesDownload>(onDownload);
    on<StoriesExitOffline>(onExitOffline);
    add(StoriesInitialize());
  }

  final CacheRepository _cacheRepository;
  final StoriesRepository _storiesRepository;
  static const _pageSize = 20;

  Future<void> loadStories(
      {required StoryType of, required Emitter<StoriesState> emit}) async {
    if (state.offlineReading) {
      final ids = await _cacheRepository.getCachedStoryIds(of: of);
      emit(state
          .copyWithStoryIdsUpdated(of: of, to: ids)
          .copyWithCurrentPageUpdated(of: of, to: 0));
      _cacheRepository
          .getCachedStoriesStream(
              ids: ids.sublist(0, min(ids.length, _pageSize)))
          .listen((story) {
        add(StoryLoaded(story: story, type: of));
      }).onDone(() {
        add(StoriesLoaded(type: of));
      });
    } else {
      final ids = await _storiesRepository.fetchStoryIds(of: of);
      emit(state
          .copyWithStoryIdsUpdated(of: of, to: ids)
          .copyWithCurrentPageUpdated(of: of, to: 0));
      _storiesRepository
          .fetchStoriesStream(ids: ids.sublist(0, _pageSize))
          .listen((story) {
        add(StoryLoaded(story: story, type: of));
      }).onDone(() {
        add(StoriesLoaded(type: of));
      });
    }
  }

  Future<void> onInitialize(
      StoriesInitialize event, Emitter<StoriesState> emit) async {
    final hasCachedStories = await _cacheRepository.hasCachedStories;
    emit(state.copyWith(offlineReading: hasCachedStories));
    await loadStories(of: StoryType.top, emit: emit);
    await loadStories(of: StoryType.latest, emit: emit);
    await loadStories(of: StoryType.ask, emit: emit);
    await loadStories(of: StoryType.show, emit: emit);
    await loadStories(of: StoryType.jobs, emit: emit);
  }

  Future<void> onRefresh(
      StoriesRefresh event, Emitter<StoriesState> emit) async {
    if (state.offlineReading) {
      emit(state.copyWithStatusUpdated(
        of: event.type,
        to: StoriesStatus.loaded,
      ));
    } else {
      emit(state.copyWithRefreshed(of: event.type));
      await loadStories(of: event.type, emit: emit);
    }
  }

  void onLoadMore(StoriesLoadMore event, Emitter<StoriesState> emit) {
    final currentPage = state.currentPageByType[event.type]!;
    final len = state.storyIdsByType[event.type]!.length;
    emit(state.copyWithCurrentPageUpdated(of: event.type, to: currentPage + 1));
    final lower = _pageSize * (currentPage + 1);
    var upper = _pageSize + lower;

    if (len > lower) {
      if (len < upper) {
        upper = len;
      }

      if (state.offlineReading) {
        _cacheRepository
            .getCachedStoriesStream(
                ids: state.storyIdsByType[event.type]!.sublist(
          lower,
          upper,
        ))
            .listen((story) {
          add(StoryLoaded(
            story: story,
            type: event.type,
          ));
        });
      } else {
        _storiesRepository
            .fetchStoriesStream(
                ids: state.storyIdsByType[event.type]!.sublist(
          lower,
          upper,
        ))
            .listen((story) {
          add(StoryLoaded(
            story: story,
            type: event.type,
          ));
        });
      }
    } else {
      emit(state.copyWithStatusUpdated(
          of: event.type, to: StoriesStatus.loaded));
    }
  }

  void onStoryLoaded(StoryLoaded event, Emitter<StoriesState> emit) {
    emit(state.copyWithStoryAdded(of: event.type, story: event.story));
    if (state.storiesByType[event.type]!.length % _pageSize == 0) {
      emit(
        state.copyWithStatusUpdated(
          of: event.type,
          to: StoriesStatus.loaded,
        ),
      );
    }
  }

  void onStoriesLoaded(StoriesLoaded event, Emitter<StoriesState> emit) {
    emit(state.copyWithStatusUpdated(of: event.type, to: StoriesStatus.loaded));
  }

  Future<void> onDownload(
      StoriesDownload event, Emitter<StoriesState> emit) async {
    emit(state.copyWith(
      downloadStatus: StoriesDownloadStatus.downloading,
    ));

    await _cacheRepository.deleteAllStoryIds();
    await _cacheRepository.deleteAllStories();
    await _cacheRepository.deleteAllComments();

    final topIds = await _storiesRepository.fetchStoryIds(of: StoryType.top);
    final newIds = await _storiesRepository.fetchStoryIds(of: StoryType.latest);
    final askIds = await _storiesRepository.fetchStoryIds(of: StoryType.ask);
    final showIds = await _storiesRepository.fetchStoryIds(of: StoryType.show);
    final jobIds = await _storiesRepository.fetchStoryIds(of: StoryType.jobs);

    await _cacheRepository.cacheStoryIds(of: StoryType.top, ids: topIds);
    await _cacheRepository.cacheStoryIds(of: StoryType.latest, ids: newIds);
    await _cacheRepository.cacheStoryIds(of: StoryType.ask, ids: askIds);
    await _cacheRepository.cacheStoryIds(of: StoryType.show, ids: showIds);
    await _cacheRepository.cacheStoryIds(of: StoryType.jobs, ids: jobIds);

    final allIds = [...topIds, ...newIds, ...askIds, ...showIds, ...jobIds];

    _storiesRepository.fetchStoriesStream(ids: allIds).listen((story) async {
      await _cacheRepository.cacheStory(story: story);
      _storiesRepository
          .fetchAllChildrenComments(ids: story.kids)
          .listen((comment) async {
        if (comment != null) {
          await _cacheRepository.cacheComment(comment: comment);
        }
      });
    }).onDone(() {
      emit(state.copyWith(
        downloadStatus: StoriesDownloadStatus.finished,
      ));
    });
  }

  Future<void> onExitOffline(
      StoriesExitOffline event, Emitter<StoriesState> emit) async {
    await _cacheRepository.deleteAllStoryIds();
    await _cacheRepository.deleteAllStories();
    await _cacheRepository.deleteAllComments();
    emit(state.copyWith(offlineReading: false));
    add(StoriesInitialize());
  }
}
