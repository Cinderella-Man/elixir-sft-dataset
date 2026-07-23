# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule InvertedIndex do
  @moduledoc """
  A Boolean full-text search engine backed by a `GenServer`.

  Documents are tokenized field-by-field (lowercase, split on punctuation and
  whitespace, stop words removed) while preserving token order so that phrase
  queries can match on consecutive positions. Queries are Boolean expressions
  built from `{:term, ...}`, `{:phrase, ...}`, `{:and, ...}`, `{:or, ...}` and
  `{:not, ...}` nodes. There is no relevance scoring: a document either
  satisfies a query or it does not.

  Two internal structures are maintained:

    * `documents` — `%{id => %{field => [token]}}`, used for phrase matching and
      for clean removal/replacement of documents.
    * `postings` — `%{term => MapSet.t(id)}`, used for fast term membership,
      document-frequency ranking of suggestions, and vocabulary statistics.
  """

  use GenServer

  @type query ::
          {:term, String.t()}
          | {:phrase, String.t()}
          | {:and, [query]}
          | {:or, [query]}
          | {:not, query}

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

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the index process.

  Options:

    * `:name` — optional process name for registration.
    * `:stop_words` — optional `MapSet` of words to exclude during tokenization.
      Defaults to a built-in English stop-word set.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Indexes `fields` (a map of field name to text) under `id`.

  Re-indexing an existing `id` cleanly replaces its previous version.
  """
  @spec index(GenServer.server(), String.t(), map()) :: :ok
  def index(server, id, fields) do
    GenServer.call(server, {:index, id, fields})
  end

  @doc """
  Removes the document `id` from the index entirely.

  Removing a non-existent `id` is a no-op.
  """
  @spec remove(GenServer.server(), String.t()) :: :ok
  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end

  @doc """
  Evaluates a Boolean `query` and returns the sorted list of matching ids.
  """
  @spec search(GenServer.server(), query()) :: [String.t()]
  def search(server, query) do
    GenServer.call(server, {:search, query})
  end

  @doc """
  Returns up to `limit` vocabulary terms starting with `prefix`.

  Terms are sorted by document frequency descending (ties broken
  alphabetically). The `prefix` is lowercased before lookup.
  """
  @spec suggest(GenServer.server(), String.t(), non_neg_integer()) :: [String.t()]
  def suggest(server, prefix, limit \\ 10) do
    GenServer.call(server, {:suggest, prefix, limit})
  end

  @doc """
  Returns `%{document_count: integer, term_count: integer}` for the index.
  """
  @spec stats(GenServer.server()) :: %{
          document_count: non_neg_integer(),
          term_count: non_neg_integer()
        }
  def stats(server) do
    GenServer.call(server, :stats)
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  def init(opts) do
    stop_words = Keyword.get(opts, :stop_words, @default_stop_words)
    {:ok, %{stop_words: stop_words, documents: %{}, postings: %{}}}
  end

  @impl true
  def handle_call({:index, id, fields}, _from, state) do
    state = do_remove(state, id)

    tokenized =
      fields
      |> Enum.map(fn {field, text} -> {field, tokenize(text, state.stop_words)} end)
      |> Map.new()

    terms = doc_terms(tokenized)

    postings =
      Enum.reduce(terms, state.postings, fn term, acc ->
        Map.update(acc, term, MapSet.new([id]), &MapSet.put(&1, id))
      end)

    documents = Map.put(state.documents, id, tokenized)
    {:reply, :ok, %{state | documents: documents, postings: postings}}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, do_remove(state, id)}
  end

  def handle_call({:search, query}, _from, state) do
    ids = query |> eval(state) |> MapSet.to_list() |> Enum.sort()
    {:reply, ids, state}
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    prefix = String.downcase(prefix)

    terms =
      state.postings
      |> Enum.filter(fn {term, _ids} -> String.starts_with?(term, prefix) end)
      |> Enum.sort_by(fn {term, ids} -> {-MapSet.size(ids), term} end)
      |> Enum.take(limit)
      |> Enum.map(fn {term, _ids} -> term end)

    {:reply, terms, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      document_count: map_size(state.documents),
      term_count: map_size(state.postings)
    }

    {:reply, stats, state}
  end

  # ------------------------------------------------------------------
  # Indexing / removal helpers
  # ------------------------------------------------------------------

  defp do_remove(state, id) do
    case Map.pop(state.documents, id) do
      {nil, _documents} ->
        state

      {tokenized, documents} ->
        terms = doc_terms(tokenized)

        postings =
          Enum.reduce(terms, state.postings, fn term, acc ->
            drop_posting(acc, term, id)
          end)

        %{state | documents: documents, postings: postings}
    end
  end

  defp drop_posting(postings, term, id) do
    case Map.get(postings, term) do
      nil ->
        postings

      set ->
        set = MapSet.delete(set, id)

        if MapSet.size(set) == 0 do
          Map.delete(postings, term)
        else
          Map.put(postings, term, set)
        end
    end
  end

  defp doc_terms(tokenized) do
    tokenized
    |> Enum.flat_map(fn {_field, tokens} -> tokens end)
    |> MapSet.new()
  end

  defp tokenize(text, stop_words) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&MapSet.member?(stop_words, &1))
  end

  # ------------------------------------------------------------------
  # Query evaluation — returns a MapSet of matching ids
  # ------------------------------------------------------------------

  defp eval({:term, word}, state) do
    case tokenize(word, state.stop_words) do
      [] -> MapSet.new()
      [term | _rest] -> Map.get(state.postings, term, MapSet.new())
    end
  end

  defp eval({:phrase, text}, state) do
    case tokenize(text, state.stop_words) do
      [] ->
        MapSet.new()

      [single] ->
        Map.get(state.postings, single, MapSet.new())

      terms ->
        terms
        |> candidate_ids(state)
        |> Enum.filter(fn id -> doc_has_phrase?(Map.get(state.documents, id), terms) end)
        |> MapSet.new()
    end
  end

  defp eval({:and, []}, state), do: all_ids(state)

  defp eval({:and, list}, state) do
    list
    |> Enum.map(&eval(&1, state))
    |> intersect_all()
  end

  defp eval({:or, list}, state) do
    Enum.reduce(list, MapSet.new(), fn q, acc -> MapSet.union(acc, eval(q, state)) end)
  end

  defp eval({:not, expr}, state) do
    MapSet.difference(all_ids(state), eval(expr, state))
  end

  defp candidate_ids(terms, state) do
    terms
    |> Enum.map(&Map.get(state.postings, &1, MapSet.new()))
    |> intersect_all()
  end

  defp doc_has_phrase?(nil, _terms), do: false

  defp doc_has_phrase?(tokenized, terms) do
    Enum.any?(tokenized, fn {_field, tokens} -> contains_sequence?(tokens, terms) end)
  end

  defp contains_sequence?(tokens, terms) do
    len = length(terms)

    tokens
    |> Stream.chunk_every(len, 1, :discard)
    |> Enum.any?(&(&1 == terms))
  end

  defp all_ids(state) do
    state.documents |> Map.keys() |> MapSet.new()
  end

  defp intersect_all([]), do: MapSet.new()

  defp intersect_all([first | rest]) do
    Enum.reduce(rest, first, fn set, acc -> MapSet.intersection(acc, set) end)
  end
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
  # Basic term search
  # -------------------------------------------------------

  test "term query finds documents containing the token", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "a slow green turtle"})

    assert InvertedIndex.search(idx, {:term, "fox"}) == ["a"]
    assert InvertedIndex.search(idx, {:term, "quick"}) == ["a", "b"]
  end

  test "term query is case-insensitive", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "Quick Brown Fox"})
    assert InvertedIndex.search(idx, {:term, "FOX"}) == ["a"]
  end

  test "term query for a stop word matches nothing", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the cat on the mat"})
    assert InvertedIndex.search(idx, {:term, "the"}) == []
    assert InvertedIndex.search(idx, {:term, "cat"}) == ["a"]
  end

  # -------------------------------------------------------
  # Boolean operators
  # -------------------------------------------------------

  test "and returns intersection", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow green turtle"})

    result = InvertedIndex.search(idx, {:and, [{:term, "quick"}, {:term, "brown"}]})
    assert result == ["a", "b"]

    result2 = InvertedIndex.search(idx, {:and, [{:term, "quick"}, {:term, "fox"}]})
    assert result2 == ["a"]
  end

  test "or returns union", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow green turtle"})

    result = InvertedIndex.search(idx, {:or, [{:term, "fox"}, {:term, "turtle"}]})
    assert result == ["a", "c"]
  end

  test "not excludes matching documents", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow green turtle"})

    assert InvertedIndex.search(idx, {:not, {:term, "fox"}}) == ["b", "c"]
  end

  test "empty and matches all, empty or matches none", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "slow turtle"})

    assert InvertedIndex.search(idx, {:and, []}) == ["a", "b"]
    assert InvertedIndex.search(idx, {:or, []}) == []
  end

  test "nested boolean expressions evaluate correctly", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "a slow green turtle"})
    :ok = InvertedIndex.index(idx, "d", %{body: "fox jumps high"})

    # (cat OR fox) AND (NOT quick)  ->  only "d"
    query = {:and, [{:or, [{:term, "cat"}, {:term, "fox"}]}, {:not, {:term, "quick"}}]}
    assert InvertedIndex.search(idx, query) == ["d"]
  end

  # -------------------------------------------------------
  # Result ordering
  # -------------------------------------------------------

  test "results are sorted ascending by id", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "c", %{body: "keyword"})
    :ok = InvertedIndex.index(idx, "a", %{body: "keyword"})
    :ok = InvertedIndex.index(idx, "b", %{body: "keyword"})

    assert InvertedIndex.search(idx, {:term, "keyword"}) == ["a", "b", "c"]
  end

  # -------------------------------------------------------
  # Phrase queries
  # -------------------------------------------------------

  test "phrase matches consecutive terms", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown cat"})

    assert InvertedIndex.search(idx, {:phrase, "quick brown"}) == ["a", "b"]
    assert InvertedIndex.search(idx, {:phrase, "brown fox"}) == ["a"]
  end

  test "phrase does not match non-consecutive terms", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    # "quick" and "fox" both appear but are not adjacent
    assert InvertedIndex.search(idx, {:phrase, "quick fox"}) == []
  end

  test "phrase must lie within a single field", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d", %{title: "quick", body: "brown cat"})

    # "quick" is in title, "brown" is in body -> not a single-field phrase
    assert InvertedIndex.search(idx, {:phrase, "quick brown"}) == []
    # but each term individually is findable in some field
    assert InvertedIndex.search(idx, {:term, "quick"}) == ["d"]
  end

  test "stop words in a phrase are dropped before matching", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    # "the" is a stop word: phrase tokenizes to ["brown", "fox"] which is consecutive
    assert InvertedIndex.search(idx, {:phrase, "brown the fox"}) == ["a"]
  end

  test "single-term phrase behaves like a term query", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{title: "fox", body: "hunting"})
    assert InvertedIndex.search(idx, {:phrase, "fox"}) == ["a"]
  end

  # -------------------------------------------------------
  # Stats
  # -------------------------------------------------------

  test "stats reflects document and term counts", %{idx: idx} do
    # TODO
  end

  # -------------------------------------------------------
  # Custom stop words
  # -------------------------------------------------------

  test "custom stop words override the defaults", _ctx do
    {:ok, idx} = InvertedIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = InvertedIndex.index(idx, "a", %{body: "foo baz bar qux"})
    :ok = InvertedIndex.index(idx, "b", %{body: "the quick brown"})

    assert InvertedIndex.search(idx, {:term, "foo"}) == []
    assert InvertedIndex.search(idx, {:term, "bar"}) == []
    # "the" is NOT a stop word under the custom set
    assert InvertedIndex.search(idx, {:term, "the"}) == ["b"]
  end

  # -------------------------------------------------------
  # Removal and re-indexing
  # -------------------------------------------------------

  test "removed document no longer appears", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow turtle"})

    :ok = InvertedIndex.remove(idx, "b")

    assert InvertedIndex.search(idx, {:term, "quick"}) == ["a"]
    assert InvertedIndex.stats(idx).document_count == 2
  end

  test "removing non-existent doc does not raise", %{idx: idx} do
    assert :ok = InvertedIndex.remove(idx, "nonexistent")
  end

  test "re-indexing replaces previous content", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "apple banana cherry"})
    assert InvertedIndex.search(idx, {:term, "apple"}) == ["a"]

    :ok = InvertedIndex.index(idx, "a", %{body: "delta epsilon zeta"})
    assert InvertedIndex.search(idx, {:term, "apple"}) == []
    assert InvertedIndex.search(idx, {:term, "delta"}) == ["a"]
    assert InvertedIndex.stats(idx).document_count == 1
  end

  # -------------------------------------------------------
  # Prefix suggestion
  # -------------------------------------------------------

  test "suggest returns prefix matches sorted by document frequency", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "d2", %{body: "program productivity projects"})
    :ok = InvertedIndex.index(idx, "d3", %{body: "testing productivity"})

    suggestions = InvertedIndex.suggest(idx, "pro")
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pro"))

    # "program" (2 docs) and "productivity" (2 docs) rank above the 1-doc terms
    top_two = Enum.take(suggestions, 2)
    assert "program" in top_two
    assert "productivity" in top_two
  end

  test "suggest respects limit and is case-insensitive", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "d2", %{body: "program productivity projects"})

    assert length(InvertedIndex.suggest(idx, "pro", 2)) == 2
    assert length(InvertedIndex.suggest(idx, "PRO")) > 0
  end

  test "suggest without a limit returns at most 10 terms", %{idx: idx} do
    words = Enum.map_join(1..12, " ", fn i -> "pre#{i}" end)
    :ok = InvertedIndex.index(idx, "d1", %{body: words})

    suggestions = InvertedIndex.suggest(idx, "pre")
    assert length(suggestions) == 10
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pre"))
  end

  test "suggest returns empty list for non-matching prefix", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "d1", %{body: "alpha beta gamma"})
    assert InvertedIndex.suggest(idx, "xyz") == []
  end

  # -------------------------------------------------------
  # Edge cases and tokenization
  # -------------------------------------------------------

  test "search on empty index returns empty list", %{idx: idx} do
    assert InvertedIndex.search(idx, {:term, "anything"}) == []
    assert InvertedIndex.search(idx, {:phrase, "any thing"}) == []
  end

  test "punctuation is stripped during tokenization", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "Hello, world! This is a test."})
    assert InvertedIndex.search(idx, {:term, "hello"}) == ["a"]
    assert InvertedIndex.search(idx, {:term, "world"}) == ["a"]
    assert InvertedIndex.search(idx, {:phrase, "hello world"}) == ["a"]
  end

  test "accepts :name option for registration" do
    {:ok, _pid} = InvertedIndex.start_link(name: :bool_index)
    :ok = InvertedIndex.index(:bool_index, "a", %{body: "hello world"})
    assert InvertedIndex.search(:bool_index, {:term, "hello"}) == ["a"]
  end

  test "term query with multi-token word uses only the first token", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick green turtle"})
    :ok = InvertedIndex.index(idx, "c", %{body: "slow brown bear"})

    # tokenizes to ["quick", "brown"]; only "quick" is used
    assert InvertedIndex.search(idx, {:term, "quick brown"}) == ["a", "b"]
    # punctuation-separated form tokenizes the same way
    assert InvertedIndex.search(idx, {:term, "quick, brown!"}) == ["a", "b"]
  end

  test "phrase of only stop words matches no documents", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "the quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "is on at the of"})

    assert InvertedIndex.search(idx, {:phrase, "the is of"}) == []
    assert InvertedIndex.search(idx, {:phrase, "!!! ,,,"}) == []
    assert InvertedIndex.search(idx, {:phrase, ""}) == []
  end

  test "removed document drops its exclusive terms from the vocabulary", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{body: "quick brown fox"})
    :ok = InvertedIndex.index(idx, "b", %{body: "quick brown cat"})
    assert InvertedIndex.stats(idx).term_count == 4

    :ok = InvertedIndex.remove(idx, "a")

    assert InvertedIndex.search(idx, {:term, "fox"}) == []
    assert InvertedIndex.search(idx, {:phrase, "brown fox"}) == []
    assert InvertedIndex.suggest(idx, "fo") == []
    assert InvertedIndex.stats(idx).term_count == 3
  end

  test "every documented default stop word is excluded from the index", _ctx do
    {:ok, idx} = InvertedIndex.start_link([])

    defaults = ~w(the a an is are was were in on at to of and or it this that for with
                as by not be has had have do does did but if from)

    text = Enum.join(defaults, " ") <> " sentinel"
    :ok = InvertedIndex.index(idx, "a", %{body: text})

    assert InvertedIndex.stats(idx).term_count == 1
    assert InvertedIndex.search(idx, {:term, "sentinel"}) == ["a"]

    for word <- defaults do
      assert InvertedIndex.search(idx, {:term, word}) == [], "#{word} was indexed"
    end
  end

  test "re-indexing removes the old version's terms from the vocabulary", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{title: "apple pie", body: "apple banana"})
    assert InvertedIndex.stats(idx).term_count == 3

    :ok = InvertedIndex.index(idx, "a", %{body: "cherry"})

    assert InvertedIndex.stats(idx) == %{document_count: 1, term_count: 1}
    assert InvertedIndex.suggest(idx, "app") == []
    assert InvertedIndex.search(idx, {:phrase, "apple pie"}) == []
    assert InvertedIndex.search(idx, {:term, "cherry"}) == ["a"]
  end

  test "term query matches a token found in any field of the document", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "a", %{title: "alpha", body: "beta", notes: "gamma"})
    :ok = InvertedIndex.index(idx, "b", %{title: "beta", body: "delta"})

    assert InvertedIndex.search(idx, {:term, "alpha"}) == ["a"]
    assert InvertedIndex.search(idx, {:term, "gamma"}) == ["a"]
    assert InvertedIndex.search(idx, {:term, "beta"}) == ["a", "b"]
  end
end
```
