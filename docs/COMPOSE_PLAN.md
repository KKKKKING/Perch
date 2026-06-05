# Plan: Perch compose — two-phase implementation (text-only first, full design second)

## Context

Goal: implement complete post / reply / quote / retweet from the `design/` prototype. Investigation found
the **text flows already exist and are wired to live X** (`AppState.onPost` → `sendLiveTweet` →
`TwitterService.postTweet` → `TwitterAPIClient.createTweet`; direct retweet via `repost()`), but several
compose affordances are dead stubs and the optimistic path is fire-and-forget.

Per the user's direction this is split into **two phases**, and this document is the saved plan:
- **Phase 1** — ship only what the current API client already supports: **text-only** post / reply / quote /
  retweet. Validate and harden it against Flare's known-good X implementation
  (`/Users/jimliu/GitHub/Flare/.../compose/ComposeDialog.kt` + `xqt` datasource). Make the compose UI honest
  (disable the not-yet-built tools).
- **Phase 2** — the full designed feature set: media upload (images/video/GIF), polls, scheduling, content
  warning, who-can-reply, ALT text, emoji, drafts, multi-account cross-post.

On execution, also persist this document into the repo at `docs/COMPOSE_PLAN.md` for the team.

## Validation vs Flare (reference: `social/xqt` datasource) — Perch is already correct, with 2 nits

| Aspect | Flare (known-good) | Perch today | Verdict |
|---|---|---|---|
| CreateTweet `features` (18 keys) | `PostCreateTweetRequestFeatures` | `createTweetFeatures` (`TwitterAPIClient.swift:113`) | **Match** ✓ |
| CreateTweet `variables` shape (tweet_text, dark_request, media.media_entities, semantic_annotation_ids, reply, attachment_url) | same | `createTweet` (`:311`) | **Match** ✓ |
| Reply | `reply{in_reply_to_tweet_id, exclude_reply_user_ids}` | identical (`:319`) | **Match** ✓ |
| Quote | `attachment_url = https://{host}/{user}/status/{id}` | `https://twitter.com/i/web/status/{id}` (`:322`) | Both valid; **align optional** |
| Retweet/Unretweet/Favorite/Bookmark query IDs | `ojPdsZsimiJrUGLR1sjUtA` / `iQtK4dl5hBmXewYZuEOKVw` / `lI07N6Otwv1PhnEgXILM7A` / `aoDbu3RHznuiSkQ9aNM67Q` / `Wlmlj2-xzyS1GN3a6cj-mQ` | same (`TwitterQueryIDs.swift:20-28`) | **Match** ✓ |
| Retweet/Favorite/Bookmark `features` | **none sent** | `nil` (`writeOp`) | **Match** ✓ (resolves the earlier "investigate features" question — leave `nil`) |
| CreateTweet query ID | `PIZtQLRIYtSa9AtW_fI2Mw` | seeded `TAJw1rBsjAtdNgTdlo2oeg`, runtime `discover()` refresh | **Differs** — fix seed (Phase 1) |
| Reply text seeding | prepends `@mentions` (`InitialTextResolver`) | none | Minor UX parity (Phase 1, optional) |

Conclusion: the existing live write layer is sound. Phase 1 is mostly **hardening + UI honesty**, not new API work.

---

# PHASE 1 — Text-only post / reply / quote / retweet (uses current API client only)

Scope: no media, no poll, no schedule, no CW. Make the existing four flows correct, robust, and visually
clean. Model behavior on Flare's text path (`ComposeData` with `medias=[]`, `poll=null`,
`referenceStatus = Reply|Quote`).

