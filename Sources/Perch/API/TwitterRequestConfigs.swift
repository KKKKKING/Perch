import Foundation

/// Per-operation GraphQL `features` / `fieldToggles`, transcribed verbatim from
/// Rettiwt-API's `src/requests/*.ts`. When Perch and Rettiwt both define an op, the
/// Rettiwt values win (the request bodies/queries below are the source of truth).
///
/// Most timeline GET operations share one large "grok" feature set; that canonical
/// set lives in `timelineGrok`, and the few ops that diverge are derived from it.
enum TwitterRequestConfigs {

    /// Features for a GraphQL operation (empty when the op sends no `features`).
    static func features(_ op: String) -> [String: Bool] { featuresByOp[op] ?? [:] }

    /// `fieldToggles` for a GraphQL operation, or nil when none are sent.
    static func fieldToggles(_ op: String) -> [String: Bool]? { fieldTogglesByOp[op] }

    // MARK: - Canonical timeline feature set (shared by most read timelines)

    /// The 34-key set used by followers/following*/likes/media/lists/search/etc.
    /// (*following toggles two keys — see `featuresByOp`.)
    private static let timelineGrok: [String: Bool] = [
        "rweb_video_screen_enabled": false,
        "profile_label_improvements_pcf_label_in_post_enabled": true,
        "responsive_web_profile_redirect_enabled": false,
        "rweb_tipjar_consumption_enabled": true,
        "verified_phone_label_enabled": true,
        "creator_subscriptions_tweet_preview_api_enabled": true,
        "responsive_web_graphql_timeline_navigation_enabled": true,
        "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
        "premium_content_api_read_enabled": false,
        "communities_web_enable_tweet_community_results_fetch": true,
        "c9s_tweet_anatomy_moderator_badge_enabled": true,
        "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
        "responsive_web_grok_analyze_post_followups_enabled": true,
        "responsive_web_jetfuel_frame": true,
        "responsive_web_grok_share_attachment_enabled": true,
        "articles_preview_enabled": true,
        "responsive_web_edit_tweet_api_enabled": true,
        "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
        "view_counts_everywhere_api_enabled": true,
        "longform_notetweets_consumption_enabled": true,
        "responsive_web_twitter_article_tweet_consumption_enabled": true,
        "tweet_awards_web_tipping_enabled": false,
        "responsive_web_grok_show_grok_translated_post": false,
        "responsive_web_grok_analysis_button_from_backend": true,
        "creator_subscriptions_quote_tweet_preview_enabled": false,
        "freedom_of_speech_not_reach_fetch_enabled": true,
        "standardized_nudges_misinfo": true,
        "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
        "longform_notetweets_rich_text_read_enabled": true,
        "longform_notetweets_inline_media_enabled": true,
        "responsive_web_grok_image_annotation_enabled": true,
        "responsive_web_grok_imagine_annotation_enabled": true,
        "responsive_web_grok_community_note_auto_translation_is_enabled": false,
        "responsive_web_enhance_cards_enabled": false,
    ]

    /// `timelineGrok` with `responsive_web_jetfuel_frame=false` and no
    /// `responsive_web_grok_imagine_annotation_enabled` (Bookmarks / BookmarkFolders / Following).
    private static var timelineGrokNoJet: [String: Bool] = {
        var d = timelineGrok
        d["responsive_web_jetfuel_frame"] = false
        d.removeValue(forKey: "responsive_web_grok_imagine_annotation_enabled")
        return d
    }()

    /// `timelineGrok` with `responsive_web_grok_imagine_annotation_enabled=false`
    /// (BookmarkFolderTimeline).
    private static var timelineGrokImagineOff: [String: Bool] = {
        var d = timelineGrok
        d["responsive_web_grok_imagine_annotation_enabled"] = false
        return d
    }()

    // MARK: - Op → features

