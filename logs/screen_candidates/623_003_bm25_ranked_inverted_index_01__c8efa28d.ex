defmodule InvertedIndex do
  @moduledoc """
  An in-memory full-text search engine implemented as a `GenServer`.

  Documents are supplied as maps of field names to text. Text is tokenized by
  lowercasing, splitting on any run of non-alphanumeric characters, and dropping
  stop words. No stemming is performed.

  Ranking uses the Okapi BM25 scoring function:

      score(d) = Σ_t IDF(t) · [ f(t,d) · (k1 + 1) ] /
                             [ f(t,d) + k1 · (1 − b + b · |d| / avgdl) ]

      IDF(t)   = ln( 1 + (N − df(t) + 0.5) / (df(t) + 0.5) )

  where `N` is the number of indexed documents, `df(t)` the number of documents
  containing term `t`, `f(t,d)` the boost-weighted count of `t` in `d`, `|d|` the
  boost-weighted length of `d`, and `avgdl` the mean boost-weighted length across
  all indexed documents. Field boosts are supplied per-search via `opts[:boosts]`;
  unlisted fields default to a boost of `1`.

  The index also supports prefix suggestion over its vocabulary, ordered by
  document frequency.

  ## Example

      {:ok, pid} = InvertedIndex.start_link([])
      :ok = InvertedIndex.index(pid, "1", %{title: "Quick brown fox",
                                            body: "The fox jumped over the lazy dog"})
      InvertedIndex.search(pid, "fox", boosts: %{title: 3, body: 1})
      #=> [%{id: "1", score: 0.13...}]
  """

  use GenServer

  @default_stop_words MapSet.new(~w(
    the a an is are was were in on at to of and or it this that for with as by
    not be has had have do does did but if from
  ))

  @default_k1 1.2
  @default_b 0.75
  @token_separator ~r/[^a-z0-9]+/

  @typedoc "A document identifier."
  @type id :: String.t()

  @typedoc "A map of field name to raw text."
  @type fields :: %{optional(atom() | String.t()) => String.t()}

  @typedoc "A map of field name to numeric boost."
  @type boosts :: %{optional(atom() | String.t()) => number()}

  @typedoc "A single search result."
  @type result :: %{id: id(), score: float()}

  # Server state.
  #
  #   * `:docs`       — %{id => %{field => %{term => count}}}
  #   * `:field_lens` — %{id => %{field => token_count}}
  #   * `:postings`   — %{term => MapSet.t(id)} (used for df and candidate lookup)
  #   * `:stop_words` — MapSet.t(String.t())
  #   * `:k1`, `:b`   — BM25 parameters
  defstruct docs: %{},
            field_lens: %{},
            postings: %{},
            stop_words: @default_stop_words,
            k1: @default_k1,
            b: @default_b

  @doc """
  Starts the index process.

  ## Options

    * `:name` — optional process registration name.
    * `:stop_words` — a `MapSet` of words removed during tokenization. Defaults to a
      built-in English stop-word set.
    * `:k1` — BM25 term-frequency saturation parameter. Defaults to `1.2`.
    * `:b` — BM25 length-normalization parameter. Defaults to `0.75`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc """
  Indexes `fields` under document `id`, replacing any previous version of `id`.

  `fields` is a map of field name to text, e.g.
  `%{title: "Quick brown fox", body: "The fox jumped over the lazy dog"}`.
  """
  @spec index(GenServer.server(), id(), fields()) :: :ok
  def index(server, id, fields) when is_binary(id) and is_map(fields) do
    GenServer.call(server, {:index, id, fields})
  end

  @doc """
  Removes document `id` from the index. Removing an unknown `id` is a no-op.
  """
  @spec remove(GenServer.server(), id()) :: :ok
  def remove(server, id) when is_binary(id) do
    GenServer.call(server, {:remove, id})
  end

  @doc """
  Searches the index for `query`, returning documents ranked by BM25 score descending.

  Matching documents are those containing at least one query term.

  ## Options

    * `:boosts` — a map of field name to numeric boost, e.g. `%{title: 3, body: 1}`.
      Fields not listed default to a boost of `1`.
    * `:limit` — caps the number of returned results.
  """
  @spec search(GenServer.server(), String.t(), keyword()) :: [result()]
  def search(server, query, opts \\ []) when is_binary(query) and is_list(opts) do
    GenServer.call(server, {:search, query, opts})
  end

  @doc """
  Returns up to `limit` vocabulary terms starting with `prefix`, most frequent first.

  The prefix is lowercased before lookup, and terms are ordered by document
  frequency descending.
  """
  @spec suggest(GenServer.server(), String.t(), pos_integer()) :: [String.t()]
  def suggest(server, prefix, limit \\ 10) when is_binary(prefix) and is_integer(limit) do
    GenServer.call(server, {:suggest, prefix, limit})
  end

  @doc """
  Returns index statistics: the number of indexed documents and the vocabulary size.
  """
  @spec stats(GenServer.server()) :: %{document_count: non_neg_integer(), term_count: non_neg_integer()}
  def stats(server) do
    GenServer.call(server, :stats)
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  def init(opts) do
    state = %__MODULE__{
      stop_words: Keyword.get(opts, :stop_words, @default_stop_words),
      k1: Keyword.get(opts, :k1, @default_k1) / 1,
      b: Keyword.get(opts, :b, @default_b) / 1
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:index, id, fields}, _from, state) do
    state = do_remove(state, id)

    field_terms =
      Map.new(fields, fn {field, text} ->
        {field, tokenize(text, state.stop_words)}
      end)

    counts = Map.new(field_terms, fn {field, tokens} -> {field, count_terms(tokens)} end)
    lens = Map.new(field_terms, fn {field, tokens} -> {field, length(tokens)} end)

    postings =
      counts
      |> Enum.flat_map(fn {_field, term_counts} -> Map.keys(term_counts) end)
      |> Enum.uniq()
      |> Enum.reduce(state.postings, fn term, acc ->
        Map.update(acc, term, MapSet.new([id]), &MapSet.put(&1, id))
      end)

    state = %{
      state
      | docs: Map.put(state.docs, id, counts),
        field_lens: Map.put(state.field_lens, id, lens),
        postings: postings
    }

    {:reply, :ok, state}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, do_remove(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    {:reply, do_search(state, query, opts), state}
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    {:reply, do_suggest(state, prefix, limit), state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      document_count: map_size(state.docs),
      term_count: map_size(state.postings)
    }

    {:reply, stats, state}
  end

  # ------------------------------------------------------------------
  # Internals
  # ------------------------------------------------------------------

  @spec tokenize(String.t(), MapSet.t(String.t())) :: [String.t()]
  defp tokenize(text, stop_words) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split(@token_separator, trim: true)
    |> Enum.reject(&MapSet.member?(stop_words, &1))
  end

  @spec count_terms([String.t()]) :: %{String.t() => pos_integer()}
  defp count_terms(tokens) do
    Enum.reduce(tokens, %{}, fn token, acc -> Map.update(acc, token, 1, &(&1 + 1)) end)
  end

  @spec do_remove(%__MODULE__{}, id()) :: %__MODULE__{}
  defp do_remove(state, id) do
    case Map.fetch(state.docs, id) do
      :error ->
        state

      {:ok, counts} ->
        terms =
          counts
          |> Enum.flat_map(fn {_field, term_counts} -> Map.keys(term_counts) end)
          |> Enum.uniq()

        postings =
          Enum.reduce(terms, state.postings, fn term, acc ->
            case Map.fetch(acc, term) do
              :error ->
                acc

              {:ok, ids} ->
                remaining = MapSet.delete(ids, id)

                if MapSet.size(remaining) == 0 do
                  Map.delete(acc, term)
                else
                  Map.put(acc, term, remaining)
                end
            end
          end)

        %{
          state
          | docs: Map.delete(state.docs, id),
            field_lens: Map.delete(state.field_lens, id),
            postings: postings
        }
    end
  end

  @spec do_search(%__MODULE__{}, String.t(), keyword()) :: [result()]
  defp do_search(state, query, opts) do
    boosts = Keyword.get(opts, :boosts, %{})
    limit = Keyword.get(opts, :limit)

    terms = state |> Map.fetch!(:stop_words) |> then(&tokenize(query, &1)) |> Enum.uniq()
    total_docs = map_size(state.docs)

    cond do
      terms == [] or total_docs == 0 ->
        []

      true ->
        doc_lengths =
          Map.new(state.field_lens, fn {id, lens} -> {id, weighted_length(lens, boosts)} end)

        avgdl = average(Map.values(doc_lengths))

        candidates =
          terms
          |> Enum.flat_map(fn term ->
            state.postings |> Map.get(term, MapSet.new()) |> MapSet.to_list()
          end)
          |> Enum.uniq()

        candidates
        |> Enum.map(fn id ->
          score = score_document(state, id, terms, boosts, doc_lengths, avgdl, total_docs)
          %{id: id, score: score}
        end)
        |> Enum.sort_by(& &1.score, :desc)
        |> apply_limit(limit)
    end
  end

  @spec score_document(
          %__MODULE__{},
          id(),
          [String.t()],
          boosts(),
          %{id() => float()},
          float(),
          pos_integer()
        ) :: float()
  defp score_document(state, id, terms, boosts, doc_lengths, avgdl, total_docs) do
    counts = Map.fetch!(state.docs, id)
    doc_len = Map.fetch!(doc_lengths, id)

    norm =
      case avgdl do
        +0.0 -> 1.0 - state.b
        _ -> 1.0 - state.b + state.b * doc_len / avgdl
      end

    Enum.reduce(terms, 0.0, fn term, acc ->
      tf = weighted_term_frequency(counts, term, boosts)

      if tf > 0.0 do
        df = state.postings |> Map.get(term, MapSet.new()) |> MapSet.size()
        idf = :math.log(1 + (total_docs - df + 0.5) / (df + 0.5))
        acc + idf * (tf * (state.k1 + 1)) / (tf + state.k1 * norm)
      else
        acc
      end
    end)
  end

  @spec weighted_term_frequency(%{term: any()} | map(), String.t(), boosts()) :: float()
  defp weighted_term_frequency(counts, term, boosts) do
    Enum.reduce(counts, 0.0, fn {field, term_counts}, acc ->
      case Map.fetch(term_counts, term) do
        :error -> acc
        {:ok, count} -> acc + count * boost_for(boosts, field)
      end
    end)
  end

  @spec weighted_length(map(), boosts()) :: float()
  defp weighted_length(lens, boosts) do
    Enum.reduce(lens, 0.0, fn {field, len}, acc -> acc + len * boost_for(boosts, field) end)
  end

  @spec boost_for(boosts(), atom() | String.t()) :: float()
  defp boost_for(boosts, field) do
    boosts |> Map.get(field, 1) |> Kernel./(1)
  end

  @spec average([float()]) :: float()
  defp average([]), do: 0.0
  defp average(values), do: Enum.sum(values) / length(values)

  @spec do_suggest(%__MODULE__{}, String.t(), integer()) :: [String.t()]
  defp do_suggest(_state, _prefix, limit) when limit <= 0, do: []

  defp do_suggest(state, prefix, limit) do
    normalized = String.downcase(prefix)

    state.postings
    |> Enum.filter(fn {term, _ids} -> String.starts_with?(term, normalized) end)
    |> Enum.sort_by(fn {term, ids} -> {-MapSet.size(ids), term} end)
    |> Enum.take(limit)
    |> Enum.map(fn {term, _ids} -> term end)
  end

  @spec apply_limit([result()], nil | integer()) :: [result()]
  defp apply_limit(results, nil), do: results
  defp apply_limit(_results, limit) when limit <= 0, do: []
  defp apply_limit(results, limit), do: Enum.take(results, limit)
end