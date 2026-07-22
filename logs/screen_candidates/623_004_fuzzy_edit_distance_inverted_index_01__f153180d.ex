defmodule FuzzyIndex do
  @moduledoc """
  A small in-memory full-text search engine with approximate (typo-tolerant) matching.

  `FuzzyIndex` is a `GenServer` that stores documents as bags of tokens and answers
  queries by comparing query terms against the indexed vocabulary using the
  Levenshtein edit distance. A query term matches a vocabulary term when their edit
  distance is at most `:max_distance` (default `1`), and documents are ranked by how
  close each match is and how often the matching term occurs.

  ## Scoring

  For a unique query term `q` and a vocabulary term `t` with
  `edit_distance(q, t) <= max_distance`, the similarity is:

      similarity(q, t) = max_distance + 1 - edit_distance(q, t)

  so an exact match scores `max_distance + 1` and a match at the maximum allowed
  distance scores `1`. A document's contribution for `q` is the maximum, over every
  matching term `t` present in the document, of `similarity(q, t) * occurrences(t)`.
  The document's score is the sum of its contributions over all unique query terms.
  Because an exact match has strictly higher similarity than any inexact match, an
  exact hit always outweighs a near-miss on a per-occurrence basis.

  ## Example

      {:ok, pid} = FuzzyIndex.start_link([])
      :ok = FuzzyIndex.index(pid, "doc1", "The quick brown fox")
      FuzzyIndex.search(pid, "quik")
      #=> [%{id: "doc1", score: 1}]

  """

  use GenServer

  @default_stop_words MapSet.new(~w(
    the a an is are was were in on at to of and or it this that for with as by
    not be has had have do does did but if from
  ))

  @typedoc "A document identifier."
  @type id :: String.t()

  @typedoc "A search result: the document id and its score."
  @type result :: %{id: id(), score: non_neg_integer()}

  defstruct docs: %{}, vocab: %{}, stop_words: @default_stop_words

  @typep state :: %__MODULE__{
           docs: %{optional(id()) => %{optional(String.t()) => pos_integer()}},
           vocab: %{optional(String.t()) => %{optional(id()) => pos_integer()}},
           stop_words: MapSet.t(String.t())
         }

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the index process.

  ## Options

    * `:name` - optional name under which to register the process.
    * `:stop_words` - a `MapSet` of words removed during tokenization. Replaces the
      built-in default stop-word set entirely.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Indexes `text` under the document `id`.

  The text is tokenized (lowercased, split on non-alphanumeric runs, stop words
  removed) and the occurrence count of each surviving token is stored. Indexing an
  existing `id` cleanly replaces the previous version of that document.
  """
  @spec index(GenServer.server(), id(), String.t()) :: :ok
  def index(server, id, text) when is_binary(id) and is_binary(text) do
    GenServer.call(server, {:index, id, text})
  end

  @doc """
  Removes the document `id` from the index.

  Vocabulary terms that no longer appear in any document are dropped. Removing an
  unknown id is a no-op and still returns `:ok`.
  """
  @spec remove(GenServer.server(), id()) :: :ok
  def remove(server, id) when is_binary(id) do
    GenServer.call(server, {:remove, id})
  end

  @doc """
  Searches the index for `query`, returning ranked results.

  The query is tokenized with the same pipeline used for indexing. Duplicate query
  terms count once. Returns `%{id: id, score: score}` maps for every document with a
  score greater than `0`, sorted by score descending.

  ## Options

    * `:max_distance` - maximum edit distance for a fuzzy match (default `1`).
    * `:limit` - maximum number of results to return, applied after sorting.

  """
  @spec search(GenServer.server(), String.t(), keyword()) :: [result()]
  def search(server, query, opts \\ []) when is_binary(query) and is_list(opts) do
    GenServer.call(server, {:search, query, opts})
  end

  @doc """
  Returns the vocabulary terms within `max_distance` edit distance of `term`.

  `term` is lowercased (but not split or tokenized) before comparison. Results are
  sorted by edit distance ascending, ties broken alphabetically ascending.
  """
  @spec terms_like(GenServer.server(), String.t(), non_neg_integer()) :: [String.t()]
  def terms_like(server, term, max_distance \\ 1)
      when is_binary(term) and is_integer(max_distance) and max_distance >= 0 do
    GenServer.call(server, {:terms_like, term, max_distance})
  end

  @doc """
  Returns index statistics: the number of documents and distinct vocabulary terms.
  """
  @spec stats(GenServer.server()) :: %{document_count: non_neg_integer(), term_count: non_neg_integer()}
  def stats(server) do
    GenServer.call(server, :stats)
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl true
  def init(opts) do
    stop_words = Keyword.get(opts, :stop_words, @default_stop_words)
    {:ok, %__MODULE__{stop_words: stop_words}}
  end

  @impl true
  def handle_call({:index, id, text}, _from, state) do
    state = do_remove(state, id)
    counts = text |> tokenize(state.stop_words) |> count_tokens()

    state =
      if map_size(counts) == 0 do
        %{state | docs: Map.put(state.docs, id, %{})}
      else
        vocab =
          Enum.reduce(counts, state.vocab, fn {term, n}, acc ->
            Map.update(acc, term, %{id => n}, &Map.put(&1, id, n))
          end)

        %{state | docs: Map.put(state.docs, id, counts), vocab: vocab}
      end

    {:reply, :ok, state}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, do_remove(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    {:reply, do_search(state, query, opts), state}
  end

  def handle_call({:terms_like, term, max_distance}, _from, state) do
    {:reply, do_terms_like(state, term, max_distance), state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{document_count: map_size(state.docs), term_count: map_size(state.vocab)}
    {:reply, stats, state}
  end

  # ----------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------

  @spec do_remove(state(), id()) :: state()
  defp do_remove(state, id) do
    case Map.pop(state.docs, id) do
      {nil, _docs} ->
        state

      {counts, docs} ->
        vocab =
          Enum.reduce(counts, state.vocab, fn {term, _n}, acc ->
            case Map.fetch(acc, term) do
              {:ok, postings} ->
                postings = Map.delete(postings, id)
                if map_size(postings) == 0, do: Map.delete(acc, term), else: Map.put(acc, term, postings)

              :error ->
                acc
            end
          end)

        %{state | docs: docs, vocab: vocab}
    end
  end

  @spec do_search(state(), String.t(), keyword()) :: [result()]
  defp do_search(state, query, opts) do
    max_distance = Keyword.get(opts, :max_distance, 1)
    limit = Keyword.get(opts, :limit)
    terms = query |> tokenize(state.stop_words) |> Enum.uniq()

    if terms == [] or map_size(state.docs) == 0 do
      []
    else
      terms
      |> Enum.reduce(%{}, fn q, scores -> accumulate(state, q, max_distance, scores) end)
      |> Enum.reject(fn {_id, score} -> score <= 0 end)
      |> Enum.map(fn {id, score} -> %{id: id, score: score} end)
      |> Enum.sort_by(& &1.score, :desc)
      |> apply_limit(limit)
    end
  end

  # Adds each document's contribution for the single query term `q` into `scores`.
  # The contribution is the max over matching terms of similarity * occurrences.
  @spec accumulate(state(), String.t(), non_neg_integer(), %{optional(id()) => integer()}) ::
          %{optional(id()) => integer()}
  defp accumulate(state, q, max_distance, scores) do
    best =
      Enum.reduce(state.vocab, %{}, fn {term, postings}, acc ->
        distance = edit_distance(q, term)

        if distance <= max_distance do
          similarity = max_distance + 1 - distance

          Enum.reduce(postings, acc, fn {id, n}, inner ->
            Map.update(inner, id, similarity * n, &max(&1, similarity * n))
          end)
        else
          acc
        end
      end)

    Enum.reduce(best, scores, fn {id, contribution}, acc ->
      Map.update(acc, id, contribution, &(&1 + contribution))
    end)
  end

  @spec apply_limit([result()], nil | integer()) :: [result()]
  defp apply_limit(results, nil), do: results
  defp apply_limit(results, limit) when is_integer(limit) and limit >= 0, do: Enum.take(results, limit)
  defp apply_limit(results, _limit), do: results

  @spec do_terms_like(state(), String.t(), non_neg_integer()) :: [String.t()]
  defp do_terms_like(state, term, max_distance) do
    needle = String.downcase(term)

    state.vocab
    |> Map.keys()
    |> Enum.map(fn t -> {edit_distance(needle, t), t} end)
    |> Enum.filter(fn {distance, _t} -> distance <= max_distance end)
    |> Enum.sort()
    |> Enum.map(fn {_distance, t} -> t end)
  end

  @spec tokenize(String.t(), MapSet.t(String.t())) :: [String.t()]
  defp tokenize(text, stop_words) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&(&1 == "" or MapSet.member?(stop_words, &1)))
  end

  @spec count_tokens([String.t()]) :: %{optional(String.t()) => pos_integer()}
  defp count_tokens(tokens) do
    Enum.reduce(tokens, %{}, fn token, acc -> Map.update(acc, token, 1, &(&1 + 1)) end)
  end

  @doc false
  @spec edit_distance(String.t(), String.t()) :: non_neg_integer()
  def edit_distance(a, b) when is_binary(a) and is_binary(b) do
    do_edit_distance(String.graphemes(a), String.graphemes(b))
  end

  # Iterative Levenshtein: keep a single previous row of the DP matrix.
  @spec do_edit_distance([String.t()], [String.t()]) :: non_neg_integer()
  defp do_edit_distance(a, []), do: length(a)
  defp do_edit_distance([], b), do: length(b)

  defp do_edit_distance(a, b) do
    initial = Enum.to_list(0..length(b))

    a
    |> Enum.reduce({initial, 1}, fn char, {prev_row, row_index} ->
      {next_row, _} = build_row(char, b, prev_row, row_index)
      {next_row, row_index + 1}
    end)
    |> elem(0)
    |> List.last()
  end

  @spec build_row(String.t(), [String.t()], [non_neg_integer()], pos_integer()) ::
          {[non_neg_integer()], non_neg_integer()}
  defp build_row(char, b, prev_row, row_index) do
    [diagonal | rest_prev] = prev_row

    {reversed, last} =
      Enum.zip(b, rest_prev)
      |> Enum.reduce({[row_index], {diagonal, row_index}}, fn {bc, above}, {acc, {diag, left}} ->
        cost = if bc == char, do: 0, else: 1
        value = Enum.min([above + 1, left + 1, diag + cost])
        {[value | acc], {above, value}}
      end)

    {Enum.reverse(reversed), elem(last, 1)}
  end
end