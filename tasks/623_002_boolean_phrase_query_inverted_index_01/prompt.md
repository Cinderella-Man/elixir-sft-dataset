# Design brief: `InvertedIndex` — a Boolean full-text search engine

## Problem

We need a Boolean full-text search engine, written as an Elixir module called `InvertedIndex`, with positional storage and phrase queries. Unlike a ranked search engine, this one answers set-membership questions: a document either satisfies a Boolean query or it does not — there is no relevance score.

## Constraints

- Implement this as a GenServer.
- Use no external dependencies — only standard library and OTP.
- All term storage and lookup must be case-insensitive.
- The module must be in a single file called `inverted_index.ex`.
- Tokenization is a single shared pipeline used everywhere text is processed (indexing, `{:term, word}`, `{:phrase, text}`). It must: lowercase everything, split on whitespace and punctuation via the regex `~r/[^a-z0-9]+/`, then remove stop words.
- The **order** of the surviving tokens within each field must be preserved, because phrase queries match on consecutive positions.

## Required interface

The public API consists of the following functions.

1. `InvertedIndex.start_link(opts)` — starts the process. It must accept a `:name` option for process registration and a `:stop_words` option which is a `MapSet` of words to exclude during tokenization. If `:stop_words` is not provided, default to a built-in set containing at minimum: "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to", "of", "and", "or", "it", "this", "that", "for", "with", "as", "by", "not", "be", "has", "had", "have", "do", "does", "did", "but", "if", "from".

2. `InvertedIndex.index(server, id, fields)` — indexes a document. `id` is a string, `fields` is a map of field names to text strings (e.g. `%{title: "Quick brown fox", body: "The fox jumped over the lazy dog"}`). Each field's text goes through the tokenization pipeline described above. Indexing the same `id` again must replace the previous version of that document cleanly. Return `:ok`.

3. `InvertedIndex.remove(server, id)` — removes a document from the index entirely. After removal it must not appear in any search results and must not contribute to the vocabulary. Return `:ok`. Removing a non-existent id must not raise.

4. `InvertedIndex.search(server, query)` — evaluates a Boolean query expression and returns the **sorted (ascending) list of matching document ids** (a list of strings). There is no scoring. The `query` is one of the following expression forms, which nest arbitrarily:
   - `{:term, word}` — `word` is run through the same tokenization pipeline; only the first resulting token is used (if tokenization yields nothing — e.g. `word` is a stop word — the query matches no documents). A document matches if that token appears in **any** of its fields.
   - `{:phrase, text}` — `text` is run through the same tokenization pipeline to produce a sequence of terms (stop words in the phrase are dropped, exactly as in indexing). A document matches if **some single field** contains that exact term sequence at consecutive positions, in order. A one-term phrase is equivalent to `{:term, term}`. A phrase that tokenizes to nothing matches no documents.
   - `{:and, list}` — a document matches if it matches every sub-expression in `list`. An empty list matches **all** indexed documents.
   - `{:or, list}` — a document matches if it matches at least one sub-expression in `list`. An empty list matches **no** documents.
   - `{:not, expr}` — a document matches if it does **not** match `expr`. Evaluated against all currently indexed documents.

5. `InvertedIndex.suggest(server, prefix, limit \\ 10)` — returns term completions from the index vocabulary. The prefix is lowercased before lookup. Return up to `limit` terms that start with the prefix, sorted by document frequency descending (terms appearing in more documents come first). Return a list of strings.

6. `InvertedIndex.stats(server)` — returns `%{document_count: integer, term_count: integer}` — the total indexed documents and the total unique terms in the vocabulary.

## Acceptance criteria

- The engine is a GenServer in the single file `inverted_index.ex`, dependency-free beyond the standard library and OTP, and case-insensitive in all term storage and lookup.
- `start_link/1` honours `:name` for registration and `:stop_words` as a `MapSet`, falling back to the built-in default stop word set listed above when the option is absent.
- `index/3` returns `:ok`, tokenizes by lowercasing, splitting on `~r/[^a-z0-9]+/`, and dropping stop words while preserving surviving token order per field; re-indexing an existing `id` leaves no trace of the prior version.
- `remove/2` returns `:ok`, erases the document from both search results and the vocabulary, and does not raise on an unknown id.
- `search/2` returns matching ids as an ascending sorted list of strings, with no scores, and correctly evaluates `{:term, word}`, `{:phrase, text}`, `{:and, list}`, `{:or, list}` and `{:not, expr}` — including the empty-`{:and, list}` (matches all indexed documents), empty-`{:or, list}` (matches none), empty-tokenization (matches none), single-term-phrase, and arbitrary nesting cases.
- `suggest/3` lowercases the prefix, defaults `limit` to `10`, and returns at most `limit` matching vocabulary terms as strings ordered by descending document frequency.
- `stats/1` reports `%{document_count: integer, term_count: integer}` reflecting the current documents and unique vocabulary terms.
