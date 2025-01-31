import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:lemmy_api_client/v3.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_transform/stream_transform.dart';

import 'package:thunder/core/enums/custom_theme_type.dart';
import 'package:thunder/core/enums/font_scale.dart';
import 'package:thunder/core/enums/local_settings.dart';
import 'package:thunder/core/enums/nested_comment_indicator.dart';
import 'package:thunder/core/enums/swipe_action.dart';
import 'package:thunder/core/enums/theme_type.dart';
import 'package:thunder/core/models/version.dart';
import 'package:thunder/core/singletons/preferences.dart';
import 'package:thunder/core/update/check_github_update.dart';
import 'package:thunder/utils/constants.dart';

part 'thunder_event.dart';
part 'thunder_state.dart';

const throttleDuration = Duration(milliseconds: 300);

EventTransformer<E> throttleDroppable<E>(Duration duration) {
  return (events, mapper) => droppable<E>().call(events.throttle(duration), mapper);
}

class ThunderBloc extends Bloc<ThunderEvent, ThunderState> {
  ThunderBloc() : super(const ThunderState()) {
    on<InitializeAppEvent>(
      _initializeAppEvent,
      transformer: throttleDroppable(throttleDuration),
    );
    on<UserPreferencesChangeEvent>(
      _userPreferencesChangeEvent,
      transformer: throttleDroppable(throttleDuration),
    );
    on<OnScrollToTopEvent>(
      _onScrollToTopEvent,
      transformer: throttleDroppable(throttleDuration),
    );
  }

