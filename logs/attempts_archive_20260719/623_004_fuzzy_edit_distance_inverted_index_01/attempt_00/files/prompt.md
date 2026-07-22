Write me an Elixir module called `FuzzyIndex` that implements a small full-text search engine whose distinguishing feature is **approximate (typo-tolerant) matching** based on Levenshtein edit distance. Unlike a plain exact-match index, a query term matches a document when the document contains a vocabulary term that is *close enough* to the query term, and results are ranked by how close the matches are and how often they occur.

Implement this as a `GenServer` using no external dependencies — only the standard library and OTP. Put everything in a single file called `fuzzy_index.ex`.

## Edit distance

Throughout, "edit distance" means the **Levenshtein distance** between two strings: the minimum number of single-character insertions, deletions, and substitutions (each costing 1) needed to turn one string into the other.

## Tokenization

Tokenizing a piece of text must, in this order:

1. lowercase the whole string,
2. split it on runs of non-alphanumeric characters via the regex `~r/[^a-z0-9]+/` (dropping empty tokens),
3. remove stop words.

The default stop-word set must contain at minimum: "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to", "of", "and", "or", "it", "this", "that", "for", "with", "as", "by", "not", "be", "has", "had", "have", "do", "does", "did", "but", "if", "from". A caller may replace this set entirely via the `:stop_words` option.

All storage and lookup is case-insensitive.

## Public API

- `FuzzyIndex.start_link(opts)` — start the process. Accept a `:name` option for process registration and a `:stop_words` option (a `MapSet` of words to exclude during tokenization). If `:stop_words` is not given, use the built-in default set above.

- `FuzzyIndex.index(server, id, text)` — index a document. `id` is a string and `text` is a single text string. Tokenize `text` and store, per document, how many times each surviving token occurs. Indexing the same `id` again must cleanly replace the previous version of that document (its old tokens must no longer contribute to anything). Return `:ok`.

- `FuzzyIndex.remove(server, id)` — remove a document entirely. After removal it must not appear in any search results, the document count must decrease, and any vocabulary term that no longer appears in *any* document must disappear from the vocabulary. Removing an id that is not present must not raise and must return `:ok`.

- `FuzzyIndex.search(server, query, opts \\ [])` — tokenize `query` with the same pipeline used for indexing, then rank documents. Options:
  - `:max_distance` — the maximum edit distance for a fuzzy match. Defaults to `1`.
  - `:limit` — cap the number of returned results.

  Scoring is defined as follows. Duplicate query terms are considered once. For each unique query term `q`:
  - A vocabulary term `t` is a **match** for `q` when `edit_distance(q, t) <= max_distance`. Its **similarity** is `max_distance + 1 - edit_distance(q, t)` (so an exact match, distance `0`, has similarity `max_distance + 1`, and a match at the maximum allowed distance has similarity `1`).
  - A document's **contribution** for query term `q` is the **maximum**, over every matching vocabulary term `t` that is present in that document, of `similarity(q, t) * (number of times t occurs in the document)`. If the document contains no matching term for `q`, its contribution for `q` is `0`.
  - A document's **score** is the sum of its contributions across all unique query terms.

  Return a list of `%{id: id, score: score}` maps for every document whose score is greater than `0`, sorted by score descending. Apply `:limit` (if given) after sorting. If the index is empty or the query has no surviving tokens, return `[]`.

  Because an exact match has strictly higher similarity than any inexact match, a document containing the exact query term contributes more, per occurrence, than one that only contains a near-miss variant.

- `FuzzyIndex.terms_like(server, term, max_distance \\ 1)` — return the vocabulary terms within `max_distance` edit distance of `term`. Lowercase `term` before comparing (do not split it). Return the matching terms sorted by edit distance ascending, breaking ties alphabetically ascending. Return a list of strings. `max_distance` defaults to `1`.

- `FuzzyIndex.stats(server)` — return `%{document_count: integer, term_count: integer}`, where `document_count` is the number of indexed documents and `term_count` is the number of distinct terms currently in the vocabulary.