# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`build_document/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `build_document/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `build_document/2` missing

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

  @doc """
  Returns index statistics as
  `%{document_count: integer(), term_count: integer()}`.
  """
  @spec stats(GenServer.server()) :: %{document_count: integer(), term_count: integer()}
  def stats(server) do
    GenServer.call(server, :stats)
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

  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
