# `FuzzyIndex` — typo-tolerant full-text search engine

**Summary:** Build an Elixir module `FuzzyIndex`: a small full-text search engine whose distinguishing feature is approximate (typo-tolerant) matching based on Levenshtein edit distance. Unlike a plain exact-match index, a query term matches a document when the document contains a vocabulary term that is *close enough* to the query term; results are ranked by how close the matches are and how often they occur.

**Delivery constraints**
- Implement as a `GenServer`.
- No external dependencies — standard library and OTP only.
- Everything in a single file called `fuzzy_index.ex`.

**Edit distance**
- Throughout, "edit distance" means the Levenshtein distance between two strings: the minimum number of single-character insertions, deletions, and substitutions (each costing 1) needed to turn one string into the other.

**Tokenization** — must run in this order:
1. lowercase the whole string;
2. split on runs of non-alphanumeric characters via the regex `~r/[^a-z0-9]+/`, dropping empty tokens;
3. remove stop words.

**Stop words**
- Default set must contain at minimum: "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to", "of", "and", "or", "it", "this", "that", "for", "with", "as", "by", "not", "be", "has", "had", "have", "do", "does", "did", "but", "if", "from".
- A caller may replace this set entirely via the `:stop_words` option.

**Case handling**
- All storage and lookup is case-insensitive: vocabulary terms are stored lowercased, and every string returned from `terms_like/3` is lowercase.

**API — `FuzzyIndex.start_link(opts)`**
- Starts the process; returns `{:ok, pid}` on success.
- Must accept an empty option list.
- Accepts `:name` for process registration; the process must then be reachable by that name from every other function.
- Accepts `:stop_words` (a `MapSet` of words to exclude during tokenization). If not given, use the built-in default set above.

**API — `FuzzyIndex.index(server, id, text)`**
- `id` is a string; `text` is a single text string.
- Tokenize `text` and store, per document, how many times each surviving token occurs.
- Indexing the same `id` again must cleanly replace the previous version of that document: its old tokens must no longer contribute to anything, and the document count must not grow.
- Returns `:ok`.

**API — `FuzzyIndex.remove(server, id)`**
- Removes a document entirely. Afterwards it must not appear in any search results and the document count must decrease.
- Any vocabulary term that no longer appears in *any* document must disappear from the vocabulary.
- Removing an id that is not present must not raise and must return `:ok`.

**API — `FuzzyIndex.search(server, query, opts \\ [])`**
- Tokenize `query` with the same pipeline used for indexing, then rank documents.
- Option `:max_distance` — maximum edit distance for a fuzzy match. Defaults to `1`.
- Option `:limit` — caps the number of returned results.

**Scoring**
- Duplicate query terms are considered once. For each unique query term `q`:
  - A vocabulary term `t` is a **match** for `q` when `edit_distance(q, t) <= max_distance`. Its **similarity** is `max_distance + 1 - edit_distance(q, t)` — so an exact match, distance `0`, has similarity `max_distance + 1`, and a match at the maximum allowed distance has similarity `1`.
  - A document's **contribution** for `q` is the **maximum**, over every matching vocabulary term `t` present in that document, of `similarity(q, t) * (number of times t occurs in the document)` — the maximum, never the sum, so a document holding both `color` and `colour` scores as if it held only the better of the two. If the document contains no matching term for `q`, its contribution for `q` is `0`.
  - A document's **score** is the sum of its contributions across all unique query terms.
- Because an exact match has strictly higher similarity than any inexact match, a document containing the exact query term contributes more, per occurrence, than one that only contains a near-miss variant.

**Search return value**
- A list of `%{id: id, score: score}` maps for every document whose score is greater than `0`, sorted by score descending.
- Apply `:limit` (if given) after sorting, so the results kept are the highest scoring ones.
- If the index is empty or the query has no surviving tokens, return `[]`.

**API — `FuzzyIndex.terms_like(server, term, max_distance \\ 1)`**
- Returns the vocabulary terms within `max_distance` edit distance of `term`.
- Lowercase `term` before comparing; do not split it.
- `max_distance` of `0` is allowed and returns only exact vocabulary matches.
- Sort matches by edit distance ascending, breaking ties alphabetically ascending.
- Returns a list of strings. `max_distance` defaults to `1`.

**API — `FuzzyIndex.stats(server)`**
- Returns `%{document_count: integer, term_count: integer}`, where `document_count` is the number of indexed documents and `term_count` is the number of distinct terms currently in the vocabulary.
- On a fresh process this is `%{document_count: 0, term_count: 0}`.
