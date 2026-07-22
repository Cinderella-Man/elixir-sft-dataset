defmodule InvertedIndex do
  @moduledoc """
  An in-memory full-text search engine backed by a `GenServer`.

  The index maintains an inverted mapping from terms to postings. Each posting records, for a
  given document, how many times a term occurs in each of the document's fields. Together with
  the per-field token counts this is enough to compute TF-IDF scores at query time:

      tf(term, doc, field) = occurrences_of_term_in_field / total_tokens_in_field
      idf(term)            = log(total_documents / documents_containing_term)
      score(term, doc)     = sum over fields of tf * idf * boost(field)

  Scores of individual query terms are summed to produce the final document score.

  Features:

    * configurable stop-word removal,
    * an optional (per-call) suffix-stripping stemmer,
    * field-level boosting at query time,
    * prefix suggestions ranked by document frequency,
    * clean re-indexing and removal of documents.

  All tokens are lowercased, so storage and lookup are case-insensitive.

  ## Example

      {:ok, pid} = InvertedIndex.start_link([])
      :ok = InvertedIndex.index(pid, "1", %{title: "Quick brown fox", body: "The fox jumped"})
      InvertedIndex.search(pid, "fox", boosts: %{title: 3, body: 1})
      #=> [%{id: "1", score: 0.0}]

  """

  use GenServer

  @default_stop_words MapSet.new(~w(
    the a an is are was were in on at to of and or it this that for with as by not be has had
    have do does did but if from
  ))

  @token_pattern ~r/[^a-z0-9]+/

  @typedoc "Identifier of an indexed document."
  @type document_id :: String.t()

  @typedoc "Field name of a document; any term-comparable key is accepted."
  @type field :: atom() | String.t()

  @typedoc "Map of field names to their raw text contents."
  @type fields :: %{optional(field()) => String.t()}

  @typedoc "A single search result."
  @type result :: %{id: document_id(), score: float()}

  @typedoc "Reference to a running index process."
  @type server :: GenServer.server()

  defmodule State do
    @moduledoc false

    defstruct stop_words: MapSet.new(), docs: %{}, postings: %{}

    @type t :: %__MODULE__{
            stop_words: MapSet.t(String.t()),
            docs: %{optional(String.t()) => %{lengths: map(), terms: [String.t()]}},
            postings: %{optional(String.t()) => %{optional(String.t()) => map()}}
          }
  end

  # ----------------------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------------------

  @doc """
  Starts the index process.

  ## Options

    * `:name` - optional name used to register the process.
    * `:stop_words` - a `MapSet` of words removed during tokenization. Defaults to a built-in
      English stop-word set.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Indexes `fields` of the document identified by `id`.

  Re-indexing an existing `id` first removes the previous version of the document, so postings
  never contain stale data.

  ## Options

    * `:stem` - when `true`, tokens are stemmed before being stored.

  """
  @spec index(server(), document_id(), fields(), keyword()) :: :ok
  def index(server, id, fields, opts \\ []) when is_binary(id) and is_map(fields) do
    GenServer.call(server, {:index, id, fields, opts})
  end

  @doc """
  Removes the document `id` from the index.

  Removing an unknown id is a no-op. The document count used for IDF drops accordingly.
  """
  @spec remove(server(), document_id()) :: :ok
  def remove(server, id) when is_binary(id) do
    GenServer.call(server, {:remove, id})
  end

  @doc """
  Searches the index and returns documents ranked by descending TF-IDF score.

  A document matches when it contains at least one query term. Ties are broken by document id.

  ## Options

    * `:boosts` - map of field name to multiplier, e.g. `%{title: 3, body: 1}`. Fields absent
      from the map use a boost of `1`.
    * `:limit` - maximum number of results returned.
    * `:stem` - when `true`, the query is stemmed with the same stemmer used at index time.

  """
  @spec search(server(), String.t(), keyword()) :: [result()]
  def search(server, query, opts \\ []) when is_binary(query) do
    GenServer.call(server, {:search, query, opts})
  end

  @doc """
  Returns up to `limit` vocabulary terms starting with `prefix`.

  The prefix is lowercased before lookup. Terms are ordered by document frequency descending,
  then alphabetically.
  """
  @spec suggest(server(), String.t(), pos_integer()) :: [String.t()]
  def suggest(server, prefix, limit \\ 10) when is_binary(prefix) and is_integer(limit) do
    GenServer.call(server, {:suggest, prefix, limit})
  end

  @doc """
  Returns index statistics: the number of indexed documents and the vocabulary size.
  """
  @spec stats(server()) :: %{document_count: non_neg_integer(), term_count: non_neg_integer()}
  def stats(server) do
    GenServer.call(server, :stats)
  end

  @doc """
  Returns the default built-in stop-word set.
  """
  @spec default_stop_words() :: MapSet.t(String.t())
  def default_stop_words, do: @default_stop_words

  # ----------------------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    stop_words =
      case Keyword.get(opts, :stop_words) do
        nil -> @default_stop_words
        %MapSet{} = set -> set
        enumerable -> MapSet.new(enumerable, &String.downcase/1)
      end

    {:ok, %State{stop_words: stop_words}}
  end

  @impl GenServer
  def handle_call({:index, id, fields, opts}, _from, state) do
    stem? = Keyword.get(opts, :stem, false)
    state = purge(state, id)

    {counts, lengths} = analyze(fields, state.stop_words, stem?)
    terms = counts |> Enum.flat_map(fn {_field, fc} -> Map.keys(fc) end) |> Enum.uniq()

    postings = merge_postings(state.postings, id, counts)
    docs = Map.put(state.docs, id, %{lengths: lengths, terms: terms})

    {:reply, :ok, %State{state | docs: docs, postings: postings}}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, purge(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    {:reply, do_search(state, query, opts), state}
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    {:reply, do_suggest(state, prefix, limit), state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{document_count: map_size(state.docs), term_count: map_size(state.postings)}
    {:reply, stats, state}
  end

  # ----------------------------------------------------------------------------------------
  # Indexing internals
  # ----------------------------------------------------------------------------------------

  @spec analyze(fields(), MapSet.t(String.t()), boolean()) :: {map(), map()}
  defp analyze(fields, stop_words, stem?) do
    Enum.reduce(fields, {%{}, %{}}, fn {field, text}, {counts, lengths} ->
      tokens = tokenize(to_string(text), stop_words, stem?)

      {
        Map.put(counts, field, Enum.frequencies(tokens)),
        Map.put(lengths, field, length(tokens))
      }
    end)
  end

  @spec merge_postings(map(), document_id(), map()) :: map()
  defp merge_postings(postings, id, counts) do
    Enum.reduce(counts, postings, fn {field, field_counts}, acc ->
      Enum.reduce(field_counts, acc, fn {term, count}, term_acc ->
        Map.update(term_acc, term, %{id => %{field => count}}, fn docs ->
          Map.update(docs, id, %{field => count}, &Map.put(&1, field, count))
        end)
      end)
    end)
  end

  @spec purge(State.t(), document_id()) :: State.t()
  defp purge(state, id) do
    case Map.pop(state.docs, id) do
      {nil, _docs} ->
        state

      {%{terms: terms}, docs} ->
        postings = Enum.reduce(terms, state.postings, &drop_posting(&2, &1, id))
        %State{state | docs: docs, postings: postings}
    end
  end

  @spec drop_posting(map(), String.t(), document_id()) :: map()
  defp drop_posting(postings, term, id) do
    case Map.fetch(postings, term) do
      :error ->
        postings

      {:ok, entry} ->
        entry = Map.delete(entry, id)
        if map_size(entry) == 0, do: Map.delete(postings, term), else: Map.put(postings, term, entry)
    end
  end

  # ----------------------------------------------------------------------------------------
  # Search internals
  # ----------------------------------------------------------------------------------------

  @spec do_search(State.t(), String.t(), keyword()) :: [result()]
  defp do_search(state, query, opts) do
    boosts = Keyword.get(opts, :boosts, %{}) || %{}
    limit = Keyword.get(opts, :limit)
    stem? = Keyword.get(opts, :stem, false)

    total = map_size(state.docs)
    terms = query |> tokenize(state.stop_words, stem?) |> Enum.uniq()

    if total == 0 or terms == [] do
      []
    else
      terms
      |> Enum.reduce(%{}, &accumulate_term(&1, &2, state, total, boosts))
      |> Enum.map(fn {id, score} -> %{id: id, score: score} end)
      |> Enum.sort_by(fn %{id: id, score: score} -> {-score, id} end)
      |> maybe_limit(limit)
    end
  end

  @spec accumulate_term(String.t(), map(), State.t(), pos_integer(), map()) :: map()
  defp accumulate_term(term, scores, state, total, boosts) do
    case Map.fetch(state.postings, term) do
      :error ->
        scores

      {:ok, postings} ->
        idf = :math.log(total / map_size(postings))

        Enum.reduce(postings, scores, fn {id, field_counts}, acc ->
          lengths = get_in(state.docs, [id, :lengths]) || %{}
          score = document_score(field_counts, lengths, idf, boosts)
          Map.update(acc, id, score, &(&1 + score))
        end)
    end
  end

  @spec document_score(map(), map(), float(), map()) :: float()
  defp document_score(field_counts, lengths, idf, boosts) do
    Enum.reduce(field_counts, 0.0, fn {field, count}, acc ->
      case Map.get(lengths, field, 0) do
        0 -> acc
        length -> acc + count / length * idf * boost_for(boosts, field)
      end
    end)
  end

  @spec boost_for(map(), field()) :: number()
  defp boost_for(boosts, field) do
    case Map.fetch(boosts, field) do
      {:ok, boost} -> boost
      :error -> Map.get(boosts, to_string(field), 1)
    end
  end

  @spec maybe_limit([result()], nil | integer()) :: [result()]
  defp maybe_limit(results, nil), do: results
  defp maybe_limit(results, limit) when is_integer(limit) and limit >= 0, do: Enum.take(results, limit)
  defp maybe_limit(results, _limit), do: results

  @spec do_suggest(State.t(), String.t(), integer()) :: [String.t()]
  defp do_suggest(_state, _prefix, limit) when limit <= 0, do: []

  defp do_suggest(state, prefix, limit) do
    prefix = String.downcase(prefix)

    state.postings
    |> Enum.filter(fn {term, _postings} -> String.starts_with?(term, prefix) end)
    |> Enum.sort_by(fn {term, postings} -> {-map_size(postings), term} end)
    |> Enum.take(limit)
    |> Enum.map(fn {term, _postings} -> term end)
  end

  # ----------------------------------------------------------------------------------------
  # Tokenization
  # ----------------------------------------------------------------------------------------

  @spec tokenize(String.t(), MapSet.t(String.t()), boolean()) :: [String.t()]
  defp tokenize(text, stop_words, stem?) do
    text
    |> String.downcase()
    |> String.split(@token_pattern, trim: true)
    |> Enum.reject(&MapSet.member?(stop_words, &1))
    |> maybe_stem(stem?)
  end

  @spec maybe_stem([String.t()], boolean()) :: [String.t()]
  defp maybe_stem(tokens, true), do: Enum.map(tokens, &stem/1)
  defp maybe_stem(tokens, _stem?), do: tokens

  @spec stem(String.t()) :: String.t()
  defp stem(word) do
    cond do
      strippable?(word, "tion") -> chop(word, "tion") <> "t"
      strippable?(word, "ment") -> chop(word, "ment")
      strippable?(word, "ing") -> chop(word, "ing")
      strippable?(word, "ed") -> chop(word, "ed")
      strippable?(word, "ly") -> chop(word, "ly")
      String.ends_with?(word, "ss") -> word
      strippable?(word, "s") -> chop(word, "s")
      true -> word
    end
  end

  @spec strippable?(String.t(), String.t()) :: boolean()
  defp strippable?(word, suffix) do
    String.ends_with?(word, suffix) and
      byte_size(word) - byte_size(suffix) >= 3
  end

  @spec chop(String.t(), String.t()) :: String.t()
  defp chop(word, suffix), do: binary_part(word, 0, byte_size(word) - byte_size(suffix))
end