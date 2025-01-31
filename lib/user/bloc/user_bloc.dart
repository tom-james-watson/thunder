import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:lemmy_api_client/v3.dart';

import 'package:stream_transform/stream_transform.dart';

import 'package:thunder/account/models/account.dart';
import 'package:thunder/core/auth/helpers/fetch_account.dart';
import 'package:thunder/core/models/comment_view_tree.dart';
import 'package:thunder/core/models/post_view_media.dart';
import 'package:thunder/core/singletons/lemmy_client.dart';
import 'package:thunder/utils/comment.dart';
import 'package:thunder/utils/post.dart';

part 'user_event.dart';
part 'user_state.dart';

const throttleDuration = Duration(seconds: 1);
const timeout = Duration(seconds: 3);

EventTransformer<E> throttleDroppable<E>(Duration duration) {
  return (events, mapper) => droppable<E>().call(events.throttle(duration), mapper);
}

class UserBloc extends Bloc<UserEvent, UserState> {
  UserBloc() : super(const UserState()) {
    on<GetUserEvent>(
      _getUserEvent,
      transformer: throttleDroppable(throttleDuration),
    );
    on<VotePostEvent>(
      _votePostEvent,
      transformer: throttleDroppable(throttleDuration),
    );
    on<SavePostEvent>(
      _savePostEvent,
      transformer: throttleDroppable(throttleDuration),
    );
    on<VoteCommentEvent>(
      _voteCommentEvent,
      transformer: throttleDroppable(throttleDuration),
    );
    on<SaveCommentEvent>(
      _saveCommentEvent,
      transformer: throttleDroppable(throttleDuration),
    );
    on<GetUserSavedEvent>(
      _getUserSavedEvent,
      transformer: throttleDroppable(throttleDuration),
    );
    on<MarkUserPostAsReadEvent>(
      _markPostAsReadEvent,
      transformer: throttleDroppable(throttleDuration),
    );
    on<BlockUserEvent>(
      _blockUserEvent,
      transformer: throttleDroppable(throttleDuration),
    );
  }

