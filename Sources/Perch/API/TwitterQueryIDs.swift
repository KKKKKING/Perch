import Foundation

/// GraphQL operation query IDs. These rotate as X ships new client bundles, so the
/// hardcoded values are only fallbacks; `TwitterQueryIDs.discover` refreshes them at
/// runtime by scanning the public client-web JS bundles (mirrors Bird's update-query-ids.ts).
actor TwitterQueryIDs {
    static let shared = TwitterQueryIDs()

    // Seed values are taken verbatim from Rettiwt-API's `src/requests/*.ts` (the URLs
    // embed each operation's queryId). Where Perch and Rettiwt both define an op, the
    // Rettiwt value wins. `discover()` still refreshes these at runtime.
    private var ids: [String: String] = [
        // ── Reads (timelines / lookups) ──
        "HomeLatestTimeline": "iCyHMXVutL66dZyvMtyChA",
        "HomeTimeline": "jYMvLJJjGjO3aKWY3bP5HA",
        "TweetDetail": "97JF30KziU00483E_8elBA",
        "TweetResultByRestId": "aFvUsJm2c-oDkJV75blV6g",
        "TweetResultsByRestIds": "-R17e8UqwApFGdMxa3jASA",
        "TweetEditHistory": "MGElmrYILE8wUfI8GorUYA",
        "Favoriters": "b3OrdeHDQfb9zRMC0fV3bw",
        "Retweeters": "wfglZEC0MRgBdxMa_1a5YQ",
        "UserByScreenName": "-oaLodhGbbnzJBACb1kk2Q",
        "UserByRestId": "Bbaot8ySMtJD7K2t01gW7A",
        "UsersByRestIds": "xavgLWWbFH8wm_8MQN8plQ",
        "AboutAccountQuery": "zs_jFPFT78rBpXv9Z3U2YQ",
        "ProfileSpotlightsQuery": "_pnlqeTOtnpbIL9o-fS_pg",
        "AccountOverviewQuery": "LwtiA7urqM6eDeBheAFi5w",
        "UserBusinessProfileTeamTimeline": "KFaAofDlKP7bnzskNWmjwA",
        "UserTweets": "-V26I6Pb5xDZ3C7BWwCQ_Q",
        "UserTweetsAndReplies": "61HQnvcGP870hiE-hCbG4A",
        "UserMedia": "MMnr49cP_nldzCTfeVDRtA",
        "UserHighlightsTweets": "kzKWdUA6Y1LCqlvaVILZwQ",
        "UserCreatorSubscriptions": "fl06vhYypYRcRxgLKO011Q",
        "Followers": "kuFUYP9eV1FPoEy4N-pi7w",
        "FollowersYouKnow": "yqrUptVSP9DAkVLqpc0lsg",
        "Following": "C1qZ6bs-L3oc_TKSZyxkXQ",
        "Likes": "JR2gceKucIKcVNB_9JkhsA",
        "Bookmarks": "-LGfdImKeQz0xS_jjUwzlA",
        "BookmarkFoldersSlice": "i78YDd0Tza-dV4SYs58kRg",
        "BookmarkFolderTimeline": "KJIQpsvxrTfRIlbaRIySHQ",
        "ListsManagementPageTimeline": "9mQl9vR31wjodBP9b7_wyQ",
        "NotificationsTimeline": "Ev6UMJRROInk_RMH2oVbBg",
        "FetchScheduledTweets": "ITtjAzvlZni2wWXwf295Qg",
        "SearchTimeline": "M1jEez78PEfVfbQLvlWMvQ",
        // ── Lists ──
        "ListByRestId": "Tzkkg-NaBi_y1aAUUb6_eQ",
        "ListMembers": "Bnhcen0kdsMAU1tW7U79qQ",
        "ListLatestTweetsTimeline": "fqNUs_6rqLf89u_2waWuqg",
        "ListAddMember": "EadD8ivrhZhYQr2pDmCpjA",
        "ListRemoveMember": "B5tMzrMYuFHJex_4EXFTSw",
        "ListOwnerships": "qVUHFKgADgW-BrulG9OyqA",
        "CreateList": "vr7nuEH4eh7I_-In17FZCg",
        "EditListBanner": "YuAYKtb4nACpawz8OdBwCA",
        "DeleteList": "UnN9Th1BDbeLjpgjGSpL3Q",
        "UpdateList": "hC86V8CK9BF4EkA5Wcq9hQ",
        // ── Direct messages ──
        "DMConversationSearchTabGroupsQuery": "8D8KoSq5q9d5Su3emu2dwg",
        "DMConversationSearchTabPeopleQuery": "qno3lU4_eSHtSFoWQUhEag",
        "DMMessageSearchTabQuery": "QUobOGFxSYwNxfh2zCpVGA",
        "DMPinnedInboxQuery": "_gBQBgClVuMQb8efxWkbbQ",
        "DmAllSearchSlice": "hNFpW5uN1FOZBE8u1HJicw",
        "AddParticipantsMutation": "oBwyQ0_xVbAQ8FAyG0pCRA",
        "dmBlockUser": "IYw9u1KEhrS-t-BXsau4Uw",
        "dmUnblockUser": "Krbs6Nak_o7liWQwfV1jOQ",
        "DMMessageDeleteMutation": "BJ6DtxA2llfjnRoRjaiIiw",
        "DMPinnedInboxAppend_Mutation": "o0aymgGiJY-53Y52YSUGVA",
        "DMPinnedInboxDelete_Mutation": "_TQxP2Rb0expwVP9ktGrTQ",
        "useDMReactionMutationAddMutation": "VyDyV9pC2oZEj6g52hgnhA",
        "useDMReactionMutationRemoveMutation": "bV_Nim3RYHsaJwMkTXJ6ew",
        // ── Spaces ──
        "AudioSpaceById": "rR7CQrr8kxb6fatlUaB61Q",
        // ── Writes ──
        "CreateTweet": "Uf3io9zVp1DsYxrmL5FJ7g",
        "CreateNoteTweet": "_eeuQKX1-VyRP_ROM-GN7g",
        "CreateScheduledTweet": "LCVzRQGxOaGnOnYH01NQXg",
        "DeleteScheduledTweet": "CTOVqej0JBXAZSwkp1US0g",
        "DeleteTweet": "VaenaVgh5q5ih7kvyVjgtg",
        "FavoriteTweet": "lI07N6Otwv1PhnEgXILM7A",
        "UnfavoriteTweet": "ZYKSe-w7KEslx3JhSIk5LA",
        "CreateRetweet": "LFho5rIi4xcKO90p9jwG7A",
        "DeleteRetweet": "iQtK4dl5hBmXewYZuEOKVw",
        "CreateBookmark": "aoDbu3RHznuiSkQ9aNM67Q",
        "DeleteBookmark": "Wlmlj2-xzyS1GN3a6cj-mQ",
        "RemoveFollower": "QpNfg0kpPRfjROQ_9eOLXA",
        // ── Perch-only bookmark folder mutations (not in Rettiwt) ──
        "createBookmarkFolder": "6Xxqpq8TM_CREYiuof_h5w",
        "EditBookmarkFolder": "a6kPp1cS1Dgbsjhapz1PNw",
        "DeleteBookmarkFolder": "2UTTsO-6zs93XqlEUZPsSg",
        "bookmarkTweetToFolder": "4KHZvvNbHNf07bsgnL9gWA",
        "RemoveTweetFromBookmarkFolder": "2Qbaw5LBgrTpcN8VBSlGuw",
    ]

    private var didDiscover = false

    func id(for op: String) -> String { ids[op] ?? "" }

    /// Best-effort runtime refresh. Scans x.com bundles for `queryId`/`operationName`
    /// pairs and overrides the hardcoded values. Safe to call repeatedly; runs once.
    func discover(headers: [String: String]) async {
        guard !didDiscover else { return }
        didDiscover = true
        let pages = ["https://x.com/?lang=en", "https://x.com/explore"]
        var bundles = Set<String>()
        for page in pages {
            guard let html = await fetchText(page, headers: headers) else { continue }
            for m in matches(in: html, pattern: #"https://abs\.twimg\.com/responsive-web/client-web(?:-legacy)?/[A-Za-z0-9.-]+\.js"#) {
                bundles.insert(m)
            }
        }
        guard !bundles.isEmpty else { return }
        for url in bundles.prefix(40) {
            guard ids.values.allSatisfy({ !$0.isEmpty }) == true else { break }
            guard let js = await fetchText(url, headers: headers) else { continue }
            extract(from: js)
        }
    }

    private func extract(from js: String) {
        // queryId:"X",operationName:"Y"  and  operationName:"Y",...,queryId:"X"
        let patterns = [
            #"queryId:"([A-Za-z0-9_-]+)"[^}]{0,400}?operationName:"([A-Za-z0-9_]+)""#,
            #"operationName:"([A-Za-z0-9_]+)"[^}]{0,400}?queryId:"([A-Za-z0-9_-]+)""#,
        ]
        for (i, pat) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: pat) else { continue }
            let ns = js as NSString
            re.enumerateMatches(in: js, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges == 3 else { return }
                let a = ns.substring(with: m.range(at: 1))
                let b = ns.substring(with: m.range(at: 2))
                let op = i == 0 ? b : a
                let qid = i == 0 ? a : b
                if ids[op] != nil { ids[op] = qid }
            }
        }
    }

    private func matches(in text: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private func fetchText(_ urlString: String, headers: [String: String]) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("text/html,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let started = Date()
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            NetworkLog.shared.log(method: "GET", url: url, status: nil, bytes: 0,
                                  startedAt: started, detail: "transport error")
            return nil
        }
        let code = (resp as? HTTPURLResponse)?.statusCode
        NetworkLog.shared.log(method: "GET", url: url, status: code, bytes: data.count, startedAt: started)
        guard code == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
