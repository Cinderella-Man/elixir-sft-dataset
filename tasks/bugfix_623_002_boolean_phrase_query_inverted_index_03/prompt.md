# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

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

## The buggy module

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

        if MapSet.size(set) == 1 do
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

## Failing test report

```
1 of 26 test(s) failed:

  * test removed document no longer appears
      
      
      Assertion with == failed
      code:  assert InvertedIndex.search(idx, {:term, "quick"}) == ["a"]
      left:  []
      right: ["a"]
```
