Write me an Elixir module called `InvertedIndex` that implements a full-text search engine with TF-IDF scoring, field-level boosting, and prefix suggestion.

I need these functions in the public API:

- `InvertedIndex.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a `:stop_words` option which is a `MapSet` of words to exclude during tokenization. If `:stop_words` is not provided, default to a built-in set containing at minimum: "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to", "of", "and", "or", "it", "this", "that", "for", "with", "as", "by", "not", "be", "has", "had", "have", "do", "does", "did", "but", "if", "from".

- `InvertedIndex.index(server, id, fields, opts \\ [])` which indexes a document. `id` is a string, `fields` is a map of field names to text strings (e.g. `%{title: "Quick brown fox", body: "The fox jumped over the lazy dog"}`). Tokenization must: split on whitespace and punctuation via a regex like `~r/[^a-z0-9]+/`, lowercase everything, then remove stop words. If `opts[:stem]` is `true`, apply a basic suffix-stripping stemmer that at minimum handles "-ing", "-ed", "-s", "-ly", "-tion" → "-t", "-ment". Store enough information per posting to compute TF-IDF scores later. Indexing the same `id` again must replace the previous version of that document cleanly. Return `:ok`.

- `InvertedIndex.remove(server, id)` which removes a document from the index entirely. After removal it must not appear in any search results and the document count used for IDF calculations must decrease. Return `:ok`. Removing a non-existent id must not raise.

- `InvertedIndex.search(server, query, opts \\ [])` which tokenizes the query using the same pipeline as indexing, finds all documents containing at least one query term, and returns them ranked by score descending. The scoring formula must be TF-IDF: `tf(term, doc_field) * idf(term)` where `tf = count_of_term_in_field / total_tokens_in_field` and `idf = :math.log(total_documents / documents_containing_term)`. When a document has multiple fields, the score for a term is the sum of its per-field `tf * idf * boost`. Field boosts are passed via `opts[:boosts]` as a map like `%{title: 3, body: 1}`. Fields not listed default to boost 1. If multiple query terms match, their scores are summed. Return a list of `%{id: id, score: score}` maps sorted by score descending. Support `opts[:limit]` to cap the number of results. Support `opts[:stem]` to stem the query before lookup.

- `InvertedIndex.suggest(server, prefix, limit \\ 10)` which returns term completions from the index vocabulary. The prefix is lowercased before lookup. Return up to `limit` terms that start with the prefix, sorted by document frequency descending (terms appearing in more documents come first). Return a list of strings.

- `InvertedIndex.stats(server)` which returns `%{document_count: integer, term_count: integer}` — the total indexed documents and the total unique terms in the vocabulary.

Additional requirements:
- Implement this as a GenServer. Use no external dependencies — only standard library and OTP.
- The stemmer used during search must match the one used during indexing. Stemming is controlled per-call via `opts[:stem]`. The caller is responsible for consistency (indexing with `stem: true` and searching with `stem: true`).
- All term storage and lookup must be case-insensitive.
- The module must be in a single file called `inverted_index.ex`.