### 1.1 `Sources/Perch/API/TwitterQueryIDs.swift` — refresh the CreateTweet seed
- Update the seeded `"CreateTweet"` fallback to the current known-good `PIZtQLRIYtSa9AtW_fI2Mw` (Flare's),
  keeping runtime `discover()` as the primary source. Low-risk: only the offline fallback changes.

### 1.2 `Sources/Perch/API/TwitterAPIClient.swift` — quote URL parity (optional)
- In `createTweet`, build `attachment_url` as `https://x.com/{authorHandle}/status/{quoteId}` when the
  quoted author's handle is known (matches Flare). If the handle isn't threaded through, keep the existing
  `/i/web/status/{id}` form — it also resolves. No other change in Phase 1.

### 1.3 `Sources/Perch/Core/AppState.swift` — harden the optimistic post path (the real fix)
Currently `sendLiveTweet` (`:1071`) is fire-and-forget and discards the mapped `Post` returned by
`postTweet`. Change to reconcile:
- `sendLiveTweet(tempId:plat:text:replyTo:quote:)` — on success call new
  `reconcileInjected(tempId:plat:with:real)` to replace the temporary `np…`/reply post with the mapped
  server `Post` (real id, real timestamp/stats); on failure call new `removeInjected(tempId:plat:)` to
  **revert** the optimistic insert, then `handleTimelineError`. Both fire `appStateDidChangeActive` /
  `didAddReplyTo`.
- Apply the same temp-id reconcile to the reply branch (`addReply` at `:1086`) so a failed reply doesn't
  leave a ghost comment.
- Keep the existing optimistic-inject UX (instant feedback) — only add the success/failure reconcile.

### 1.4 `Sources/Perch/Screens/ComposeView.swift` — make the UI honest for Phase 1
The footer renders five tools (image/poll/emoji/location/calendar) with **no `onClick`** (`:197-207`), and a
static "Everyone can reply" chip (`:160-168`). For a text-only release:
- Render the five footer tools in a **disabled** style (use `theme.fgDisabled`, no hover) so they read as
  "coming later", not broken. (They get wired in Phase 2.) Alternatively hide them behind a
  `Compose.phase2Enabled` flag — recommend disabled-visible to preserve layout fidelity to the design.
- Make the "who can reply" chip non-interactive (it already is) — leave as-is, decorative.
- Confirm `canPost` stays text-based (non-empty + within limit) — correct for Phase 1; repost-empty allowed.
- Keep account switch, char ring, reply/quote reference card, ⌘↩ submit, Esc close (all already work).

### 1.5 (Optional) Reply mention seeding — parity with Flare
- When opening reply, prefill the editor with `@handle ` of the post author (and skip counting it the way X
  does is out of scope) — small UX nicety. Mark optional; skip if it complicates the char ring.

### Phase 1 verification
1. `swift build`.
2. Snapshots (no creds needed): `PERCH_SNAPSHOT=/tmp/c.png PERCH_STATE=compose|reply` and `=detail` then
   quote — confirm composer renders, tools appear disabled, reply/quote reference card shows.
3. Live (signed build `./build.sh debug`, logged-in X account): post a text tweet, reply to a tweet, quote a
   tweet, retweet + un-retweet. Verify each appears and, after refresh, the optimistic cell is replaced by
   the real server post (reconcile) and a forced failure reverts cleanly.

---

# PHASE 2 — Full designed feature set

Builds on Phase 1. Largest piece is **media upload**, whose exact contract is already reverse-engineered from
a real recorded session (`~/Downloads/x.com.har`) and matches Flare's `MediaApi`/`metadata/create`.

## 2.A Media upload (images ≤4 / 1 video / 1 GIF) — authoritative contract (from HAR + Flare)

**Host:** `https://upload.x.com/i/media/upload.json`; command params in **query string**; INIT/FINALIZE empty
body; STATUS is **GET**; only APPEND/APPENDMULTI carry a multipart body. This host **omits**
`x-client-transaction-id` / `x-twitter-active-user` / `x-twitter-client-language`, but still needs
Bearer + cookie + `x-csrf-token` + `x-twitter-auth-type` → it needs its **own request builder**, not the
GraphQL `makeRequest`. (Flare's `MediaApi` uses base `upload.twitter.com/i/`; `upload.x.com` is the current host.)

- **Image:** `INIT(total_bytes,media_type,media_category=tweet_image)` → `APPEND(media_id,segment_index=0)`
  [multipart: one part named `media`, `filename="blob"`, `application/octet-stream`] →
  `FINALIZE(original_md5=<hex MD5>)` → ready (201, no polling).
- **Video:** `INIT(...,video_duration_ms,media_category=amplify_video)` →
  `APPENDMULTI(segment_indexes=i,max_segment_size=8388608,media_md5=<chunk MD5>)` per 8 MiB chunk →
  `FINALIZE(allow_async=true)` → poll `GET STATUS` honoring `processing_info.check_after_secs` until
  `state==succeeded` (throw on `failed`).
- **GIF:** `media_category=tweet_gif` (Flare confirms this value; not in the HAR).
- **Required for every media (after upload, before CreateTweet):**
  `POST x.com/i/api/1.1/media/metadata/create.json` (JSON, on the x.com host) — baseline
  `{"media_id":"<id>","allow_download_status":{"allow_download":"true"}}`; add `alt_text.text` and/or
  `self_reported_ai_generated` when set. (Flare gates this on sensitive/alt; the HAR shows it always sent.)
- **Cropping is client-side only** (no API). `media_id` numeric in responses, string downstream. MD5 via
  CryptoKit `Insecure.MD5`.

**Implementation (mirrors the earlier media plan):**
- `Models.swift`: add `PickedMedia { fileURL, kind(image/video/gif), mimeType, alt, thumbnail }` and
  `MediaItem.localImage: NSImage?` (additive) for instant local rendering.
- `TwitterAPIClient.swift`: `createTweet(..., mediaIds:[String])` injects `media_entities`; new
  `uploadRequest` builder (upload host, reduced headers); `uploadMedia(data:mimeType:kind:durationMs:)`
  (INIT→APPEND(MULTI)→FINALIZE→[STATUS]); `multipartMediaBody`; `md5Hex`; `setMediaMetadata(...)`.
- `TwitterService.postTweet(text:media:replyTo:quote:)`: upload each pick (+ duration via `AVAsset`),
  `setMediaMetadata` per item, then `createTweet(mediaIds:)`; still returns mapped `Post?`.
- `AppState.onPost(...,media:)`: build optimistic `Media` from local thumbnails; reconcile via the Phase-1
  temp-id machinery.
- `ComposeView.swift`: wire the **image** footer tool → `NSOpenPanel` (png/jpeg/gif/mp4/mov), exclusivity
  (≤4 images | 1 video | 1 gif), local thumbnail grid (new `ComposeMediaGrid` with remove/ALT chrome),
  `canPost` allows media-only; dynamic height via existing `by`/`setContentHeight`.
- `MediaViews.swift`: `ImageTile` prefers `localImage`; add `ComposeMediaGrid`.
- `RootViewController.swift`: forward `media` in the `mountCompose` `onPost` closure.

## 2.B Other designed features (from `design/project/app/compose.jsx` + Flare parity)
Implement the remaining stubbed affordances, each enabling its footer tool:
- **ALT text editor / media editor** (crop client-side, ALT → `metadata/create`). Flare: `altTextMaxLength=1000`.
- **Poll** — options (2–4) + duration; X compose has no poll in the captured flow → confirm endpoint/spec
  before building (likely a CreateTweet `card_uri`/poll variable); treat as **needs-API-confirmation**.
- **Schedule** — scheduled-post banner + dialog; needs the scheduled-tweet API (separate op) → confirm spec.
- **Who-can-reply** — `conversation_control` in CreateTweet variables (Flare has
  `PostCreateTweetRequestVariablesConversationControl`); wire the scope menu from the design.
- **Content disclosure (AI / paid)** — `content_disclosure.ai_generated_disclosure` in CreateTweet (seen in
  HAR) + `self_reported_ai_generated` in metadata.
- **Emoji picker**, **content warning / spoiler** (X uses none; Mastodon-style — likely N/A for X),
  **drafts** (Flare `DraftBoxScreen`), **multi-account cross-post** (Flare selects N accounts and sends to
  each independently). Prioritize media + who-can-reply + ALT + AI disclosure; poll/schedule gated on API spec.

### Phase 2 verification
- Snapshots: add a `debugApply` branch seeding sample `PickedMedia` (e.g. `PERCH_STATE=compose-media`) to
  render the grid without `NSOpenPanel`; snapshot poll/schedule/scope dialogs.
- Live signed build: upload 1 image, 4 images, a video (verify STATUS polling), a GIF; post each as new/reply/
  quote; set ALT; toggle who-can-reply and AI disclosure; confirm on x.com.

## Risks
- **Upload host header divergence** — use the dedicated `uploadRequest` (no txn-id / active-user / lang).
- **MD5** required (`original_md5`, per-chunk `media_md5`); **multipart** single `media`/`blob`/octet-stream,
  UUID boundary. **STATUS polling** must honor `check_after_secs`, cap (~120 s), handle `failed`.
- **Poll/Schedule APIs not captured** — confirm specs (or another HAR) before building those two.
- CreateTweet query id rotates — keep `discover()`; Phase-1 seed refresh is just the offline fallback.
- `MediaType` has no `.gif` (optimistic = static image). `Data(contentsOf:)` loads whole video into memory.
