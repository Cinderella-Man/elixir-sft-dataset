Implement the private `eval/2` function for the `InvertedIndex` module below.

`eval(query, state)` is the recursive Boolean query evaluator. It takes a query
expression and the GenServer state (`%{stop_words: MapSet.t(), documents: %{id =>
%{field => [token]}}, postings: %{term => MapSet.t(id)}}`) and returns a `MapSet`
of the ids of documents matching that query. It must be written as a set of
clauses, one per query form:

* `{:term, word}` — run `word` through `tokenize/2` with the state's stop words.
  If tokenization yields no tokens, return an empty `MapSet`. Otherwise take the
  first token and return its posting list from `state.postings`, defaulting to an
  empty `MapSet` when the term is not in the vocabulary.

* `{:phrase, text}` — tokenize `text` the same way. If it yields no tokens,
  return an empty `MapSet`. If it yields exactly one token, behave like
  `{:term, token}` (a posting-list lookup). Otherwise, narrow the search with
  `candidate_ids/2` (the intersection of the posting lists of all the phrase
  terms), then keep only those ids whose document — looked up in
  `state.documents` — actually contains the term sequence at consecutive
  positions in some single field, using `doc_has_phrase?/2`. Return the survivors
  as a `MapSet`.

* `{:and, []}` — the empty conjunction matches every indexed document: return
  `all_ids/1`.

* `{:and, list}` — evaluate every sub-expression recursively and intersect the
  resulting sets with `intersect_all/1`.

* `{:or, list}` — evaluate every sub-expression recursively and union the
  resulting sets, starting from an empty `MapSet` (so an empty list matches no
  documents).

* `{:not, expr}` — return the set difference of `all_ids/1` and the evaluation of
  `expr`.

Clause ordering matters: the `{:and, []}` clause must come before the general
`{:and, list}` clause. All other private helpers (`tokenize/2`, `candidate_ids/2`,
`doc_has_phrase?/2`, `all_ids/1`, `intersect_all/1`) already exist — use them.

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
    # TODO
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