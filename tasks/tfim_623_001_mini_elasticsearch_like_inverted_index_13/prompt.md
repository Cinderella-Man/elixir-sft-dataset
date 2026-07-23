# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule InvertedIndex do
  @moduledoc """
  A full-text search engine backed by a GenServer, supporting TF-IDF scoring,
  field-level boosting, prefix-based term suggestion, and optional suffix-stripping stemming.
  """

  use GenServer

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

  # ── State shape ──────────────────────────────────────────────────────────────
  #
  # %{
  #   stop_words: MapSet.t(),
  #   docs: %{doc_id => %{field_name => [token, ...]}},       # raw tokens per field
  #   postings: %{term => %{doc_id => %{field_name => count}}}, # inverted index
  #   doc_freq: %{term => pos_integer}                          # # docs containing term
  # }

  # ── Public API ───────────────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  @doc "Start the InvertedIndex process."
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @spec index(GenServer.server(), term(), map(), keyword()) :: :ok
  @doc "Index a document. Re-indexing the same `id` replaces the previous version."
  def index(server, id, fields, opts \\ []) do
    GenServer.call(server, {:index, id, fields, opts})
  end

  @spec remove(GenServer.server(), term()) :: :ok
  @doc "Remove a document from the index. No-op when `id` is absent."
  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end

  @spec search(GenServer.server(), String.t(), keyword()) :: [%{id: term(), score: float()}]
  @doc "Search the index. Returns `[%{id: id, score: score}, ...]` sorted by score descending."
  def search(server, query, opts \\ []) do
    GenServer.call(server, {:search, query, opts})
  end

  @spec suggest(GenServer.server(), String.t(), pos_integer()) :: [String.t()]
  @doc """
  Return up to `limit` term completions for `prefix`, sorted by document
  frequency descending.
  """
  def suggest(server, prefix, limit \\ 10) do
    GenServer.call(server, {:suggest, prefix, limit})
  end

  @spec stats(GenServer.server()) :: %{
          document_count: non_neg_integer(),
          term_count: non_neg_integer()
        }
  @doc "Return `%{document_count: integer, term_count: integer}`."
  def stats(server) do
    GenServer.call(server, :stats)
  end

  # ── GenServer callbacks ──────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    stop_words = Keyword.get(opts, :stop_words, @default_stop_words)

    {:ok,
     %{
       stop_words: stop_words,
       docs: %{},
       postings: %{},
       doc_freq: %{}
     }}
  end

  @impl true
  def handle_call({:index, id, fields, opts}, _from, state) do
    # If the document already exists, remove it first so counts stay consistent.
    state = do_remove(state, id)

    stem? = Keyword.get(opts, :stem, false)

    # Tokenize every field and collect per-field token lists.
    tokenized_fields =
      Map.new(fields, fn {field, text} ->
        {field, tokenize(text, state.stop_words, stem?)}
      end)

    # Build per-term, per-field counts for this document.
    # term_field_counts :: %{term => %{field => count}}
    term_field_counts =
      Enum.reduce(tokenized_fields, %{}, fn {field, tokens}, acc ->
        freq = Enum.frequencies(tokens)

        Enum.reduce(freq, acc, fn {term, count}, inner ->
          field_map = Map.get(inner, term, %{})
          Map.put(inner, term, Map.put(field_map, field, count))
        end)
      end)

    # Merge into postings and update doc_freq.
    {postings, doc_freq} =
      Enum.reduce(term_field_counts, {state.postings, state.doc_freq}, fn {term, fmap}, {p, df} ->
        existing = Map.get(p, term, %{})
        p = Map.put(p, term, Map.put(existing, id, fmap))
        df = Map.update(df, term, 1, &(&1 + 1))
        {p, df}
      end)

    docs = Map.put(state.docs, id, tokenized_fields)

    {:reply, :ok, %{state | docs: docs, postings: postings, doc_freq: doc_freq}}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, do_remove(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    stem? = Keyword.get(opts, :stem, false)
    boosts = Keyword.get(opts, :boosts, %{})
    limit = Keyword.get(opts, :limit, nil)

    terms = tokenize(query, state.stop_words, stem?)
    total_docs = map_size(state.docs)

    # Short-circuit when the index is empty or no query terms survive tokenization.
    if total_docs == 0 or terms == [] do
      {:reply, [], state}
    else
      # Pre-compute IDF for each unique query term.
      unique_terms = Enum.uniq(terms)

      idf_map =
        Map.new(unique_terms, fn term ->
          df = Map.get(state.doc_freq, term, 0)
          idf = if df > 0, do: :math.log(total_docs / df), else: 0.0
          {term, idf}
        end)

      # Accumulate scores per document.
      scores =
        Enum.reduce(unique_terms, %{}, fn term, acc ->
          idf = Map.fetch!(idf_map, term)

          case Map.get(state.postings, term) do
            nil ->
              acc

            doc_map ->
              Enum.reduce(doc_map, acc, fn {doc_id, field_counts}, inner_acc ->
                doc_fields = Map.fetch!(state.docs, doc_id)

                term_score =
                  Enum.reduce(field_counts, 0.0, fn {field, count}, fs ->
                    total_tokens = length(Map.fetch!(doc_fields, field))
                    tf = if total_tokens > 0, do: count / total_tokens, else: 0.0
                    boost = Map.get(boosts, field, 1)
                    fs + tf * idf * boost
                  end)

                Map.update(inner_acc, doc_id, term_score, &(&1 + term_score))
              end)
          end
        end)

      results =
        scores
        |> Enum.map(fn {doc_id, score} -> %{id: doc_id, score: score} end)
        |> Enum.sort_by(& &1.score, :desc)

      results = if limit, do: Enum.take(results, limit), else: results

      {:reply, results, state}
    end
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    prefix = String.downcase(prefix)

    suggestions =
      state.doc_freq
      |> Enum.filter(fn {term, _df} -> String.starts_with?(term, prefix) end)
      |> Enum.sort_by(fn {_term, df} -> df end, :desc)
      |> Enum.take(limit)
      |> Enum.map(fn {term, _df} -> term end)

    {:reply, suggestions, state}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       document_count: map_size(state.docs),
       term_count: map_size(state.doc_freq)
     }, state}
  end

  # ── Internal helpers ─────────────────────────────────────────────────────────

  defp do_remove(state, id) do
    case Map.pop(state.docs, id) do
      {nil, _docs} ->
        state

      {tokenized_fields, docs} ->
        # Collect every unique term that appeared in this document.
        terms_in_doc =
          tokenized_fields
          |> Enum.flat_map(fn {_field, tokens} -> tokens end)
          |> Enum.uniq()

        {postings, doc_freq} =
          Enum.reduce(terms_in_doc, {state.postings, state.doc_freq}, fn term, {p, df} ->
            case Map.get(p, term) do
              nil ->
                {p, df}

              doc_map ->
                doc_map = Map.delete(doc_map, id)

                p =
                  if map_size(doc_map) == 0,
                    do: Map.delete(p, term),
                    else: Map.put(p, term, doc_map)

                new_df = Map.get(df, term, 1) - 1

                df =
                  if new_df <= 0,
                    do: Map.delete(df, term),
                    else: Map.put(df, term, new_df)

                {p, df}
            end
          end)

        %{state | docs: docs, postings: postings, doc_freq: doc_freq}
    end
  end

  @doc false
  def tokenize(text, stop_words, stem?) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&MapSet.member?(stop_words, &1))
    |> then(fn tokens ->
      if stem?, do: Enum.map(tokens, &stem/1), else: tokens
    end)
  end

  @doc false
  def stem(word) do
    word
    |> strip_suffix("tion", "t")
    |> strip_suffix("ment", "")
    |> strip_suffix("ing", "")
    |> strip_suffix("er", "")
    |> strip_suffix("ly", "")
    |> strip_suffix("ed", "")
    |> strip_suffix("s", "")
    |> dedup_trailing_consonant()
  end

  defp dedup_trailing_consonant(word) when byte_size(word) >= 3 do
    len = byte_size(word)
    last = String.at(word, len - 1)
    second_last = String.at(word, len - 2)

    if last == second_last and last not in ~w(a e i o u),
      do: String.slice(word, 0, len - 1),
      else: word
  end

  defp dedup_trailing_consonant(word), do: word

  # Only strip if the remaining root has at least 2 characters.
  defp strip_suffix(word, suffix, replacement) do
    suffix_len = byte_size(suffix)
    root_len = byte_size(word) - suffix_len

    if root_len >= 2 and String.ends_with?(word, suffix) do
      String.slice(word, 0, root_len) <> replacement
    else
      word
    end
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

    results = InvertedIndex.search(idx, "quick brown")
    ids = Enum.map(results, & &1.id)
    assert length(results) == 2
    assert "doc1" in ids
    assert "doc2" in ids
  end

  # -------------------------------------------------------
  # Stats
  # -------------------------------------------------------

  test "stats reflects document and term counts", %{idx: idx} do
    assert %{document_count: 0, term_count: 0} = InvertedIndex.stats(idx)

    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    stats = InvertedIndex.stats(idx)
    assert stats.document_count == 1
    assert stats.term_count == 3

    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma delta"})
    stats = InvertedIndex.stats(idx)
    assert stats.document_count == 2
    assert stats.term_count == 4
  end

  # -------------------------------------------------------
  # TF-IDF scoring
  # -------------------------------------------------------

  test "document with higher term frequency ranks first", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "data data data analysis"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "data analysis report summary"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "report summary overview"})

    results = InvertedIndex.search(idx, "data")
    assert length(results) == 2
    assert hd(results).id == "doc1"
    assert hd(results).score > List.last(results).score
  end

  test "rare terms get higher IDF weight", %{idx: idx} do
    # "overview" appears in 1 doc, "data" in 2 — overview has higher IDF
    :ok = InvertedIndex.index(idx, "doc1", %{body: "data data data analysis"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "data analysis report summary"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "report summary overview"})

    [rare] = InvertedIndex.search(idx, "overview")
    [_top, common] = InvertedIndex.search(idx, "data")

    # rare term "overview" in single doc can outscore common term "data" in its weaker doc
    assert rare.score > common.score
  end

  # -------------------------------------------------------
  # Stop word removal
  # -------------------------------------------------------

  test "stop words are not searchable", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "the cat is on the mat"})

    assert InvertedIndex.search(idx, "the") == []
    assert InvertedIndex.search(idx, "is") == []
    assert InvertedIndex.search(idx, "on") == []

    assert length(InvertedIndex.search(idx, "cat")) == 1
  end

  test "document with only stop words is not searchable", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "stoponly", %{body: "the a an is are was"})

    assert InvertedIndex.search(idx, "the") == []
    assert InvertedIndex.search(idx, "is") == []
  end

  # -------------------------------------------------------
  # Custom stop words
  # -------------------------------------------------------

  test "custom stop words override the defaults", _ctx do
    {:ok, idx} = InvertedIndex.start_link(stop_words: MapSet.new(["foo", "bar"]))

    :ok = InvertedIndex.index(idx, "doc1", %{body: "foo baz bar qux"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "the quick brown"})

    # "foo" and "bar" are now stop words
    assert InvertedIndex.search(idx, "foo") == []
    assert InvertedIndex.search(idx, "bar") == []

    # "the" is NOT a stop word under the custom set, so it IS indexed
    assert length(InvertedIndex.search(idx, "the")) == 1
  end

  # -------------------------------------------------------
  # Field-level boosting
  # -------------------------------------------------------

  test "title boost makes title matches rank higher", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "an animal that runs fast"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "animals", body: "fox quick clever"})
    # a third doc without the term keeps idf = log(3/2) > 0, so the scores are
    # real numbers — not an all-zero tie ranked by map-order accident
    :ok = InvertedIndex.index(idx, "doc3", %{title: "birds", body: "sparrow feathers sky"})

    boosted = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    assert Enum.map(boosted, & &1.id) == ["doc1", "doc2"]
    assert hd(boosted).score > List.last(boosted).score
  end

  test "boosted score is higher than default score for the same doc", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{title: "fox", body: "an animal"})
    :ok = InvertedIndex.index(idx, "doc2", %{title: "animals", body: "quick clever"})

    boosted = InvertedIndex.search(idx, "fox", boosts: %{title: 5, body: 1})
    unboosted = InvertedIndex.search(idx, "fox")

    doc1_boosted = Enum.find(boosted, &(&1.id == "doc1")).score
    doc1_unboosted = Enum.find(unboosted, &(&1.id == "doc1")).score

    assert doc1_boosted > doc1_unboosted
  end

  # -------------------------------------------------------
  # Multi-field scoring without boosts
  # -------------------------------------------------------

  test "term in multiple fields scores higher than in one field", %{idx: idx} do
    :ok =
      InvertedIndex.index(idx, "doc1", %{title: "python guide", body: "learn python programming"})

    :ok = InvertedIndex.index(idx, "doc2", %{title: "java guide", body: "learn python basics"})
    # a third doc without the term keeps idf > 0, so the field-sum comparison is real
    :ok = InvertedIndex.index(idx, "doc3", %{title: "ruby guide", body: "learn ruby basics"})

    results = InvertedIndex.search(idx, "python")
    assert Enum.map(results, & &1.id) == ["doc1", "doc2"]
    assert hd(results).score > List.last(results).score
  end

  # -------------------------------------------------------
  # Search limit
  # -------------------------------------------------------

  test "limit caps number of returned results", %{idx: idx} do
    # TODO
  end

  # -------------------------------------------------------
  # Stemming
  # -------------------------------------------------------

  test "stemmed search matches morphological variants", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "walking jumps quickly"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc2", %{body: "jumped walked slowly"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc3", %{body: "unrelated content here"}, stem: true)

    # "walking"/"walked" → "walk" and "jumps"/"jumped" → "jump" need only the
    # spec-listed "-ing"/"-ed"/"-s" suffixes — no stemming beyond the prompt
    walk_results = InvertedIndex.search(idx, "walking", stem: true)
    assert walk_results |> Enum.map(& &1.id) |> Enum.sort() == ["doc1", "doc2"]

    jump_results = InvertedIndex.search(idx, "jumped", stem: true)
    assert jump_results |> Enum.map(& &1.id) |> Enum.sort() == ["doc1", "doc2"]
  end

  test "unstemmed query does not match stemmed index", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "running jumps"}, stem: true)

    # Stored as "run", "jump"; query "running" not stemmed → no match
    results = InvertedIndex.search(idx, "running")
    assert results == []
  end

  # -------------------------------------------------------
  # Document removal
  # -------------------------------------------------------

  test "removed document no longer appears in results", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta gamma delta"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "gamma delta epsilon"})

    assert InvertedIndex.stats(idx).document_count == 3

    :ok = InvertedIndex.remove(idx, "doc2")

    assert InvertedIndex.stats(idx).document_count == 2

    beta = InvertedIndex.search(idx, "beta")
    assert length(beta) == 1
    assert hd(beta).id == "doc1"

    delta = InvertedIndex.search(idx, "delta")
    assert length(delta) == 1
    assert hd(delta).id == "doc3"
  end

  test "removing non-existent doc does not raise", %{idx: idx} do
    assert :ok = InvertedIndex.remove(idx, "nonexistent")
  end

  # -------------------------------------------------------
  # Document re-indexing (update)
  # -------------------------------------------------------

  test "re-indexing replaces previous content", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "apple banana cherry"})
    assert length(InvertedIndex.search(idx, "apple")) == 1

    :ok = InvertedIndex.index(idx, "doc1", %{body: "delta epsilon zeta"})

    assert InvertedIndex.search(idx, "apple") == []
    assert length(InvertedIndex.search(idx, "delta")) == 1
    assert hd(InvertedIndex.search(idx, "delta")).id == "doc1"
    assert InvertedIndex.stats(idx).document_count == 1
  end

  # -------------------------------------------------------
  # Prefix suggestion
  # -------------------------------------------------------

  test "suggest returns terms matching the prefix sorted by doc frequency", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "program productivity projects"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "testing productivity"})

    suggestions = InvertedIndex.suggest(idx, "pro")
    assert length(suggestions) > 0
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pro"))

    # "program" in 2 docs, "productivity" in 2 docs → both should come before
    # "programming", "problems", "projects" (each in 1 doc)
    top_two = Enum.take(suggestions, 2)
    assert "program" in top_two
    assert "productivity" in top_two
  end

  test "suggest respects limit", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program problems"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "program productivity projects"})

    limited = InvertedIndex.suggest(idx, "pro", 2)
    assert length(limited) == 2
  end

  test "suggest returns empty list for non-matching prefix", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    assert InvertedIndex.suggest(idx, "xyz") == []
  end

  test "suggest is case-insensitive", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "programming program"})

    assert length(InvertedIndex.suggest(idx, "PRO")) > 0
  end

  # -------------------------------------------------------
  # Empty index edge cases
  # -------------------------------------------------------

  test "search on empty index returns empty list", %{idx: idx} do
    assert InvertedIndex.search(idx, "anything") == []
  end

  test "suggest on empty index returns empty list", %{idx: idx} do
    assert InvertedIndex.suggest(idx, "abc") == []
  end

  # -------------------------------------------------------
  # Punctuation and special characters
  # -------------------------------------------------------

  test "punctuation is stripped during tokenization", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "Hello, world! This is a test."})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "hello-world test-driven development"})

    assert length(InvertedIndex.search(idx, "hello")) >= 1
    assert length(InvertedIndex.search(idx, "world")) >= 1
    assert length(InvertedIndex.search(idx, "test")) >= 1
  end

  # -------------------------------------------------------
  # Named process registration
  # -------------------------------------------------------

  test "accepts :name option for registration" do
    {:ok, _pid} = InvertedIndex.start_link(name: :my_index)

    :ok = InvertedIndex.index(:my_index, "doc1", %{body: "hello world"})
    results = InvertedIndex.search(:my_index, "hello")
    assert length(results) == 1
  end

  # -------------------------------------------------------
  # Default suggest limit
  # -------------------------------------------------------

  test "suggest without an explicit limit returns at most 10 terms", %{idx: idx} do
    words = Enum.map_join(1..12, " ", fn i -> "pre#{i}" end)
    :ok = InvertedIndex.index(idx, "doc1", %{body: words})

    # 12 candidate terms share the prefix; the documented default limit is 10
    suggestions = InvertedIndex.suggest(idx, "pre")
    assert length(suggestions) == 10
    assert Enum.all?(suggestions, &String.starts_with?(&1, "pre"))
  end

  # -------------------------------------------------------
  # Stemming is opt-in
  # -------------------------------------------------------

  test "indexing without the stem option stores unstemmed tokens", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "walking"})

    # stemming is controlled per-call via opts[:stem]; absent means off, so the
    # stored term is the literal token "walking", not the stem "walk"
    assert [%{id: "doc1"}] = InvertedIndex.search(idx, "walking")
    assert InvertedIndex.search(idx, "walk") == []
  end

  # -------------------------------------------------------
  # Exact TF-IDF value with the documented default boost
  # -------------------------------------------------------

  test "unlisted field boost defaults to exactly 1 in tf-idf scoring", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "fox runs fast"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "cat naps quietly"})

    # tf = 1/3, idf = log(2/1); :body is not listed in boosts so its boost is 1
    [result] = InvertedIndex.search(idx, "fox", boosts: %{title: 3})
    assert result.id == "doc1"
    assert_in_delta result.score, :math.log(2) / 3, 1.0e-9
  end

  # -------------------------------------------------------
  # Removal keeps per-term document frequency exact
  # -------------------------------------------------------

  test "removing a document decrements per-term document frequency for idf", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "beta alpha"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "gamma delta"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "beta zeta"})

    :ok = InvertedIndex.remove(idx, "doc3")

    # "beta" is now in exactly 1 of 2 documents: tf = 1/2, idf = log(2/1)
    [result] = InvertedIndex.search(idx, "beta")
    assert result.id == "doc1"
    assert_in_delta result.score, :math.log(2) / 2, 1.0e-9

    # "zeta" left with doc3; the vocabulary is alpha, beta, gamma, delta
    assert InvertedIndex.stats(idx).term_count == 4
    assert InvertedIndex.suggest(idx, "zeta") == []
  end

  # -------------------------------------------------------
  # Tokenization produces no empty tokens
  # -------------------------------------------------------

  test "leading and trailing punctuation adds no tokens or terms", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "Hello, world!"})

    # splitting on ~r/[^a-z0-9]+/ yields exactly ["hello", "world"]
    assert InvertedIndex.stats(idx).term_count == 2
  end

  # -------------------------------------------------------
  # Disjunctive retrieval across query terms
  # -------------------------------------------------------

  test "a document matching only one of several query terms is still returned", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha kappa lambda"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "beta kappa sigma"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "gamma delta epsilon"})

    # search finds all documents containing at least one query term: doc1 has
    # only "alpha", doc2 has only "beta", and no document contains both
    results = InvertedIndex.search(idx, "alpha beta")
    assert results |> Enum.map(& &1.id) |> Enum.sort() == ["doc1", "doc2"]
  end

  # -------------------------------------------------------
  # Cross-term score summation
  # -------------------------------------------------------

  test "scores of matching query terms are summed per document", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "alpha beta gamma"})
    :ok = InvertedIndex.index(idx, "doc2", %{body: "alpha delta epsilon"})
    :ok = InvertedIndex.index(idx, "doc3", %{body: "zeta kappa sigma"})

    combined = InvertedIndex.search(idx, "alpha beta")
    assert Enum.map(combined, & &1.id) == ["doc1", "doc2"]

    doc1 = Enum.find(combined, &(&1.id == "doc1"))
    doc2 = Enum.find(combined, &(&1.id == "doc2"))

    # doc1 matches both terms: alpha has tf = 1/3 and idf = log(3/2), beta has
    # tf = 1/3 and idf = log(3/1); the two term scores add together
    assert_in_delta doc1.score, :math.log(3 / 2) / 3 + :math.log(3) / 3, 1.0e-9

    # the same sum, stated against the single-term scores of the same document
    alpha_only = Enum.find(InvertedIndex.search(idx, "alpha"), &(&1.id == "doc1")).score
    beta_only = Enum.find(InvertedIndex.search(idx, "beta"), &(&1.id == "doc1")).score
    assert_in_delta doc1.score, alpha_only + beta_only, 1.0e-9

    # doc2 matches only "alpha" and keeps exactly that one term's score
    assert_in_delta doc2.score, :math.log(3 / 2) / 3, 1.0e-9
    assert doc1.score > doc2.score
  end

  # -------------------------------------------------------
  # Stemmer: trailing doubled-letter handling
  # -------------------------------------------------------

  test "stemming collapses a trailing doubled consonant to a single letter", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "running"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc2", %{body: "run"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc3", %{body: "zebra"}, stem: true)

    # stripping "-ing" leaves "runn", whose trailing doubled consonant collapses
    # to a single letter, so "running" and the bare word "run" share a term
    results = InvertedIndex.search(idx, "run", stem: true)
    assert results |> Enum.map(& &1.id) |> Enum.sort() == ["doc1", "doc2"]
  end

  test "stemming keeps a trailing doubled vowel intact", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "seeing"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc2", %{body: "sees"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc3", %{body: "zebra"}, stem: true)

    # "seeing" strips "-ing" and "sees" strips "-s"; both land on "see" because
    # the doubled letter is a vowel and therefore survives the collapse rule
    results = InvertedIndex.search(idx, "seeing", stem: true)
    assert results |> Enum.map(& &1.id) |> Enum.sort() == ["doc1", "doc2"]

    # a vowel-collapsed "se" is not the stored term, so it matches nothing
    assert InvertedIndex.search(idx, "se", stem: true) == []
  end

  # -------------------------------------------------------
  # Stemmer: -tion, -ment and -ly rules
  # -------------------------------------------------------

  test "stemming rewrites the -tion suffix to -t", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "creation"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc2", %{body: "created"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc3", %{body: "zebra"}, stem: true)

    # "creation" → "creat" via the "-tion" → "-t" rule, meeting "created" → "creat"
    results = InvertedIndex.search(idx, "created", stem: true)
    assert results |> Enum.map(& &1.id) |> Enum.sort() == ["doc1", "doc2"]
  end

  test "stemming strips the -ment suffix", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "payment"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc2", %{body: "pay"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc3", %{body: "zebra"}, stem: true)

    # "payment" → "pay", the same term the bare word "pay" produces
    results = InvertedIndex.search(idx, "payment", stem: true)
    assert results |> Enum.map(& &1.id) |> Enum.sort() == ["doc1", "doc2"]
  end

  test "stemming strips the -ly suffix", %{idx: idx} do
    :ok = InvertedIndex.index(idx, "doc1", %{body: "quickly"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc2", %{body: "quick"}, stem: true)
    :ok = InvertedIndex.index(idx, "doc3", %{body: "zebra"}, stem: true)

    # "quickly" → "quick", the same term the bare word "quick" produces
    results = InvertedIndex.search(idx, "quickly", stem: true)
    assert results |> Enum.map(& &1.id) |> Enum.sort() == ["doc1", "doc2"]
  end
end
```