  /// This event should be triggered at the start of the app.
  ///
  /// It initializes the local database, checks for updates from GitHub, and loads the user's preferences.
  Future<void> _initializeAppEvent(InitializeAppEvent event, Emitter<ThunderState> emit) async {
    try {
      // Check for any updates from GitHub
      Version version = await fetchVersion();

      add(UserPreferencesChangeEvent());
      emit(state.copyWith(status: ThunderStatus.success, version: version));
    } catch (e) {
      return emit(state.copyWith(status: ThunderStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _userPreferencesChangeEvent(UserPreferencesChangeEvent event, Emitter<ThunderState> emit) async {
    try {
      emit(state.copyWith(status: ThunderStatus.refreshing));

      SharedPreferences prefs = (await UserPreferences.instance).sharedPreferences;

      /// -------------------------- Feed Related Settings --------------------------
      // Default Listing/Sort Settings
      PostListingType defaultPostListingType = DEFAULT_LISTING_TYPE;
      SortType defaultSortType = DEFAULT_SORT_TYPE;
      try {
        defaultPostListingType = PostListingType.values.byName(prefs.getString(LocalSettings.defaultFeedListingType.name) ?? DEFAULT_LISTING_TYPE.name);
        defaultSortType = SortType.values.byName(prefs.getString(LocalSettings.defaultFeedSortType.name) ?? DEFAULT_SORT_TYPE.name);
      } catch (e) {
        defaultPostListingType = PostListingType.values.byName(DEFAULT_LISTING_TYPE.name);
        defaultSortType = SortType.values.byName(DEFAULT_SORT_TYPE.name);
      }

      // NSFW Settings
      bool hideNsfwPosts = prefs.getBool(LocalSettings.hideNsfwPosts.name) ?? false;
      bool hideNsfwPreviews = prefs.getBool(LocalSettings.hideNsfwPreviews.name) ?? true;

      // Tablet Settings
      bool tabletMode = prefs.getBool(LocalSettings.useTabletMode.name) ?? false;

      // General Settings
      bool showLinkPreviews = prefs.getBool(LocalSettings.showLinkPreviews.name) ?? true;
      bool openInExternalBrowser = prefs.getBool(LocalSettings.openLinksInExternalBrowser.name) ?? false;
      bool useDisplayNames = prefs.getBool(LocalSettings.useDisplayNamesForUsers.name) ?? true;
      bool markPostReadOnMediaView = prefs.getBool(LocalSettings.markPostAsReadOnMediaView.name) ?? false;
      bool disableFeedFab = prefs.getBool(LocalSettings.disableFeedFab.name) ?? false;
      bool showInAppUpdateNotification = prefs.getBool(LocalSettings.showInAppUpdateNotification.name) ?? true;

      /// -------------------------- Feed Post Related Settings --------------------------
      // Compact Related Settings
      bool useCompactView = prefs.getBool(LocalSettings.useCompactView.name) ?? false;
      bool showTitleFirst = prefs.getBool(LocalSettings.showPostTitleFirst.name) ?? false;
      bool showThumbnailPreviewOnRight = prefs.getBool(LocalSettings.showThumbnailPreviewOnRight.name) ?? false;
      bool showTextPostIndicator = prefs.getBool(LocalSettings.showTextPostIndicator.name) ?? false;

      // General Settings
      bool showVoteActions = prefs.getBool(LocalSettings.showPostVoteActions.name) ?? true;
      bool showSaveAction = prefs.getBool(LocalSettings.showPostSaveAction.name) ?? true;
      bool showCommunityIcons = prefs.getBool(LocalSettings.showPostCommunityIcons.name) ?? false;
      bool showFullHeightImages = prefs.getBool(LocalSettings.showPostFullHeightImages.name) ?? false;
      bool showEdgeToEdgeImages = prefs.getBool(LocalSettings.showPostEdgeToEdgeImages.name) ?? false;
      bool showTextContent = prefs.getBool(LocalSettings.showPostTextContentPreview.name) ?? false;
      bool showPostAuthor = prefs.getBool(LocalSettings.showPostAuthor.name) ?? false;

      /// -------------------------- Post Page Related Settings --------------------------
      bool disablePostFabs = prefs.getBool(LocalSettings.disablePostFab.name) ?? false;

      // Comment Related Settings
      CommentSortType defaultCommentSortType = CommentSortType.values.byName(prefs.getString(LocalSettings.defaultCommentSortType.name) ?? DEFAULT_COMMENT_SORT_TYPE.name);
      bool collapseParentCommentOnGesture = prefs.getBool(LocalSettings.collapseParentCommentBodyOnGesture.name) ?? true;
      bool showCommentButtonActions = prefs.getBool(LocalSettings.showCommentActionButtons.name) ?? false;
      NestedCommentIndicatorStyle nestedCommentIndicatorStyle =
          NestedCommentIndicatorStyle.values.byName(prefs.getString(LocalSettings.nestedCommentIndicatorStyle.name) ?? DEFAULT_NESTED_COMMENT_INDICATOR_STYLE.name);
      NestedCommentIndicatorColor nestedCommentIndicatorColor =
          NestedCommentIndicatorColor.values.byName(prefs.getString(LocalSettings.nestedCommentIndicatorColor.name) ?? DEFAULT_NESTED_COMMENT_INDICATOR_COLOR.name);

      /// -------------------------- Theme Related Settings --------------------------
      // Theme Settings
      ThemeType themeType = ThemeType.values[prefs.getInt(LocalSettings.appTheme.name) ?? ThemeType.system.index];
      CustomThemeType selectedTheme = CustomThemeType.values.byName(prefs.getString(LocalSettings.appThemeAccentColor.name) ?? CustomThemeType.deepBlue.name);
      bool useMaterialYouTheme = prefs.getBool(LocalSettings.useMaterialYouTheme.name) ?? false;

      // Font Settings
      FontScale titleFontSizeScale = FontScale.values.byName(prefs.getString(LocalSettings.titleFontSizeScale.name) ?? FontScale.base.name);
      FontScale contentFontSizeScale = FontScale.values.byName(prefs.getString(LocalSettings.contentFontSizeScale.name) ?? FontScale.base.name);

      /// -------------------------- Gesture Related Settings --------------------------
      // Sidebar Gesture Settings
      bool bottomNavBarSwipeGestures = prefs.getBool(LocalSettings.sidebarBottomNavBarSwipeGesture.name) ?? true;
      bool bottomNavBarDoubleTapGestures = prefs.getBool(LocalSettings.sidebarBottomNavBarDoubleTapGesture.name) ?? false;

      // Post Gestures
      bool enablePostGestures = prefs.getBool(LocalSettings.enablePostGestures.name) ?? true;
      SwipeAction leftPrimaryPostGesture = SwipeAction.values.byName(prefs.getString(LocalSettings.postGestureLeftPrimary.name) ?? SwipeAction.upvote.name);
      SwipeAction leftSecondaryPostGesture = SwipeAction.values.byName(prefs.getString(LocalSettings.postGestureLeftSecondary.name) ?? SwipeAction.downvote.name);
      SwipeAction rightPrimaryPostGesture = SwipeAction.values.byName(prefs.getString(LocalSettings.postGestureRightPrimary.name) ?? SwipeAction.save.name);
      SwipeAction rightSecondaryPostGesture = SwipeAction.values.byName(prefs.getString(LocalSettings.postGestureRightSecondary.name) ?? SwipeAction.toggleRead.name);

      // Comment Gestures
      bool enableCommentGestures = prefs.getBool(LocalSettings.enableCommentGestures.name) ?? true;
      SwipeAction leftPrimaryCommentGesture = SwipeAction.values.byName(prefs.getString(LocalSettings.commentGestureLeftPrimary.name) ?? SwipeAction.upvote.name);
      SwipeAction leftSecondaryCommentGesture = SwipeAction.values.byName(prefs.getString(LocalSettings.commentGestureLeftSecondary.name) ?? SwipeAction.downvote.name);
      SwipeAction rightPrimaryCommentGesture = SwipeAction.values.byName(prefs.getString(LocalSettings.commentGestureRightPrimary.name) ?? SwipeAction.reply.name);
      SwipeAction rightSecondaryCommentGesture = SwipeAction.values.byName(prefs.getString(LocalSettings.commentGestureRightSecondary.name) ?? SwipeAction.save.name);

      return emit(state.copyWith(
        status: ThunderStatus.success,

        /// -------------------------- Feed Related Settings --------------------------
        // Default Listing/Sort Settings
        defaultPostListingType: defaultPostListingType,
        defaultSortType: defaultSortType,

        // NSFW Settings
        hideNsfwPosts: hideNsfwPosts,
        hideNsfwPreviews: hideNsfwPreviews,

        // Tablet Settings
        tabletMode: tabletMode,

        // General Settings
        showLinkPreviews: showLinkPreviews,
        openInExternalBrowser: openInExternalBrowser,
        useDisplayNames: useDisplayNames,
        markPostReadOnMediaView: markPostReadOnMediaView,
        disableFeedFab: disableFeedFab,
        showInAppUpdateNotification: showInAppUpdateNotification,

        /// -------------------------- Feed Post Related Settings --------------------------
        // Compact Related Settings
        useCompactView: useCompactView,
        showTitleFirst: showTitleFirst,
        showThumbnailPreviewOnRight: showThumbnailPreviewOnRight,
        showTextPostIndicator: showTextPostIndicator,

        // General Settings
        showVoteActions: showVoteActions,
        showSaveAction: showSaveAction,
        showCommunityIcons: showCommunityIcons,
        showFullHeightImages: showFullHeightImages,
        showEdgeToEdgeImages: showEdgeToEdgeImages,
        showTextContent: showTextContent,
        showPostAuthor: showPostAuthor,

        /// -------------------------- Post Page Related Settings --------------------------
        disablePostFabs: disablePostFabs,

        // Comment Related Settings
        defaultCommentSortType: defaultCommentSortType,
        collapseParentCommentOnGesture: collapseParentCommentOnGesture,
        showCommentButtonActions: showCommentButtonActions,
        nestedCommentIndicatorStyle: nestedCommentIndicatorStyle,
        nestedCommentIndicatorColor: nestedCommentIndicatorColor,

        /// -------------------------- Theme Related Settings --------------------------
        // Theme Settings
        themeType: themeType,
        selectedTheme: selectedTheme,
        useMaterialYouTheme: useMaterialYouTheme,

        // Font Settings
        titleFontSizeScale: titleFontSizeScale,
        contentFontSizeScale: contentFontSizeScale,

        /// -------------------------- Gesture Related Settings --------------------------
        // Sidebar Gesture Settings
        bottomNavBarSwipeGestures: bottomNavBarSwipeGestures,
        bottomNavBarDoubleTapGestures: bottomNavBarDoubleTapGestures,

        // Post Gestures
        enablePostGestures: enablePostGestures,
        leftPrimaryPostGesture: leftPrimaryPostGesture,
        leftSecondaryPostGesture: leftSecondaryPostGesture,
        rightPrimaryPostGesture: rightPrimaryPostGesture,
        rightSecondaryPostGesture: rightSecondaryPostGesture,

        // Comment Gestures
        enableCommentGestures: enableCommentGestures,
        leftPrimaryCommentGesture: leftPrimaryCommentGesture,
        leftSecondaryCommentGesture: leftSecondaryCommentGesture,
        rightPrimaryCommentGesture: rightPrimaryCommentGesture,
        rightSecondaryCommentGesture: rightSecondaryCommentGesture,
      ));
    } catch (e) {
      return emit(state.copyWith(status: ThunderStatus.failure, errorMessage: e.toString()));
    }
  }

  void _onScrollToTopEvent(OnScrollToTopEvent event, Emitter<ThunderState> emit) {
    emit(state.copyWith(scrollToTopId: state.scrollToTopId + 1));
  }
}