    private static let featuresByOp: [String: [String: Bool]] = [
        // ── Shared timeline reads ──
        "Followers": timelineGrok,
        "FollowersYouKnow": timelineGrok,
        "Following": timelineGrokNoJet,
        "Likes": timelineGrok,
        "UserTweets": timelineGrok,
        "UserTweetsAndReplies": timelineGrok,
        "UserMedia": timelineGrok,
        "UserHighlightsTweets": timelineGrok,
        "UserCreatorSubscriptions": timelineGrok,
        "UserBusinessProfileTeamTimeline": timelineGrok,
        "ListsManagementPageTimeline": timelineGrok,
        "NotificationsTimeline": timelineGrok,
        "Favoriters": timelineGrok,
        "Retweeters": timelineGrok,
        "SearchTimeline": timelineGrok,
        "Bookmarks": timelineGrokNoJet,
        "BookmarkFoldersSlice": timelineGrokNoJet,
        "BookmarkFolderTimeline": timelineGrokImagineOff,
        "ListMembers": timelineGrok,
        "ListOwnerships": timelineGrok,
        "ListLatestTweetsTimeline": timelineGrok,

        // ── TweetResultsByRestIds (bulk tweet details) ──
        "TweetResultsByRestIds": [
            "rweb_lists_timeline_redesign_enabled": true,
            "responsive_web_graphql_exclude_directive_enabled": true,
            "verified_phone_label_enabled": true,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "tweetypie_unmention_optimization_enabled": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": false,
            "tweet_awards_web_tipping_enabled": false,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": true,
            "responsive_web_media_download_video_enabled": false,
            "responsive_web_enhance_cards_enabled": false,
            "responsive_web_grok_show_grok_translated_post": false,
            "responsive_web_grok_analyze_post_followups_enabled": false,
            "responsive_web_jetfuel_frame": false,
            "responsive_web_grok_image_annotation_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": false,
            "c9s_tweet_anatomy_moderator_badge_enabled": false,
            "premium_content_api_read_enabled": false,
            "responsive_web_grok_analysis_button_from_backend": false,
            "profile_label_improvements_pcf_label_in_post_enabled": false,
            "rweb_tipjar_consumption_enabled": false,
            "creator_subscriptions_quote_tweet_preview_enabled": false,
            "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
            "articles_preview_enabled": false,
            "responsive_web_grok_share_attachment_enabled": false,
            "responsive_web_grok_imagine_annotation_enabled": false,
            "responsive_web_grok_community_note_auto_translation_is_enabled": false,
            "responsive_web_profile_redirect_enabled": false,
        ],

        // ── TweetResultByRestId (single tweet details) ──
        "TweetResultByRestId": [
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "premium_content_api_read_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
            "responsive_web_grok_analyze_post_followups_enabled": false,
            "responsive_web_jetfuel_frame": false,
            "responsive_web_grok_share_attachment_enabled": true,
            "articles_preview_enabled": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "tweet_awards_web_tipping_enabled": false,
            "responsive_web_grok_show_grok_translated_post": false,
            "responsive_web_grok_analysis_button_from_backend": false,
            "creator_subscriptions_quote_tweet_preview_enabled": false,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": true,
            "profile_label_improvements_pcf_label_in_post_enabled": true,
            "rweb_tipjar_consumption_enabled": true,
            "verified_phone_label_enabled": true,
            "responsive_web_grok_image_annotation_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_enhance_cards_enabled": false,
        ],

        // ── TweetEditHistory ──
        "TweetEditHistory": [
            "premium_content_api_read_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
            "responsive_web_grok_analyze_post_followups_enabled": true,
            "rweb_cashtags_composer_attachment_enabled": true,
            "responsive_web_jetfuel_frame": true,
            "responsive_web_grok_share_attachment_enabled": true,
            "responsive_web_grok_annotations_enabled": true,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "rweb_video_screen_enabled": false,
            "responsive_web_edit_tweet_api_enabled": true,
            "rweb_conversational_replies_downvote_enabled": false,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "content_disclosure_indicator_enabled": true,
            "content_disclosure_ai_generated_indicator_enabled": true,
            "responsive_web_grok_show_grok_translated_post": true,
            "responsive_web_grok_analysis_button_from_backend": true,
            "post_ctas_fetch_enabled": true,
            "profile_label_improvements_pcf_label_in_post_enabled": true,
            "responsive_web_profile_redirect_enabled": false,
            "rweb_tipjar_consumption_enabled": false,
            "verified_phone_label_enabled": false,
            "rweb_cashtags_enabled": true,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": false,
            "articles_preview_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "responsive_web_grok_community_note_auto_translation_is_enabled": true,
            "responsive_web_grok_image_annotation_enabled": true,
            "responsive_web_grok_imagine_annotation_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_enhance_cards_enabled": false,
        ],

        // ── TweetDetail (replies) ──
        "TweetDetail": timelineGrok,

        // ── CreateTweet ──
        "CreateTweet": [
            "premium_content_api_read_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
            "responsive_web_grok_analyze_post_followups_enabled": true,
            "responsive_web_jetfuel_frame": false,
            "responsive_web_grok_share_attachment_enabled": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "tweet_awards_web_tipping_enabled": false,
            "responsive_web_grok_show_grok_translated_post": false,
            "responsive_web_grok_analysis_button_from_backend": true,
            "creator_subscriptions_quote_tweet_preview_enabled": false,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": true,
            "profile_label_improvements_pcf_label_in_post_enabled": true,
            "rweb_tipjar_consumption_enabled": true,
            "verified_phone_label_enabled": true,
            "articles_preview_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "responsive_web_grok_image_annotation_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_enhance_cards_enabled": false,
            "responsive_web_grok_imagine_annotation_enabled": false,
            "responsive_web_profile_redirect_enabled": false,
            "responsive_web_grok_community_note_auto_translation_is_enabled": false,
        ],

        // ── CreateNoteTweet (long-form) ──
        "CreateNoteTweet": [
            "premium_content_api_read_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
            "responsive_web_grok_analyze_post_followups_enabled": true,
            "responsive_web_jetfuel_frame": true,
            "responsive_web_grok_share_attachment_enabled": true,
            "responsive_web_grok_annotations_enabled": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "tweet_awards_web_tipping_enabled": false,
            "content_disclosure_indicator_enabled": true,
            "content_disclosure_ai_generated_indicator_enabled": true,
            "responsive_web_grok_show_grok_translated_post": true,
            "responsive_web_grok_analysis_button_from_backend": true,
            "post_ctas_fetch_enabled": true,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": false,
            "profile_label_improvements_pcf_label_in_post_enabled": true,
            "responsive_web_profile_redirect_enabled": false,
            "rweb_tipjar_consumption_enabled": false,
            "verified_phone_label_enabled": false,
            "articles_preview_enabled": true,
            "responsive_web_grok_community_note_auto_translation_is_enabled": false,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "responsive_web_grok_image_annotation_enabled": true,
            "responsive_web_grok_imagine_annotation_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_enhance_cards_enabled": false,
        ],

        // ── HomeLatestTimeline (followed feed) ──
        "HomeLatestTimeline": homeFeedFeatures,
        // ── HomeTimeline (recommended feed) ──
        "HomeTimeline": homeFeedFeatures,

        // ── UserByRestId (details by id) ──
        "UserByRestId": [
            "hidden_profile_subscriptions_enabled": true,
            "profile_label_improvements_pcf_label_in_post_enabled": true,
            "rweb_tipjar_consumption_enabled": true,
            "verified_phone_label_enabled": true,
            "highlights_tweets_tab_ui_enabled": true,
            "responsive_web_twitter_article_notes_tab_enabled": true,
            "subscriptions_feature_can_gift_premium": true,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_profile_redirect_enabled": false,
        ],

        // ── UserByScreenName (details by username) ──
        "UserByScreenName": [
            "hidden_profile_subscriptions_enabled": true,
            "profile_label_improvements_pcf_label_in_post_enabled": true,
            "responsive_web_profile_redirect_enabled": false,
            "rweb_tipjar_consumption_enabled": true,
            "verified_phone_label_enabled": true,
            "subscriptions_verification_info_is_identity_verified_enabled": true,
            "subscriptions_verification_info_verified_since_enabled": true,
            "highlights_tweets_tab_ui_enabled": true,
            "responsive_web_twitter_article_notes_tab_enabled": true,
            "subscriptions_feature_can_gift_premium": true,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "responsive_web_graphql_timeline_navigation_enabled": true,
        ],

        // ── UsersByRestIds (bulk user details) ──
        "UsersByRestIds": [
            "hidden_profile_likes_enabled": false,
            "hidden_profile_subscriptions_enabled": false,
            "responsive_web_graphql_exclude_directive_enabled": true,
            "verified_phone_label_enabled": true,
            "subscriptions_verification_info_verified_since_enabled": true,
            "highlights_tweets_tab_ui_enabled": true,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "profile_label_improvements_pcf_label_in_post_enabled": false,
            "rweb_tipjar_consumption_enabled": false,
            "responsive_web_profile_redirect_enabled": false,
        ],

        // ── List add/remove member & details ──
        "ListAddMember": listMutationFeatures,
        "ListRemoveMember": listMutationFeatures,
        "ListByRestId": listMutationFeatures,
        "CreateList": listMutationFeatures,
        "EditListBanner": listMutationFeatures,
        "DeleteList": listMutationFeatures,
        "UpdateList": listMutationFeatures,

        // ── AudioSpaceById ──
        "AudioSpaceById": [
            "spaces_2022_h2_spaces_communities": true,
            "spaces_2022_h2_clipping": true,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "profile_label_improvements_pcf_label_in_post_enabled": true,
            "responsive_web_profile_redirect_enabled": false,
            "rweb_tipjar_consumption_enabled": false,
            "verified_phone_label_enabled": false,
            "premium_content_api_read_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
            "responsive_web_grok_analyze_post_followups_enabled": true,
            "responsive_web_jetfuel_frame": true,
            "responsive_web_grok_share_attachment_enabled": true,
            "responsive_web_grok_annotations_enabled": false,
            "articles_preview_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "tweet_awards_web_tipping_enabled": false,
            "responsive_web_grok_show_grok_translated_post": false,
            "responsive_web_grok_analysis_button_from_backend": true,
            "post_ctas_fetch_enabled": true,
            "creator_subscriptions_quote_tweet_preview_enabled": false,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": true,
            "responsive_web_grok_image_annotation_enabled": true,
            "responsive_web_grok_imagine_annotation_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_grok_community_note_auto_translation_is_enabled": false,
            "responsive_web_enhance_cards_enabled": false,
        ],
    ]