  Future<void> _getUserEvent(GetUserEvent event, emit) async {
    int attemptCount = 0;
    int limit = 30;

    try {
      Object exception;

      Account? account = await fetchActiveProfileAccount();

      while (attemptCount < 2) {
        try {
          LemmyApiV3 lemmy = LemmyClient.instance.lemmyApiV3;

          if (event.reset) {
            emit(state.copyWith(status: UserStatus.loading));

            FullPersonView? fullPersonView;

            if (event.userId != null) {
              fullPersonView = await lemmy
                  .run(GetPersonDetails(
                personId: event.isAccountUser ? null : event.userId,
                username: event.isAccountUser ? account?.username : null,
                auth: account?.jwt,
                sort: SortType.new_,
                limit: limit,
                page: 1,
              ))
                  .timeout(timeout, onTimeout: () {
                throw Exception('Error: Timeout when attempting to fetch user');
              });
            }

            List<PostViewMedia> posts = await parsePostViews(fullPersonView?.posts ?? []);

            // Build the tree view from the flattened comments
            List<CommentViewTree> commentTree = buildCommentViewTree(fullPersonView?.comments ?? [], flatten: true);

            return emit(
              state.copyWith(
                userId: event.userId,
                personView: fullPersonView?.personView,
                status: UserStatus.success,
                comments: commentTree,
                posts: posts,
                moderates: fullPersonView?.moderates,
                page: 2,
                hasReachedPostEnd: posts.length == fullPersonView?.personView.counts.postCount,
                hasReachedCommentEnd: posts.isEmpty && (fullPersonView?.comments.isEmpty ?? true),
              ),
            );
          }

          if (state.hasReachedCommentEnd && state.hasReachedPostEnd) {
            return emit(state.copyWith(status: UserStatus.success));
          }

          emit(state.copyWith(status: UserStatus.refreshing));

          FullPersonView? fullPersonView = await lemmy
              .run(GetPersonDetails(
            personId: state.userId,
            auth: account?.jwt,
            sort: SortType.new_,
            limit: limit,
            page: state.page,
          ))
              .timeout(timeout, onTimeout: () {
            throw Exception('Error: Timeout when attempting to fetch user');
          });

          List<PostViewMedia> posts = await parsePostViews(fullPersonView.posts ?? []);

          // Append the new posts
          List<PostViewMedia> postViewMedias = List.from(state.posts);
          postViewMedias.addAll(posts);

          // Build the tree view from the flattened comments
          List<CommentViewTree> commentTree = buildCommentViewTree(fullPersonView.comments ?? [], flatten: true);

          // Append the new comments
          List<CommentViewTree> commentViewTree = List.from(state.comments);
          commentViewTree.addAll(commentTree);

          return emit(state.copyWith(
            userId: state.userId,
            status: UserStatus.success,
            comments: commentViewTree,
            posts: postViewMedias,
            moderates: fullPersonView.moderates,
            page: state.page + 1,
            hasReachedPostEnd: postViewMedias.length == fullPersonView.personView.counts.postCount,
            hasReachedCommentEnd: posts.isEmpty && fullPersonView.comments.isEmpty,
          ));
        } catch (e) {
          exception = e;
          attemptCount++;
        }
      }
    } catch (e) {
      emit(state.copyWith(status: UserStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _getUserSavedEvent(GetUserSavedEvent event, emit) async {
    int attemptCount = 0;
    int limit = 30;

    try {
      Object exception;

      Account? account = await fetchActiveProfileAccount();

      while (attemptCount < 2) {
        try {
          LemmyApiV3 lemmy = LemmyClient.instance.lemmyApiV3;

          if (event.reset) {
            emit(state.copyWith(status: UserStatus.loading));

            FullPersonView? fullPersonView;

            if (event.userId != null) {
              fullPersonView = await lemmy
                  .run(GetPersonDetails(
                personId: event.isAccountUser ? null : event.userId,
                username: event.isAccountUser ? account?.username : null,
                auth: account?.jwt,
                sort: SortType.new_,
                limit: limit,
                page: 1,
                savedOnly: true,
              ))
                  .timeout(timeout, onTimeout: () {
                throw Exception('Error: Timeout when attempting to fetch user');
              });
            }

            List<PostViewMedia> posts = await parsePostViews(fullPersonView?.posts ?? []);

            // Build the tree view from the flattened comments
            List<CommentViewTree> commentTree = buildCommentViewTree(fullPersonView?.comments ?? [], flatten: true);

            return emit(
              state.copyWith(
                status: UserStatus.success,
                savedComments: commentTree,
                savedPosts: posts,
                savedContentPage: 2,
                hasReachedSavedPostEnd: posts.isEmpty || posts.length < limit,
                hasReachedSavedCommentEnd: commentTree.isEmpty || commentTree.length < limit,
              ),
            );
          }

          if (state.hasReachedSavedCommentEnd && state.hasReachedSavedPostEnd) {
            return emit(state.copyWith(status: UserStatus.success));
          }

          emit(state.copyWith(status: UserStatus.refreshing));

          FullPersonView? fullPersonView = await lemmy
              .run(GetPersonDetails(
            personId: state.userId,
            auth: account?.jwt,
            sort: SortType.new_,
            limit: limit,
            page: state.savedContentPage,
            savedOnly: true,
          ))
              .timeout(timeout, onTimeout: () {
            throw Exception('Error: Timeout when attempting to fetch user saved content');
          });

          List<PostViewMedia> posts = await parsePostViews(fullPersonView.posts ?? []);

          // Append the new posts
          List<PostViewMedia> postViewMedias = List.from(state.savedPosts);
          postViewMedias.addAll(posts);

          // Build the tree view from the flattened comments
          List<CommentViewTree> commentTree = buildCommentViewTree(fullPersonView.comments ?? [], flatten: true);

          // Append the new comments
          List<CommentViewTree> commentViewTree = List.from(state.savedComments);
          commentViewTree.addAll(commentTree);

          return emit(state.copyWith(
            status: UserStatus.success,
            savedComments: commentViewTree,
            savedPosts: postViewMedias,
            savedContentPage: state.savedContentPage + 1,
            hasReachedSavedPostEnd: posts.isEmpty || posts.length < limit,
            hasReachedSavedCommentEnd: commentTree.isEmpty || commentTree.length < limit,
          ));
        } catch (e) {
          exception = e;
          attemptCount++;
        }
      }
    } catch (e, s) {
      emit(state.copyWith(status: UserStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _votePostEvent(VotePostEvent event, Emitter<UserState> emit) async {
    try {
      emit(state.copyWith(status: UserStatus.refreshing));

      // Optimistically update the post
      PostViewMedia? postViewMedia = _getPost(event.postId);

      if (postViewMedia != null) {
        PostView originalPostView = postViewMedia.postView;
        PostView updatedPostView = optimisticallyVotePost(postViewMedia, event.score);
        _updatePosts(updatedPostView, event.postId);

        // Immediately set the status, and continue
        emit(state.copyWith(status: UserStatus.success));
        emit(state.copyWith(status: UserStatus.refreshing));

        PostView postView = await votePost(event.postId, event.score).timeout(timeout, onTimeout: () {
          _updatePosts(originalPostView, event.postId);
          throw Exception('Error: Timeout when attempting to vote post');
        });

        // Find the specific post to update
        _updatePosts(postView, event.postId);
      }

      return emit(state.copyWith(status: UserStatus.success));
    } catch (e) {
      return emit(state.copyWith(status: UserStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _markPostAsReadEvent(MarkUserPostAsReadEvent event, Emitter<UserState> emit) async {
    try {
      emit(state.copyWith(status: UserStatus.refreshing, userId: state.userId));

      PostView postView = await markPostAsRead(event.postId, event.read);

      _updatePosts(postView, event.postId);

      return emit(state.copyWith(status: UserStatus.success, userId: state.userId));
    } catch (e) {
      return emit(state.copyWith(
        status: UserStatus.failure,
        errorMessage: e.toString(),
        userId: state.userId,
      ));
    }
  }

  Future<void> _savePostEvent(SavePostEvent event, Emitter<UserState> emit) async {
    try {
      emit(state.copyWith(status: UserStatus.refreshing));

      PostView postView = await savePost(event.postId, event.save);

      _updatePosts(postView, event.postId);

      return emit(state.copyWith(status: UserStatus.success));
    } catch (e) {
      return emit(state.copyWith(status: UserStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _voteCommentEvent(VoteCommentEvent event, Emitter<UserState> emit) async {
    try {
      emit(state.copyWith(status: UserStatus.refreshing));

      List<int> commentIndexes = findCommentIndexesFromCommentViewTree(state.comments, event.commentId);
      CommentViewTree currentTree = state.comments[commentIndexes[0]]; // Get the initial CommentViewTree

      for (int i = 1; i < commentIndexes.length; i++) {
        currentTree = currentTree.replies[commentIndexes[i]]; // Traverse to the next CommentViewTree
      }

      // Optimistically update the comment
      CommentView? originalCommentView = currentTree.commentView;

      CommentView updatedCommentView = optimisticallyVoteComment(currentTree, event.score);
      currentTree.commentView = updatedCommentView;

      // Immediately set the status, and continue
      emit(state.copyWith(status: UserStatus.success));
      emit(state.copyWith(status: UserStatus.refreshing));

      CommentView commentView = await voteComment(event.commentId, event.score).timeout(timeout, onTimeout: () {
        currentTree.commentView = originalCommentView; // Reset this on exception
        throw Exception('Error: Timeout when attempting to vote on comment');
      });

      currentTree.commentView = commentView;

      return emit(state.copyWith(status: UserStatus.success));
    } catch (e) {
      return emit(state.copyWith(status: UserStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _saveCommentEvent(SaveCommentEvent event, Emitter<UserState> emit) async {
    try {
      emit(state.copyWith(status: UserStatus.refreshing));

      CommentView commentView = await saveComment(event.commentId, event.save).timeout(timeout, onTimeout: () {
        throw Exception('Error: Timeout when attempting save a comment');
      });

      List<int> commentIndexes = findCommentIndexesFromCommentViewTree(state.comments, event.commentId);
      CommentViewTree currentTree = state.comments[commentIndexes[0]]; // Get the initial CommentViewTree

      for (int i = 1; i < commentIndexes.length; i++) {
        currentTree = currentTree.replies[commentIndexes[i]]; // Traverse to the next CommentViewTree
      }

      currentTree.commentView = commentView; // Update the comment's information

      return emit(state.copyWith(status: UserStatus.success));
    } catch (e) {
      emit(state.copyWith(status: UserStatus.failure, errorMessage: e.toString()));
    }
  }

  PostViewMedia? _getPost(int postId) {
    int postsIndex = state.posts.indexWhere((postViewMedia) => postViewMedia.postView.post.id == postId);
    if (postsIndex >= 0) {
      return state.posts[postsIndex];
    }

    int savedPostsIndex = state.savedPosts.indexWhere((postViewMedia) => postViewMedia.postView.post.id == postId);
    if (savedPostsIndex >= 0) {
      return state.savedPosts[savedPostsIndex];
    }

    return null;
  }

  void _updatePosts(PostView postView, int postId) {
    int postsIndex = state.posts.indexWhere((postViewMedia) => postViewMedia.postView.post.id == postId);
    if (postsIndex >= 0) {
      state.posts[postsIndex].postView = postView;
    }

    int savedPostsIndex = state.savedPosts.indexWhere((postViewMedia) => postViewMedia.postView.post.id == postId);
    if (savedPostsIndex >= 0) {
      state.savedPosts[savedPostsIndex].postView = postView;
    }
  }

  Future<void> _blockUserEvent(BlockUserEvent event, Emitter<UserState> emit) async {
    try {
      emit(state.copyWith(status: UserStatus.refreshing, userId: state.userId));

      Account? account = await fetchActiveProfileAccount();
      LemmyApiV3 lemmy = LemmyClient.instance.lemmyApiV3;

      if (account?.jwt == null) {
        return emit(
          state.copyWith(
            status: UserStatus.failure,
            errorMessage: 'You are not logged in. Cannot block user.',
            userId: state.userId,
          ),
        );
      }

      BlockedPerson blockedPerson = await lemmy.run(BlockPerson(
        auth: account!.jwt!,
        personId: event.personId,
        block: event.blocked,
      ));

      return emit(state.copyWith(
        status: UserStatus.success,
        personView: state.personView,
        blockedPerson: blockedPerson,
      ));
    } catch (e, s) {
      return emit(
        state.copyWith(
          status: UserStatus.failure,
          errorMessage: e.toString(),
          personView: state.personView,
        ),
      );
    }
  }
}
