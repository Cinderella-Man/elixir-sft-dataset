# Fill in one @spec

Below: a working module where the `@spec` for
`remove_doc/2` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `remove_doc/2` missing

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

  # TODO: @spec
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

The `@spec` attribute only — nothing more.