    // MARK: - Op → fieldToggles

    private static let fieldTogglesByOp: [String: [String: Bool]] = [
        "TweetDetail": [
            "withArticleRichContentState": true,
            "withArticlePlainText": false,
            "withGrokAnalyze": false,
            "withDisallowedReplyControls": false,
        ],
        "Bookmarks": ["withArticlePlainText": false],
        "BookmarkFolderTimeline": ["withArticlePlainText": false],
        "HomeLatestTimeline": ["withArticlePlainText": false],
        "HomeTimeline": ["withArticlePlainText": false],
        "SearchTimeline": ["withArticlePlainText": false],
        "UserByScreenName": ["withAuxiliaryUserLabels": true],
        "UserHighlightsTweets": ["withArticlePlainText": false],
        "Likes": ["withArticlePlainText": false],
        "ListsManagementPageTimeline": ["withArticlePlainText": false],
        "UserMedia": ["withArticlePlainText": false],
        "UserTweets": ["withArticlePlainText": false],
        "UserTweetsAndReplies": ["withArticlePlainText": false],
    ]

    // MARK: - Shared dictionaries referenced above

    /// Features shared by HomeLatestTimeline (followed) and HomeTimeline (recommended).
    private static let homeFeedFeatures: [String: Bool] = [
        "rweb_video_screen_enabled": false,
        "rweb_cashtags_enabled": true,
        "profile_label_improvements_pcf_label_in_post_enabled": true,
        "responsive_web_profile_redirect_enabled": false,
        "rweb_tipjar_consumption_enabled": false,
        "verified_phone_label_enabled": true,
        "creator_subscriptions_tweet_preview_api_enabled": true,
        "responsive_web_graphql_timeline_navigation_enabled": true,
        "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
        "premium_content_api_read_enabled": false,
        "communities_web_enable_tweet_community_results_fetch": true,
        "c9s_tweet_anatomy_moderator_badge_enabled": true,
        "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
        "responsive_web_grok_analyze_post_followups_enabled": true,
        "responsive_web_jetfuel_frame": true,
        "responsive_web_grok_share_attachment_enabled": true,
        "responsive_web_grok_annotations_enabled": true,
        "articles_preview_enabled": true,
        "responsive_web_edit_tweet_api_enabled": true,
        "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
        "view_counts_everywhere_api_enabled": true,
        "longform_notetweets_consumption_enabled": true,
        "responsive_web_twitter_article_tweet_consumption_enabled": true,
        "content_disclosure_indicator_enabled": true,
        "content_disclosure_ai_generated_indicator_enabled": true,
        "responsive_web_grok_show_grok_translated_post": true,
        "responsive_web_grok_analysis_button_from_backend": true,
        "post_ctas_fetch_enabled": true,
        "freedom_of_speech_not_reach_fetch_enabled": true,
        "standardized_nudges_misinfo": true,
        "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
        "longform_notetweets_rich_text_read_enabled": true,
        "longform_notetweets_inline_media_enabled": false,
        "responsive_web_grok_image_annotation_enabled": true,
        "responsive_web_grok_imagine_annotation_enabled": true,
        "responsive_web_grok_community_note_auto_translation_is_enabled": true,
        "responsive_web_enhance_cards_enabled": false,
    ]

    /// Features shared by ListAddMember / ListRemoveMember / ListByRestId.
    private static let listMutationFeatures: [String: Bool] = [
        "profile_label_improvements_pcf_label_in_post_enabled": true,
        "responsive_web_profile_redirect_enabled": false,
        "rweb_tipjar_consumption_enabled": true,
        "verified_phone_label_enabled": true,
        "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
        "responsive_web_graphql_timeline_navigation_enabled": true,
    ]
}
