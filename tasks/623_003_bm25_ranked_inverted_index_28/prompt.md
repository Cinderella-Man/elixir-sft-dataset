# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `stats` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

Write me an Elixir module called `InvertedIndex` that implements a full-text search engine ranked with the **Okapi BM25** scoring function (term-frequency saturation plus document-length normalization), field-level boosting, and prefix suggestion.

I need these functions in the public API:

- `InvertedIndex.start_link(opts)` to start the process, returning `{:ok, pid}`. `opts` is a keyword list that may be empty, and it must accept:
  - `:name` — for process registration.
  - `:stop_words` — a `MapSet` of words to exclude during tokenization. When given, it fully replaces the built-in set. If not provided, default to a built-in set containing at minimum: "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to", "of", "and", "or", "it", "this", "that", "for", "with", "as", "by", "not", "be", "has", "had", "have", "do", "does", "did", "but", "if", "from".
  - `:k1` — the BM25 term-frequency saturation parameter. Default `1.2`.
  - `:b` — the BM25 length-normalization parameter. Default `0.75`.

- `InvertedIndex.index(server, id, fields)` which indexes a document. `id` is a string, `fields` is a map of field names to text strings (e.g. `%{title: "Quick brown fox", body: "The fox jumped over the lazy dog"}`). Tokenization must: lowercase everything, split on whitespace and punctuation via the regex `~r/[^a-z0-9]+/` (dropping empty pieces), then remove stop words. Indexing the same `id` again must replace the previous version cleanly — terms only in the old version must disappear from search results and from the vocabulary, and the document count must not grow. There is no stemming. Return `:ok`.

- `InvertedIndex.remove(server, id)` which removes a document from the index entirely. After removal it must not appear in results and must not contribute to the document count used for IDF; any term that occurred only in that document must also vanish from the vocabulary, so it is no longer counted by `stats/1` and no longer offered by `suggest/3`. Return `:ok`. Removing a non-existent id must not raise and must still return `:ok`.

- `InvertedIndex.search(server, query, opts \\ [])` which tokenizes the query using the same pipeline as indexing, finds all documents containing at least one query term, and returns them ranked by BM25 score descending. For a document `d` and the set of unique query terms (a term repeated in the query contributes exactly once):

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

  Field boosts are passed via `opts[:boosts]` as a map like `%{title: 3, body: 1}`; fields not listed default to boost `1` (so with no boosts every field has weight 1, `f(t,d)` is the plain total count, and `|d|` is the plain total token count). Return a list of `%{id: id, score: score}` maps sorted by score descending. Support `opts[:limit]` to cap the number of results; with no `:limit`, return every matching document. Searching an empty index, or a query whose terms are all stop words or absent from the vocabulary, returns `[]`.

- `InvertedIndex.suggest(server, prefix, limit \\ 10)` which returns term completions from the index vocabulary. The prefix is lowercased before lookup. Return up to `limit` terms that start with the prefix, sorted by document frequency descending; a prefix matching nothing returns `[]`. Return a list of strings.

- `InvertedIndex.stats(server)` which returns `%{document_count: integer, term_count: integer}` — the total indexed documents and the total unique terms in the vocabulary. On a fresh process this is `%{document_count: 0, term_count: 0}`.

Additional requirements:
- Implement this as a GenServer. Use no external dependencies — only standard library and OTP.
- All term storage and lookup must be case-insensitive, so mixed-case occurrences of the same word collapse into a single vocabulary term.
- The module must be in a single file called `inverted_index.ex`.

## The module with `stats` missing

