# Play listing, November 2026

The second Play listing pass: wording that helps search, plus an accurate share-link line. It is staged until submission 13 (1.1.5 plus the new descriptions) clears Google review.

- `listing-in-review.json`: the text in submission 13, sent 2026-11-12.
- `make_listing.py`: builds `listing.json` from it.
  - Replaces the heading and opening paragraph, and the short description, in all 8 languages. They now include "music maker", "song & beat maker", "kids", "families" and "beginners", and their translations.
  - Rewrites the share-link bullet. On Android a shared link opens the web player, not the app.
  - Titles stay the same unless `titles.json` names one (`{"en-US": "..."}`).
  - Checks Play's length limits and the banned words.
- `listing.json`: what will be sent to Play.

To send it, run a dry run first, then commit only once Publishing overview shows nothing in review:

    python3 -I bp-tools/store-api/play_listing.py com.madewithbestpractice.emojio store/play-2026-11/listing.json
    # then add --commit --nothing-in-review
