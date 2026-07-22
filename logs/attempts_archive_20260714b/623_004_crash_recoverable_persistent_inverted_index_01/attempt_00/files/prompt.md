Write me an Elixir module called `InvertedIndex` that implements a **crash-recoverable, disk-persistent** full-text search engine. Every mutation is durably recorded on disk before it is acknowledged, and the full index is rebuilt from disk when the process restarts — so a crash never loses an acknowledged write.

I need these functions in the public API:

- `InvertedIndex.start_link(opts)` to start the process. It must accept:
  - `:dir` (**required**) — a filesystem directory the server uses for its persistence files. Create it if it does not exist.
  - `:name` — for process registration.
  - `:stop_words` — a `MapSet` of words to exclude during tokenization. If not provided, default to a built-in set containing at minimum: "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to", "of", "and", "or", "it", "this", "that", "for", "with", "as", "by", "not", "be", "has", "had", "have", "do", "does", "did", "but", "if", "from".

  On start, the server must **recover its in-memory state** from `:dir`: if a snapshot file is present, load it, and then replay every write-ahead-log (WAL) entry recorded after that snapshot, in order. After `start_link` returns, the index must reflect every previously acknowledged `index`/`remove` call for that directory.

- `InvertedIndex.index(server, id, fields)` which indexes a document. `id` is a string, `fields` is a map of field names to text strings. Tokenization: lowercase everything, split on whitespace and punctuation via the regex `~r/[^a-z0-9]+/`, then remove stop words. The mutation must be **durably appended to the WAL (and flushed to disk) before the call returns**. Indexing the same `id` again must replace the previous version cleanly. Return `:ok`.

- `InvertedIndex.remove(server, id)` which removes a document entirely. The mutation must be durably appended to the WAL before returning. After removal the document must not appear in results and must not contribute to the document count used for IDF. Return `:ok`. Removing a non-existent id must not raise.

- `InvertedIndex.search(server, query, opts \\ [])` which tokenizes the query using the same pipeline as indexing, finds documents containing at least one query term, and returns them ranked by TF-IDF score descending. The scoring formula is `tf(term, field) · idf(term)` where `tf = count_of_term_in_field / total_tokens_in_field` and `idf = :math.log(total_documents / documents_containing_term)`; a term's score for a document is summed across all fields in which it appears, and scores of distinct query terms are summed. Return a list of `%{id: id, score: score}` maps sorted by score descending. Support `opts[:limit]` to cap the number of results.

- `InvertedIndex.snapshot(server)` which writes the entire current index state to the snapshot file and then truncates the WAL (so subsequent recovery loads the snapshot and replays only WAL entries written after it). This compaction must not change any query results. Return `:ok`.

- `InvertedIndex.suggest(server, prefix, limit \\ 10)` which returns up to `limit` vocabulary terms starting with the (lowercased) prefix, sorted by document frequency descending. Return a list of strings.

- `InvertedIndex.stats(server)` which returns `%{document_count: integer, term_count: integer}`.

Additional requirements:
- Implement this as a GenServer. Use no external dependencies — only standard library and OTP (you may use `:erlang.term_to_binary/1`, `File`, and `:file.sync/1`).
- Durability must not depend on a graceful shutdown: because each mutation is flushed to disk before acknowledgement, a hard kill of the process must still leave every acknowledged mutation recoverable on the next `start_link` with the same `:dir`.
- Two servers using different directories must be completely independent.
- All term storage and lookup must be case-insensitive.
- The module must be in a single file called `inverted_index.ex`.