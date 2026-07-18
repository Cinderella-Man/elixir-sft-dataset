# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule InvertedIndexTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = InvertedIndex.start_link([])
    %{idx: pid}
  end

  # -------------------------------------------------------
  # Basic indexing and search
  # -------------------------------------------------------

  test "indexes documents and finds them by keyword", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the quick brown fox jumps over the lazy dog"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown cat sits on the mat"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "a slow green turtle crosses the road"})

    results = InvertedIndex.search(idx, "fox")
    assert length(results) == 1
    assert hd(results).id == "doc1"
  end

  test "multi-term search returns all matching documents", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown cat"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "a slow green turtle"})

    ids = InvertedIndex.search(idx, "quick brown") |> Enum.map(& &1.id)
    assert length(ids) == 2
    assert "doc1" in ids
    assert "doc2" in ids
  end

  # -------------------------------------------------------
  # Stats
  # -------------------------------------------------------

  test "stats reflects document and term counts", %{idx: idx} do
    assert %{document_count: 0, term_count: 0} = InvertedIndex.stats(idx)

    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    assert InvertedIndex.stats(idx).document_count == 1
    assert InvertedIndex.stats(idx).term_count == 3

    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma delta"})
    assert InvertedIndex.stats(idx).document_count == 2
    assert InvertedIndex.stats(idx).term_count == 4
  end

  # -------------------------------------------------------
  # Exact BM25 value with default parameters
  # -------------------------------------------------------

  test "exact BM25 score with default k1 and b", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox cat"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "dog bird"})

    # N=2, df(fox)=1 -> IDF = ln(1 + 1.5/1.5) = ln 2
    # f=2, |d|=3, avgdl=2.5, k1=1.2, b=0.75
    # denom = 2 + 1.2*(1 - 0.75 + 0.75*3/2.5) = 3.38 ; numer = 2*2.2 = 4.4
    # score = ln 2 * 4.4/3.38
    [result] = InvertedIndex.search(idx, "fox")
    assert result.id == "doc1"
    expected = :math.log(2) * 4.4 / 3.38
    assert_in_delta result.score, expected, 1.0e-9
  end

  test "custom k1 and b change the score as specified", _ctx do
    {:ok, idx} = InvertedIndex.start_link(k1: 2.0, b: 0.0)
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox cat"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "dog bird"})

    # b=0 removes length normalization: denom = f + k1 = 2 + 2 = 4 ; numer = f*(k1+1) = 6
    # IDF = ln 2 ; score = ln 2 * 6/4 = ln 2 * 1.5
    [result] = InvertedIndex.search(idx, "fox")
    assert_in_delta result.score, :math.log(2) * 1.5, 1.0e-9
  end

  # -------------------------------------------------------
  # BM25 term-frequency saturation
  # -------------------------------------------------------

  test "term frequency saturates rather than scaling linearly", %{idx: idx} do
    # both docs have length 4, so length normalization is identical
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox fox fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "fox cat dog bird"})

    results = InvertedIndex.search(idx, "fox")
    d1 = Enum.find(results, &(&1.id == "doc1"))
    d2 = Enum.find(results, &(&1.id == "doc2"))

    # 4x the raw term frequency must NOT give ~4x the score (saturation)
    assert d1.score > d2.score
    assert d1.score < 2 * d2.score
  end

  # -------------------------------------------------------
  # Length normalization
  # -------------------------------------------------------

  test "shorter document with equal term frequency ranks higher", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "long", %{body: "fox padding padding padding"})
    :ok = InvertedIndex.index(idx, "short", %{body: "fox"})

    results = InvertedIndex.search(idx, "fox")
    assert Enum.map(results, & &1.id) == ["short", "long"]
  end

  # -------------------------------------------------------
  # IDF weighting
  # -------------------------------------------------------

  test "rare terms outscore common terms", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "data data data analysis"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "data analysis report summary"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "report summary overview"})

    [rare] = InvertedIndex.search(idx, "overview")
    common = InvertedIndex.search(idx, "data") |> List.last()

    assert rare.score > common.score
  end

  # -------------------------------------------------------
  # Stop words
  # -------------------------------------------------------

  test "stop words are not searchable", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the cat is on the mat"})

    assert InvertedIndex.search(idx, "the") == []
    assert InvertedIndex.search(idx, "is") == []
    assert length(InvertedIndex.search(idx, "cat")) == 1
  end

  test "custom stop words override the defaults", _ctx do
    {:ok, idx} = InvertedIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = InvertedIndex.index(idx, "doc1", %{body: "foo baz bar qux"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown"})

    assert InvertedIndex.search(idx, "foo") == []
    assert InvertedIndex.search(idx, "bar") == []
    assert length(InvertedIndex.search(idx, "the")) == 1
  end

  # -------------------------------------------------------
  # Field boosting
  # -------------------------------------------------------

  test "title boost makes a title match rank higher", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "lazy"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "lazy", body: "fox"})

    results = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]
    assert hd(results).score > List.last(results).score
  end

  test "boosting a field raises the score for the same document", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "animal"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "animals", body: "clever"})

    boosted = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    unboosted = InvertedIndex.search(idx, "fox")

    b = Enum.find(boosted, &(&1.id == "doc1")).score
    u = Enum.find(unboosted, &(&1.id == "doc1")).score
    assert b > u
  end

  # -------------------------------------------------------
  # Limit
  # -------------------------------------------------------

  test "limit caps the number of returned results", %{idx: idx} do
    for i <- 1..20 do
      :ok = InvertedIndex.index(idx, "doc#{i}", %{body: "keyword variation#{i} extra text"})
    end

    assert length(InvertedIndex.search(idx, "keyword", limit: 5)) == 5
    assert length(InvertedIndex.search(idx, "keyword")) == 20
  end

  # -------------------------------------------------------
  # Removal and re-indexing
  # -------------------------------------------------------

  test "removed document no longer appears and stops contributing to counts", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma delta"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "gamma delta epsilon"})

    assert InvertedIndex.stats(idx).document_count == 3
    :ok = InvertedIndex.remove(idx, "doc2")
    assert InvertedIndex.stats(idx).document_count == 2

    beta = InvertedIndex.search(idx, "beta")
    assert length(beta) == 1
    assert hd(beta).id == "doc1"
  end

  test "removing non-existent doc does not raise", %{idx: idx} do
    assert :ok = InvertedIndex.remove(idx, "nonexistent")
  end

  test "re-indexing replaces previous content", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "apple banana cherry"})
    assert length(InvertedIndex.search(idx, "apple")) == 1

    :ok = InvertedIndex.index(idx, "doc1", %{body: "delta epsilon zeta"})
    assert InvertedIndex.search(idx, "apple") == []
    assert hd(InvertedIndex.search(idx, "delta")).id == "doc1"
    assert InvertedIndex.stats(idx).document_count == 1
  end

  # -------------------------------------------------------
  # Suggestion
  # -------------------------------------------------------

  test "suggest returns prefix matches sorted by document frequency", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "program productivity projects"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "testing productivity"})

    suggestions = InvertedIndex.suggest(idx, "pro")
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pro"))
    top_two = Enum.take(suggestions, 2)
    assert "program" in top_two
    assert "productivity" in top_two
  end

  test "suggest respects limit, is case-insensitive, and defaults to 10", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "program productivity projects"})
    assert length(InvertedIndex.suggest(idx, "pro", 2)) == 2
    assert length(InvertedIndex.suggest(idx, "PRO")) > 0

    words = Enum.map_join(1..12, " ", fn i -> "pre#{i}" end)
    :ok = InvertedIndex.index(idx, "doc3", %{body: words})
    assert length(InvertedIndex.suggest(idx, "pre")) == 10
  end

  test "suggest returns empty list for non-matching prefix", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    assert InvertedIndex.suggest(idx, "xyz") == []
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "search on empty index returns empty list", %{idx: idx} do
    assert InvertedIndex.search(idx, "anything") == []
  end

  test "punctuation is stripped during tokenization", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "Hello, world! This is a test."})
    assert length(InvertedIndex.search(idx, "hello")) == 1
    assert length(InvertedIndex.search(idx, "world")) == 1
  end

  test "accepts :name option for registration" do
    {:ok, _pid} = InvertedIndex.start_link(name: :bm25_index)
    :ok = InvertedIndex.index(:bm25_index, "doc1", %{body: "hello world"})
    assert length(InvertedIndex.search(:bm25_index, "hello")) == 1
  end

  test "exact BM25 score when boosts weight both f(t,d) and avgdl", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "fox cat"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "dog", body: "bird"})

    # boosts %{title: 3}: |d1| = 1*3 + 2*1 = 5, |d2| = 1*3 + 1*1 = 4, avgdl = 4.5
    # f(fox,doc1) = 1*3 + 1*1 = 4 ; N=2, df(fox)=1 -> IDF = ln(1 + 1.5/1.5) = ln 2
    [result] = InvertedIndex.search(idx, "fox", boosts: %{title: 3})
    assert result.id == "doc1"

    ratio = 5.0 / 4.5
    denom = 4.0 + 1.2 * (1 - 0.75 + 0.75 * ratio)
    expected = :math.log(2) * (4.0 * 2.2) / denom
    assert_in_delta result.score, expected, 1.0e-9
  end

  test "removal lowers N so the IDF of a surviving term changes exactly", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "cat"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "dog"})

    [before] = InvertedIndex.search(idx, "fox")
    assert_in_delta before.score, :math.log(1 + 2.5 / 1.5) * 2.2 / 2.2, 1.0e-9

    :ok = InvertedIndex.remove(idx, "doc3")

    # N=2, df(fox)=1 -> IDF = ln 2 ; |d|=1, avgdl=1 -> denom = 1 + 1.2 = 2.2, numer = 2.2
    [result] = InvertedIndex.search(idx, "fox")
    assert result.id == "doc1"
    assert_in_delta result.score, :math.log(2), 1.0e-9
  end

  test "repeated query terms are scored once, not once per occurrence", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox fox cat"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "dog bird"})

    [single] = InvertedIndex.search(idx, "fox")
    [repeated] = InvertedIndex.search(idx, "fox fox fox")

    assert repeated.id == single.id
    assert_in_delta repeated.score, single.score, 1.0e-9
  end

  test "field omitted from the boosts map is weighted exactly one", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "cat", body: "fox"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "fox", body: "cat"})

    partial = InvertedIndex.search(idx, "fox", boosts: %{title: 3})
    explicit = InvertedIndex.search(idx, "fox", boosts: %{title: 3, body: 1})

    assert Enum.map(partial, & &1.id) == ["doc2", "doc1"]
    assert Enum.map(partial, & &1.id) == Enum.map(explicit, & &1.id)

    for {p, e} <- Enum.zip(partial, explicit) do
      assert_in_delta p.score, e.score, 1.0e-9
    end
  end

  test "mixed-case occurrences collapse into one term for scoring", %{idx: idx} do
    # TODO
  end

  test "removal purges the removed document's exclusive terms from the vocabulary", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma"})
    assert InvertedIndex.stats(idx).term_count == 3

    :ok = InvertedIndex.remove(idx, "doc1")

    assert InvertedIndex.stats(idx).term_count == 2
    assert InvertedIndex.suggest(idx, "alpha") == []
    assert InvertedIndex.search(idx, "alpha") == []
    assert Enum.map(InvertedIndex.search(idx, "beta"), & &1.id) == ["doc2"]
  end
end
```
