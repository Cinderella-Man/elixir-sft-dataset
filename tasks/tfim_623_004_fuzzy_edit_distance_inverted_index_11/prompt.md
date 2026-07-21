# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule FuzzyIndex do
  @moduledoc """
  `FuzzyIndex` is a small, self-contained full-text search engine implemented as a
  `GenServer`.

  Its distinguishing feature is **approximate (typo-tolerant) matching** based on the
  Levenshtein edit distance. A query term matches a document when the document contains
  a vocabulary term that is *close enough* (within a configurable maximum edit distance)
  to the query term. Results are ranked both by how close the matches are and by how
  often the matching terms occur in each document.

  The engine uses only the Elixir standard library and OTP. All storage and lookup is
  case-insensitive.

  ## Tokenization

  Text is tokenized by lowercasing it, splitting on runs of non-alphanumeric characters
  (via `~r/[^a-z0-9]+/`, dropping empty tokens), and removing stop words. A default
  stop-word set is provided and can be replaced entirely via the `:stop_words` option.

  ## Scoring

  For each unique query term `q`, a vocabulary term `t` is a match when
  `edit_distance(q, t) <= max_distance`, with similarity `max_distance + 1 -
  edit_distance(q, t)`. A document's contribution for `q` is the maximum, over every
  matching term present in that document, of `similarity * occurrences`. A document's
  score is the sum of its contributions across all unique query terms.
  """

  use GenServer

  defstruct docs: %{}, index: %{}, stop_words: nil

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

  ## Public API

  @doc """
  Start a `FuzzyIndex` process.

  Options:

    * `:name` — register the process under the given name.
    * `:stop_words` — a `MapSet` of words to exclude during tokenization. When omitted,
      the built-in default stop-word set is used.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Index the document `id` with the given `text`.

  The text is tokenized and, per document, the number of occurrences of each surviving
  token is stored. Re-indexing an existing `id` cleanly replaces its previous version.
  """
  @spec index(GenServer.server(), String.t(), String.t()) :: :ok
  def index(server, id, text) do
    GenServer.call(server, {:index, id, text})
  end

  @doc """
  Remove the document `id` entirely.

  After removal the document no longer appears in search results, the document count
  decreases, and any vocabulary term that no longer appears in any document is dropped.
  Removing an unknown `id` is a no-op that returns `:ok`.
  """
  @spec remove(GenServer.server(), String.t()) :: :ok
  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end

  @doc """
  Search the index for `query`, returning ranked results.

  Options:

    * `:max_distance` — maximum edit distance for a fuzzy match (default `1`).
    * `:limit` — cap the number of returned results (applied after sorting).

  Returns a list of `%{id: id, score: score}` maps for every document whose score is
  greater than `0`, sorted by score descending. Returns `[]` when the index is empty or
  the query has no surviving tokens.
  """
  @spec search(GenServer.server(), String.t(), keyword()) ::
          [%{id: String.t(), score: number()}]
  def search(server, query, opts \\ []) do
    GenServer.call(server, {:search, query, opts})
  end

  @doc """
  Return the vocabulary terms within `max_distance` edit distance of `term`.

  `term` is lowercased before comparison and is not split. Results are sorted by edit
  distance ascending, breaking ties alphabetically ascending. `max_distance` defaults
  to `1`.
  """
  @spec terms_like(GenServer.server(), String.t(), non_neg_integer()) :: [String.t()]
  def terms_like(server, term, max_distance \\ 1) do
    GenServer.call(server, {:terms_like, term, max_distance})
  end

  @doc """
  Return index statistics as `%{document_count: integer, term_count: integer}`.
  """
  @spec stats(GenServer.server()) ::
          %{document_count: non_neg_integer(), term_count: non_neg_integer()}
  def stats(server) do
    GenServer.call(server, :stats)
  end

  ## GenServer callbacks

  @impl GenServer
  def init(opts) do
    stop_words = Keyword.get(opts, :stop_words, @default_stop_words)
    {:ok, %__MODULE__{stop_words: stop_words}}
  end

  @impl GenServer
  def handle_call({:index, id, text}, _from, state) do
    state = remove_doc(state, id)
    counts = text |> tokenize(state.stop_words) |> token_counts()

    index =
      Enum.reduce(counts, state.index, fn {term, count}, idx ->
        Map.update(idx, term, %{id => count}, fn postings ->
          Map.put(postings, id, count)
        end)
      end)

    new_state = %{state | docs: Map.put(state.docs, id, counts), index: index}
    {:reply, :ok, new_state}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, remove_doc(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    max_distance = Keyword.get(opts, :max_distance, 1)
    limit = Keyword.get(opts, :limit)
    {:reply, do_search(state, query, max_distance, limit), state}
  end

  def handle_call({:terms_like, term, max_distance}, _from, state) do
    lowered = String.downcase(term)

    result =
      state.index
      |> Map.keys()
      |> Enum.map(fn t -> {t, edit_distance(lowered, t)} end)
      |> Enum.filter(fn {_t, d} -> d <= max_distance end)
      |> Enum.sort_by(fn {t, d} -> {d, t} end)
      |> Enum.map(fn {t, _d} -> t end)

    {:reply, result, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{document_count: map_size(state.docs), term_count: map_size(state.index)}
    {:reply, stats, state}
  end

  ## Internal helpers

  @spec remove_doc(%__MODULE__{}, String.t()) :: %__MODULE__{}
  defp remove_doc(state, id) do
    case Map.fetch(state.docs, id) do
      :error ->
        state

      {:ok, counts} ->
        index =
          Enum.reduce(counts, state.index, fn {term, _count}, idx ->
            case Map.fetch(idx, term) do
              :error ->
                idx

              {:ok, postings} ->
                pruned = Map.delete(postings, id)

                if map_size(pruned) == 0 do
                  Map.delete(idx, term)
                else
                  Map.put(idx, term, pruned)
                end
            end
          end)

        %{state | docs: Map.delete(state.docs, id), index: index}
    end
  end

  @spec do_search(%__MODULE__{}, String.t(), non_neg_integer(), non_neg_integer() | nil) ::
          [%{id: String.t(), score: number()}]
  defp do_search(state, query, max_distance, limit) do
    terms = query |> tokenize(state.stop_words) |> Enum.uniq()

    cond do
      map_size(state.docs) == 0 ->
        []

      terms == [] ->
        []

      true ->
        vocab = Map.keys(state.index)

        scores =
          Enum.reduce(terms, %{}, fn q, acc ->
            contributions = contributions_for(q, vocab, state.index, max_distance)
            Map.merge(acc, contributions, fn _id, s1, s2 -> s1 + s2 end)
          end)

        scores
        |> Enum.filter(fn {_id, score} -> score > 0 end)
        |> Enum.map(fn {id, score} -> %{id: id, score: score} end)
        |> Enum.sort_by(fn %{score: score} -> score end, :desc)
        |> apply_limit(limit)
    end
  end

  @spec contributions_for(String.t(), [String.t()], map(), non_neg_integer()) ::
          %{optional(String.t()) => number()}
  defp contributions_for(q, vocab, index, max_distance) do
    matches =
      vocab
      |> Enum.map(fn t -> {t, edit_distance(q, t)} end)
      |> Enum.filter(fn {_t, d} -> d <= max_distance end)
      |> Enum.map(fn {t, d} -> {t, max_distance + 1 - d} end)

    Enum.reduce(matches, %{}, fn {t, similarity}, acc ->
      postings = Map.get(index, t, %{})

      Enum.reduce(postings, acc, fn {id, count}, inner ->
        value = similarity * count
        Map.update(inner, id, value, fn existing -> max(existing, value) end)
      end)
    end)
  end

  @spec apply_limit([map()], non_neg_integer() | nil) :: [map()]
  defp apply_limit(results, nil), do: results
  defp apply_limit(results, limit) when is_integer(limit), do: Enum.take(results, limit)

  @spec tokenize(String.t(), MapSet.t()) :: [String.t()]
  defp tokenize(text, stop_words) do
    text
    |> String.downcase()
    |> then(fn lowered -> Regex.split(~r/[^a-z0-9]+/, lowered, trim: true) end)
    |> Enum.reject(fn token -> MapSet.member?(stop_words, token) end)
  end

  @spec token_counts([String.t()]) :: %{optional(String.t()) => pos_integer()}
  defp token_counts(tokens) do
    Enum.reduce(tokens, %{}, fn token, acc ->
      Map.update(acc, token, 1, &(&1 + 1))
    end)
  end

  @spec edit_distance(String.t(), String.t()) :: non_neg_integer()
  defp edit_distance(a, b) do
    ca = String.to_charlist(a)
    cb = String.to_charlist(b)
    initial = Enum.to_list(0..length(cb))

    ca
    |> Enum.with_index(1)
    |> Enum.reduce(initial, fn {char_a, i}, prev_row ->
      compute_row(char_a, cb, prev_row, i)
    end)
    |> List.last()
  end

  @spec compute_row(char(), charlist(), [non_neg_integer()], pos_integer()) ::
          [non_neg_integer()]
  defp compute_row(char_a, cb, prev_row, i) do
    pairs = Enum.zip([cb, prev_row, tl(prev_row)])

    {reversed, _left} =
      Enum.reduce(pairs, {[i], i}, fn {char_b, diag, above}, {acc, left} ->
        cost = if char_a == char_b, do: 0, else: 1
        value = Enum.min([above + 1, left + 1, diag + cost])
        {[value | acc], value}
      end)

    Enum.reverse(reversed)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule FuzzyIndexTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = FuzzyIndex.start_link([])
    %{idx: pid}
  end

  # -------------------------------------------------------
  # Exact keyword search
  # -------------------------------------------------------

  test "indexes documents and finds them by exact keyword", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "the quick brown fox")
    :ok = FuzzyIndex.index(idx, "doc2", "the lazy dog")

    results = FuzzyIndex.search(idx, "fox")
    assert length(results) == 1
    assert hd(results).id == "doc1"
  end

  # -------------------------------------------------------
  # Fuzzy matching within the default distance
  # -------------------------------------------------------

  test "a typo within edit distance 1 still matches by default", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "quick brown fox")
    :ok = FuzzyIndex.index(idx, "doc2", "slow green turtle")

    # "quik" is edit distance 1 from "quick" and far from every other term
    results = FuzzyIndex.search(idx, "quik")
    assert Enum.map(results, & &1.id) == ["doc1"]
  end

  test "max_distance option widens or narrows fuzzy matching", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "banana")

    # "banan" is distance 1 from "banana" → matches by default
    assert Enum.map(FuzzyIndex.search(idx, "banan"), & &1.id) == ["doc1"]

    # "bana" is distance 2 from "banana" → no match at the default max_distance of 1
    assert FuzzyIndex.search(idx, "bana") == []

    # ... but matches when max_distance is raised to 2
    assert Enum.map(FuzzyIndex.search(idx, "bana", max_distance: 2), & &1.id) == ["doc1"]
  end

  # -------------------------------------------------------
  # Scoring: exact beats fuzzy, frequency matters
  # -------------------------------------------------------

  test "exact matches outrank near-miss matches", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "color color")
    :ok = FuzzyIndex.index(idx, "doc2", "colour")

    results = FuzzyIndex.search(idx, "color")
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]

    # doc1: exact "color" (similarity 2) occurring twice → 2 * 2 = 4
    # doc2: near "colour" at distance 1 (similarity 1) occurring once → 1 * 1 = 1
    assert Enum.find(results, &(&1.id == "doc1")).score == 4
    assert Enum.find(results, &(&1.id == "doc2")).score == 1
  end

  test "higher term frequency yields a higher score", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "data data data")
    :ok = FuzzyIndex.index(idx, "doc2", "data")

    results = FuzzyIndex.search(idx, "data")
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]
    # doc1: similarity 2 * count 3 = 6 ; doc2: similarity 2 * count 1 = 2
    assert Enum.find(results, &(&1.id == "doc1")).score == 6
    assert Enum.find(results, &(&1.id == "doc2")).score == 2
  end

  test "multiple query terms sum their contributions", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "quick brown fox")

    [result] = FuzzyIndex.search(idx, "quick fox")
    assert result.id == "doc1"
    # each exact term contributes similarity 2 * count 1; 2 + 2 = 4
    assert result.score == 4
  end

  # -------------------------------------------------------
  # Stop words
  # -------------------------------------------------------

  test "stop words are not searchable", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "the cat sat")

    assert FuzzyIndex.search(idx, "the") == []
    assert length(FuzzyIndex.search(idx, "cat")) == 1
  end

  test "custom stop words override the defaults" do
    {:ok, idx} = FuzzyIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = FuzzyIndex.index(idx, "doc1", "foo baz bar qux")
    :ok = FuzzyIndex.index(idx, "doc2", "the quick")

    # "foo" and "bar" are stop words under the custom set
    assert FuzzyIndex.search(idx, "foo") == []
    assert FuzzyIndex.search(idx, "bar") == []

    # "the" is NOT a stop word under the custom set, so it is indexed
    assert length(FuzzyIndex.search(idx, "the")) == 1
  end

  # -------------------------------------------------------
  # Punctuation and tokenization
  # -------------------------------------------------------

  test "punctuation is stripped and produces no empty terms", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "Hello, world!")

    # splitting on ~r/[^a-z0-9]+/ yields exactly ["hello", "world"]
    assert FuzzyIndex.stats(idx).term_count == 2
    assert length(FuzzyIndex.search(idx, "hello")) == 1
    assert length(FuzzyIndex.search(idx, "world")) == 1
  end

  # -------------------------------------------------------
  # Stats
  # -------------------------------------------------------

  test "stats reflects document and vocabulary counts", %{idx: idx} do
    # TODO
  end

  # -------------------------------------------------------
  # terms_like
  # -------------------------------------------------------

  test "terms_like returns vocabulary within distance, sorted by distance then alpha", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "cat cot cats dog")

    # distances from "cat": cat=0, cot=1, cats=1, dog=3 (excluded at max 1)
    # tie at distance 1 broken alphabetically: "cats" < "cot"
    assert FuzzyIndex.terms_like(idx, "cat", 1) == ["cat", "cats", "cot"]
  end

  test "terms_like excludes terms beyond the distance and lowercases its input", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "color")
    :ok = FuzzyIndex.index(idx, "doc2", "colour")
    :ok = FuzzyIndex.index(idx, "doc3", "cold")

    # color=0, colour=1, cold=2 (excluded at max 1); input "COLOR" is lowercased
    assert FuzzyIndex.terms_like(idx, "COLOR", 1) == ["color", "colour"]
  end

  test "terms_like defaults to max distance 1", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "banana")

    assert FuzzyIndex.terms_like(idx, "banan") == ["banana"]
    assert FuzzyIndex.terms_like(idx, "bana") == []
  end

  # -------------------------------------------------------
  # Removal
  # -------------------------------------------------------

  test "removed document no longer appears and vocabulary shrinks", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "alpha beta")
    :ok = FuzzyIndex.index(idx, "doc2", "beta gamma")
    :ok = FuzzyIndex.index(idx, "doc3", "gamma delta")

    assert FuzzyIndex.stats(idx).document_count == 3

    :ok = FuzzyIndex.remove(idx, "doc2")

    assert FuzzyIndex.stats(idx).document_count == 2

    # "beta" now only in doc1, "gamma" now only in doc3
    assert Enum.map(FuzzyIndex.search(idx, "beta"), & &1.id) == ["doc1"]
    assert Enum.map(FuzzyIndex.search(idx, "gamma"), & &1.id) == ["doc3"]

    # vocabulary is alpha, beta, gamma, delta
    assert FuzzyIndex.stats(idx).term_count == 4
  end

  test "removal drops vocabulary terms held only by the removed document", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "alpha beta")
    :ok = FuzzyIndex.index(idx, "doc2", "beta gamma delta")

    # vocabulary is alpha, beta, gamma, delta
    assert FuzzyIndex.stats(idx).term_count == 4

    :ok = FuzzyIndex.remove(idx, "doc2")

    # "gamma" and "delta" appear in no remaining document, so they leave the
    # vocabulary; "beta" survives in doc1
    assert FuzzyIndex.stats(idx).term_count == 2
    assert FuzzyIndex.terms_like(idx, "gamma", 0) == []
    assert FuzzyIndex.terms_like(idx, "delta", 0) == []
    assert FuzzyIndex.terms_like(idx, "beta", 0) == ["beta"]
  end

  test "re-indexing drops vocabulary terms no other document holds", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "alpha beta")
    :ok = FuzzyIndex.index(idx, "doc2", "beta gamma")

    assert FuzzyIndex.stats(idx).term_count == 3

    # doc2's only unique term, "gamma", is replaced by "delta"
    :ok = FuzzyIndex.index(idx, "doc2", "beta delta")

    assert FuzzyIndex.stats(idx).term_count == 3
    assert FuzzyIndex.terms_like(idx, "gamma", 0) == []
    assert FuzzyIndex.terms_like(idx, "delta", 0) == ["delta"]
  end

  test "removing a non-existent document does not raise", %{idx: idx} do
    assert :ok = FuzzyIndex.remove(idx, "nonexistent")
  end

  # -------------------------------------------------------
  # Re-indexing (update)
  # -------------------------------------------------------

  test "re-indexing replaces previous content", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "apple banana")
    assert length(FuzzyIndex.search(idx, "apple")) == 1

    :ok = FuzzyIndex.index(idx, "doc1", "delta epsilon")

    assert FuzzyIndex.search(idx, "apple") == []
    assert Enum.map(FuzzyIndex.search(idx, "delta"), & &1.id) == ["doc1"]
    assert FuzzyIndex.stats(idx).document_count == 1
    assert FuzzyIndex.stats(idx).term_count == 2
  end

  # -------------------------------------------------------
  # Limit
  # -------------------------------------------------------

  test "limit caps the number of returned results", %{idx: idx} do
    for i <- 1..20 do
      :ok = FuzzyIndex.index(idx, "doc#{i}", "keyword variation#{i} extra text")
    end

    assert length(FuzzyIndex.search(idx, "keyword", limit: 5)) == 5
    assert length(FuzzyIndex.search(idx, "keyword")) == 20
  end

  # -------------------------------------------------------
  # Empty index
  # -------------------------------------------------------

  test "search on an empty index returns an empty list", %{idx: idx} do
    assert FuzzyIndex.search(idx, "anything") == []
  end

  # -------------------------------------------------------
  # Named registration
  # -------------------------------------------------------

  test "accepts a :name option for registration" do
    {:ok, _pid} = FuzzyIndex.start_link(name: :fuzzy_index_reg)

    :ok = FuzzyIndex.index(:fuzzy_index_reg, "doc1", "hello world")
    assert length(FuzzyIndex.search(:fuzzy_index_reg, "hello")) == 1
  end

  test "repeated query terms do not multiply a document's score", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "data data")

    [once] = FuzzyIndex.search(idx, "data")
    [thrice] = FuzzyIndex.search(idx, "data data data")

    # exact "data" (similarity 2) occurring twice → 2 * 2 = 4, counted a single time
    assert once.score == 4
    assert thrice.score == 4
  end

  test "contribution takes the max over matching terms rather than summing them", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "color colour")

    [result] = FuzzyIndex.search(idx, "color")

    # exact "color" → 2 * 1 = 2 ; near "colour" → 1 * 1 = 1 ; max is 2, not the sum 3
    assert result.score == 2
  end

  test "limit keeps the highest scoring results, not arbitrary ones", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "low", "keyword")
    :ok = FuzzyIndex.index(idx, "mid", "keyword keyword")
    :ok = FuzzyIndex.index(idx, "high", "keyword keyword keyword")

    assert Enum.map(FuzzyIndex.search(idx, "keyword", limit: 1), & &1.id) == ["high"]
    assert Enum.map(FuzzyIndex.search(idx, "keyword", limit: 2), & &1.id) == ["high", "mid"]
  end

  test "similarity scales with max_distance for exact and maximally distant matches", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "banana")

    # exact match at max_distance 2 → similarity 3, count 1 → score 3
    [exact] = FuzzyIndex.search(idx, "banana", max_distance: 2)
    assert exact.score == 3

    # "bana" is distance 2 from "banana", the maximum allowed → similarity 1 → score 1
    [edge] = FuzzyIndex.search(idx, "bana", max_distance: 2)
    assert edge.score == 1
  end

  test "every documented default stop word is dropped during tokenization", %{idx: idx} do
    text =
      "the a an is are was were in on at to of and or it this that for with as by " <>
        "not be has had have do does did but if from marker"

    :ok = FuzzyIndex.index(idx, "doc1", text)

    assert FuzzyIndex.stats(idx).term_count == 1
    assert FuzzyIndex.terms_like(idx, "marker", 0) == ["marker"]
  end

  test "uppercase text and uppercase queries match each other", %{idx: idx} do
    :ok = FuzzyIndex.index(idx, "doc1", "HELLO World")

    assert Enum.map(FuzzyIndex.search(idx, "HELLO"), & &1.id) == ["doc1"]
    assert Enum.map(FuzzyIndex.search(idx, "WoRlD"), & &1.id) == ["doc1"]
    assert FuzzyIndex.terms_like(idx, "HELLO", 0) == ["hello"]
  end
end
```
