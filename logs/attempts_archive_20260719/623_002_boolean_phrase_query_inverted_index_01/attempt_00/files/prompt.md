Write me an Elixir module called `InvertedIndex` that implements a **Boolean full-text search engine** with positional storage and phrase queries. Unlike a ranked search engine, this one answers set-membership questions: a document either satisfies a Boolean query or it does not — there is no relevance score.

I need these functions in the public API:

- `InvertedIndex.start_link(opts)` to start the process. It must accept a `:name` option for process registration and a `:stop_words` option which is a `MapSet` of words to exclude during tokenization. If `:stop_words` is not provided, default to a built-in set containing at minimum: "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to", "of", "and", "or", "it", "this", "that", "for", "with", "as", "by", "not", "be", "has", "had", "have", "do", "does", "did", "but", "if", "from".

- `InvertedIndex.index(server, id, fields)` which indexes a document. `id` is a string, `fields` is a map of field names to text strings (e.g. `%{title: "Quick brown fox", body: "The fox jumped over the lazy dog"}`). Tokenization must: lowercase everything, split on whitespace and punctuation via the regex `~r/[^a-z0-9]+/`, then remove stop words. The **order** of the surviving tokens within each field must be preserved, because phrase queries match on consecutive positions. Indexing the same `id` again must replace the previous version of that document cleanly. Return `:ok`.

- `InvertedIndex.remove(server, id)` which removes a document from the index entirely. After removal it must not appear in any search results and must not contribute to the vocabulary. Return `:ok`. Removing a non-existent id must not raise.

- `InvertedIndex.search(server, query)` which evaluates a Boolean query expression and returns the **sorted (ascending) list of matching document ids** (a list of strings). There is no scoring. The `query` is one of the following expression forms (they nest arbitrarily):
  - `{:term, word}` — `word` is run through the same tokenization pipeline; only the first resulting token is used (if tokenization yields nothing — e.g. `word` is a stop word — the query matches no documents). A document matches if that token appears in **any** of its fields.
  - `{:phrase, text}` — `text` is run through the same tokenization pipeline to produce a sequence of terms (stop words in the phrase are dropped, exactly as in indexing). A document matches if **some single field** contains that exact term sequence at consecutive positions, in order. A one-term phrase is equivalent to `{:term, term}`. A phrase that tokenizes to nothing matches no documents.
  - `{:and, list}` — a document matches if it matches every sub-expression in `list`. An empty list matches **all** indexed documents.
  - `{:or, list}` — a document matches if it matches at least one sub-expression in `list`. An empty list matches **no** documents.
  - `{:not, expr}` — a document matches if it does **not** match `expr`. Evaluated against all currently indexed documents.

- `InvertedIndex.suggest(server, prefix, limit \\ 10)` which returns term completions from the index vocabulary. The prefix is lowercased before lookup. Return up to `limit` terms that start with the prefix, sorted by document frequency descending (terms appearing in more documents come first). Return a list of strings.

- `InvertedIndex.stats(server)` which returns `%{document_count: integer, term_count: integer}` — the total indexed documents and the total unique terms in the vocabulary.

Additional requirements:
- Implement this as a GenServer. Use no external dependencies — only standard library and OTP.
- All term storage and lookup must be case-insensitive.
- The module must be in a single file called `inverted_index.ex`.