```elixir
defmodule InvertedIndex do
  @moduledoc """
  A single-process, in-memory full-text search engine backed by an inverted
  index and ranked with the Okapi BM25 scoring function.

  The engine supports:

    * tokenization with lowercasing, punctuation splitting and stop-word removal,
    * BM25 ranking with term-frequency saturation (`k1`) and document-length
      normalization (`b`),
    * query-time, field-level boosting so that matches in important fields
      (such as `:title`) can outweigh matches elsewhere,
    * prefix suggestion over the indexed vocabulary, ordered by document
      frequency.

  All storage and lookup are case-insensitive. There is no stemming.

  Documents are stored per field as term-frequency maps together with per-field
  token counts, which lets boosts be applied at query time without re-indexing.
  """

  use GenServer

  @token_regex ~r/[^a-z0-9]+/

  @default_stop_words MapSet.new([
                        "the",
                        "a",
                        "an",
                        "is",
                        "are",
                        "was",
                        "were",
                        "in",
                        "on",
                        "at",
                        "to",
                        "of",
                        "and",
                        "or",
                        "it",
                        "this",
                        "that",
                        "for",
                        "with",
                        "as",
                        "by",
                        "not",
                        "be",
                        "has",
                        "had",
                        "have",
                        "do",
                        "does",
                        "did",
                        "but",
                        "if",
                        "from"
                      ])

  @type document :: %{
          terms: %{optional(any()) => %{optional(String.t()) => non_neg_integer()}},
          lengths: %{optional(any()) => non_neg_integer()}
        }

  # ── Public API ──────────────────────────────────────────────────────────

  @doc """
  Starts the inverted-index process.

  Options:

    * `:name` — optional process registration name.
    * `:stop_words` — a `MapSet` of words to exclude during tokenization;
      defaults to a built-in English stop-word set.
    * `:k1` — BM25 term-frequency saturation parameter (default `1.2`).
    * `:b` — BM25 length-normalization parameter (default `0.75`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Indexes `id` with the given `fields` map (`field_name => text`).

  Re-indexing an existing `id` cleanly replaces the previous version.
  Returns `:ok`.
  """
  @spec index(GenServer.server(), String.t(), %{optional(any()) => String.t()}) :: :ok
  def index(server, id, fields) do
    GenServer.call(server, {:index, id, fields})
  end

  @doc """
  Removes the document `id` from the index entirely.

  Removing a non-existent `id` is a no-op. Returns `:ok`.
  """
  @spec remove(GenServer.server(), String.t()) :: :ok
  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end

  @doc """
  Searches the index for `query`, returning documents ranked by BM25 score
  in descending order.

  Options:

    * `:boosts` — a map of `field_name => boost`; unlisted fields default to
      boost `1`.
    * `:limit` — maximum number of results to return.

  Returns a list of `%{id: String.t(), score: float()}` maps.
  """
  @spec search(GenServer.server(), String.t(), keyword()) ::
          [%{id: String.t(), score: float()}]
  def search(server, query, opts \\ []) do
    GenServer.call(server, {:search, query, opts})
  end

  @doc """
  Returns up to `limit` vocabulary terms that start with `prefix`
  (case-insensitive), ordered by document frequency descending.
  """
  @spec suggest(GenServer.server(), String.t(), pos_integer()) :: [String.t()]
  def suggest(server, prefix, limit \\ 10) do
    GenServer.call(server, {:suggest, prefix, limit})
  end

  def stats(server) do
    # TODO
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    state = %{
      stop_words: Keyword.get(opts, :stop_words, @default_stop_words),
      k1: Keyword.get(opts, :k1, 1.2),
      b: Keyword.get(opts, :b, 0.75),
      docs: %{},
      postings: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:index, id, fields}, _from, state) do
    state = do_remove(state, id)
    {terms, lengths} = build_document(fields, state.stop_words)
    doc = %{terms: terms, lengths: lengths}
    postings = add_postings(state.postings, id, terms)
    {:reply, :ok, %{state | docs: Map.put(state.docs, id, doc), postings: postings}}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, do_remove(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    boosts = Keyword.get(opts, :boosts, %{})
    limit = Keyword.get(opts, :limit)
    query_terms = query |> tokenize(state.stop_words) |> Enum.uniq()
    results = do_search(state, query_terms, boosts)
    results = if limit, do: Enum.take(results, limit), else: results
    {:reply, results, state}
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    prefix = String.downcase(prefix)

    terms =
      state.postings
      |> Enum.filter(fn {term, _ids} -> String.starts_with?(term, prefix) end)
      |> Enum.sort_by(fn {_term, ids} -> MapSet.size(ids) end, :desc)
      |> Enum.take(limit)
      |> Enum.map(fn {term, _ids} -> term end)

    {:reply, terms, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      document_count: map_size(state.docs),
      term_count: map_size(state.postings)
    }

    {:reply, stats, state}
  end

  # ── Indexing helpers ────────────────────────────────────────────────────

  @spec build_document(map(), MapSet.t()) :: {map(), map()}
  defp build_document(fields, stop_words) do
    Enum.reduce(fields, {%{}, %{}}, fn {field, text}, {terms_acc, lengths_acc} ->
      tokens = tokenize(text, stop_words)

      {Map.put(terms_acc, field, count_tokens(tokens)),
       Map.put(lengths_acc, field, length(tokens))}
    end)
  end

  @spec count_tokens([String.t()]) :: %{optional(String.t()) => pos_integer()}
  defp count_tokens(tokens) do
    Enum.reduce(tokens, %{}, fn token, acc ->
      Map.update(acc, token, 1, &(&1 + 1))
    end)
  end

  @spec tokenize(String.t(), MapSet.t()) :: [String.t()]
  defp tokenize(text, stop_words) do
    text
    |> String.downcase()
    |> then(&Regex.split(@token_regex, &1, trim: true))
    |> Enum.reject(&MapSet.member?(stop_words, &1))
  end

  @spec doc_terms(map()) :: MapSet.t()
  defp doc_terms(terms) do
    terms
    |> Map.values()
    |> Enum.reduce(MapSet.new(), fn tmap, acc ->
      MapSet.union(acc, MapSet.new(Map.keys(tmap)))
    end)
  end

  @spec add_postings(map(), String.t(), map()) :: map()
  defp add_postings(postings, id, terms) do
    Enum.reduce(doc_terms(terms), postings, fn t, acc ->
      Map.update(acc, t, MapSet.new([id]), &MapSet.put(&1, id))
    end)
  end

  @spec do_remove(map(), String.t()) :: map()
  defp do_remove(state, id) do
    case Map.get(state.docs, id) do
      nil ->
        state

      doc ->
        postings = remove_postings(state.postings, id, doc.terms)
        %{state | docs: Map.delete(state.docs, id), postings: postings}
    end
  end

  @spec remove_postings(map(), String.t(), map()) :: map()
  defp remove_postings(postings, id, terms) do
    Enum.reduce(doc_terms(terms), postings, fn t, acc ->
      case Map.get(acc, t) do
        nil ->
          acc

        ids ->
          ids = MapSet.delete(ids, id)
          if MapSet.size(ids) == 0, do: Map.delete(acc, t), else: Map.put(acc, t, ids)
      end
    end)
  end

  # ── Search / scoring helpers ────────────────────────────────────────────

  @spec do_search(map(), [String.t()], map()) :: [%{id: String.t(), score: float()}]
  defp do_search(_state, [], _boosts), do: []

  defp do_search(state, query_terms, boosts) do
    n = map_size(state.docs)
    avgdl = average_length(state.docs, n, boosts)

    query_terms
    |> candidates(state.postings)
    |> Enum.map(fn id ->
      doc = Map.fetch!(state.docs, id)

      score =
        score_doc(doc, query_terms, state.postings, n, avgdl, state.k1, state.b, boosts)

      %{id: id, score: score}
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @spec candidates([String.t()], map()) :: MapSet.t()
  defp candidates(query_terms, postings) do
    Enum.reduce(query_terms, MapSet.new(), fn t, acc ->
      case Map.get(postings, t) do
        nil -> acc
        ids -> MapSet.union(acc, ids)
      end
    end)
  end

  @spec score_doc(
          document(),
          [String.t()],
          map(),
          non_neg_integer(),
          float(),
          number(),
          number(),
          map()
        ) :: float()
  defp score_doc(doc, query_terms, postings, n, avgdl, k1, b, boosts) do
    wlen = weighted_length(doc, boosts)
    ratio = if avgdl == +0.0, do: +0.0, else: wlen / avgdl

    Enum.reduce(query_terms, +0.0, fn t, acc ->
      f = term_frequency(doc, t, boosts)

      if f == +0.0 do
        acc
      else
        df = postings |> Map.get(t, MapSet.new()) |> MapSet.size()
        idf = :math.log(1 + (n - df + 0.5) / (df + 0.5))
        denom = f + k1 * (1 - b + b * ratio)
        acc + idf * (f * (k1 + 1)) / denom
      end
    end)
  end

  @spec term_frequency(document(), String.t(), map()) :: float()
  defp term_frequency(doc, term, boosts) do
    Enum.reduce(doc.terms, +0.0, fn {field, tmap}, acc ->
      acc + Map.get(tmap, term, 0) * boost(field, boosts)
    end)
  end

  @spec weighted_length(document(), map()) :: float()
  defp weighted_length(doc, boosts) do
    Enum.reduce(doc.lengths, +0.0, fn {field, len}, acc ->
      acc + len * boost(field, boosts)
    end)
  end

  @spec average_length(map(), non_neg_integer(), map()) :: float()
  defp average_length(_docs, 0, _boosts), do: +0.0

  defp average_length(docs, n, boosts) do
    total =
      Enum.reduce(docs, +0.0, fn {_id, doc}, acc ->
        acc + weighted_length(doc, boosts)
      end)

    total / n
  end

  @spec boost(any(), map()) :: number()
  defp boost(field, boosts), do: Map.get(boosts, field, 1)
end
```

Reply with `stats` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
