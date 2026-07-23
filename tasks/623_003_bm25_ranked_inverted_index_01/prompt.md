# Design brief: `InvertedIndex` — a BM25-ranked full-text search engine in Elixir

## Problem

We need an in-process full-text search engine for Elixir, exposed as a module called `InvertedIndex`. Documents arrive as sets of named fields, and callers need to rank matches with the **Okapi BM25** scoring function (term-frequency saturation plus document-length normalization), weight some fields more heavily than others at query time (field-level boosting), and offer prefix suggestion over the indexed vocabulary.

## Constraints

- Implement this as a GenServer.
- Use no external dependencies — only standard library and OTP.
- The module must be in a single file called `inverted_index.ex`.
- All term storage and lookup must be case-insensitive, so mixed-case occurrences of the same word collapse into a single vocabulary term.
- There is no stemming.
- One tokenization pipeline is used everywhere (indexing and querying alike): lowercase everything, split on whitespace and punctuation via the regex `~r/[^a-z0-9]+/` (dropping empty pieces), then remove stop words.

## Scoring model

For a document `d` and the set of unique query terms (a term repeated in the query contributes exactly once):

```
score(d) = Σ_t  IDF(t) · [ f(t,d) · (k1 + 1) ] / [ f(t,d) + k1 · (1 − b + b · |d| / avgdl) ]

IDF(t) = ln( 1 + (N − df(t) + 0.5) / (df(t) + 0.5) )
```

where:
- `N` = total number of currently indexed documents,
- `df(t)` = number of documents containing term `t`,
- `f(t,d)` = the **boost-weighted count** of `t` in `d` = Σ over fields of `count(t, field) · boost(field)`,
- `|d|` = the **boost-weighted length** of `d` = Σ over fields of `token_count(field) · boost(field)`,
- `avgdl` = the mean of `|d|` over all currently indexed documents, computed with the same boosts,
- `k1`, `b` = the parameters configured at `start_link` (defaults `1.2`, `0.75`).

## Required public interface

1. **`InvertedIndex.start_link(opts)`** — starts the process, returning `{:ok, pid}`. `opts` is a keyword list that may be empty, and it must accept:
   1. `:name` — for process registration.
   2. `:stop_words` — a `MapSet` of words to exclude during tokenization. When given, it fully replaces the built-in set. If not provided, default to a built-in set containing at minimum: "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to", "of", "and", "or", "it", "this", "that", "for", "with", "as", "by", "not", "be", "has", "had", "have", "do", "does", "did", "but", "if", "from".
   3. `:k1` — the BM25 term-frequency saturation parameter. Default `1.2`.
   4. `:b` — the BM25 length-normalization parameter. Default `0.75`.

2. **`InvertedIndex.index(server, id, fields)`** — indexes a document. `id` is a string, `fields` is a map of field names to text strings (e.g. `%{title: "Quick brown fox", body: "The fox jumped over the lazy dog"}`). Tokenization follows the pipeline described above. Returns `:ok`.

3. **`InvertedIndex.remove(server, id)`** — removes a document from the index entirely. Returns `:ok`.

4. **`InvertedIndex.search(server, query, opts \\ [])`** — tokenizes the query using the same pipeline as indexing, finds all documents containing at least one query term, and returns them ranked by BM25 score descending per the scoring model above. Field boosts are passed via `opts[:boosts]` as a map like `%{title: 3, body: 1}`; fields not listed default to boost `1` (so with no boosts every field has weight 1, `f(t,d)` is the plain total count, and `|d|` is the plain total token count). Returns a list of `%{id: id, score: score}` maps sorted by score descending. Supports `opts[:limit]` to cap the number of results; with no `:limit`, return every matching document.

5. **`InvertedIndex.suggest(server, prefix, limit \\ 10)`** — returns term completions from the index vocabulary. The prefix is lowercased before lookup. Returns up to `limit` terms that start with the prefix, sorted by document frequency descending. Returns a list of strings.

6. **`InvertedIndex.stats(server)`** — returns `%{document_count: integer, term_count: integer}` — the total indexed documents and the total unique terms in the vocabulary.

## Acceptance criteria

- **Re-indexing is a clean replace.** Indexing the same `id` again must replace the previous version cleanly — terms only in the old version must disappear from search results and from the vocabulary, and the document count must not grow.
- **Removal is total.** After `remove/2`, the document must not appear in results and must not contribute to the document count used for IDF; any term that occurred only in that document must also vanish from the vocabulary, so it is no longer counted by `stats/1` and no longer offered by `suggest/3`.
- **Removing a non-existent id** must not raise and must still return `:ok`.
- **Empty search results.** Searching an empty index, or a query whose terms are all stop words or absent from the vocabulary, returns `[]`.
- **Empty suggestions.** A prefix matching nothing returns `[]`.
- **Fresh process stats.** On a fresh process, `stats/1` is `%{document_count: 0, term_count: 0}`.
