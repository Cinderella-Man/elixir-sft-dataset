defmodule InvertedIndex do
  @moduledoc """
  A Boolean full-text search engine backed by a positional inverted index.

  Unlike a ranked search engine, `InvertedIndex` answers set-membership questions: a
  document either satisfies a Boolean query expression or it does not. There is no
  relevance score — `search/2` returns the sorted list of matching document ids.

  ## Storage model

  Each document is indexed as a map of field names to text. Text is tokenized by
  lowercasing, splitting on `~r/[^a-z0-9]+/`, and dropping stop words. The *order* of the
  surviving tokens within a field is preserved so that phrase queries can match on
  consecutive positions.

  Internally the index maintains:

    * a postings map — `term => %{doc_id => %{field => [positions]}}`
    * a documents map — `doc_id => %{field => [tokens]}`, used for clean re-indexing
      and removal

  ## Query language

  Query expressions nest arbitrarily:

    * `{:term, word}` — matches documents where the tokenized `word` occurs in any field
    * `{:phrase, text}` — matches documents where one field contains the tokenized term
      sequence at consecutive positions
    * `{:and, list}` — conjunction; an empty list matches every indexed document
    * `{:or, list}` — disjunction; an empty list matches no document
    * `{:not, expr}` — complement of `expr` over all indexed documents

  ## Example

      {:ok, pid} = InvertedIndex.start_link([])
      :ok = InvertedIndex.index(pid, "d1", %{title: "Quick brown fox",
                                             body: "The fox jumped over the lazy dog"})
      InvertedIndex.search(pid, {:phrase, "quick brown fox"})
      #=> ["d1"]
      InvertedIndex.search(pid, {:and, [{:term, "fox"}, {:not, {:term, "cat"}}]})
      #=> ["d1"]
  """

  use GenServer

  @default_stop_words MapSet.new(~w(
    the a an is are was were in on at to of and or it this that for with as by
    not be has had have do does did but if from
  ))

  @token_splitter ~r/[^a-z0-9]+/

  @typedoc "A document identifier."
  @type doc_id :: String.t()

  @typedoc "A field name; any term usable as a map key (atoms and strings are typical)."
  @type field :: term()

  @typedoc "A map of field names to raw text."
  @type fields :: %{optional(field()) => String.t()}

  @typedoc "A Boolean query expression."
  @type query ::
          {:term, String.t()}
          | {:phrase, String.t()}
          | {:and, [query()]}
          | {:or, [query()]}
          | {:not, query()}

  @typedoc "A running index process."
  @type server :: GenServer.server()

  defmodule State do
    @moduledoc false

    defstruct stop_words: MapSet.new(),
              postings: %{},
              documents: %{}

    @type t :: %__MODULE__{
            stop_words: MapSet.t(String.t()),
            postings: %{optional(String.t()) => %{optional(String.t()) => map()}},
            documents: %{optional(String.t()) => map()}
          }
  end

  # ----------------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------------

  @doc """
  Starts the index process.

  ## Options

    * `:name` — an optional name for process registration
    * `:stop_words` — a `MapSet` of words removed during tokenization; defaults to a
      built-in English stop-word set

  Any other options are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {stop_words, opts} = Keyword.pop(opts, :stop_words, @default_stop_words)
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: Keyword.put(opts, :name, name), else: opts
    GenServer.start_link(__MODULE__, stop_words, server_opts)
  end

  @doc """
  Indexes `fields` under document `id`, replacing any previous version of that document.

  `fields` is a map of field names to raw text, e.g.
  `%{title: "Quick brown fox", body: "The fox jumped over the lazy dog"}`.
  """
  @spec index(server(), doc_id(), fields()) :: :ok
  def index(server, id, fields) when is_binary(id) and is_map(fields) do
    GenServer.call(server, {:index, id, fields})
  end

  @doc """
  Removes document `id` from the index.

  Removing an unknown id is a no-op.
  """
  @spec remove(server(), doc_id()) :: :ok
  def remove(server, id) when is_binary(id) do
    GenServer.call(server, {:remove, id})
  end

  @doc """
  Evaluates a Boolean `query` and returns the sorted list of matching document ids.
  """
  @spec search(server(), query()) :: [doc_id()]
  def search(server, query) do
    GenServer.call(server, {:search, query})
  end

  @doc """
  Returns up to `limit` vocabulary terms starting with `prefix`.

  The prefix is lowercased before lookup. Results are sorted by document frequency
  descending (terms occurring in more documents come first), with ties broken
  alphabetically.
  """
  @spec suggest(server(), String.t(), pos_integer()) :: [String.t()]
  def suggest(server, prefix, limit \\ 10) when is_binary(prefix) and is_integer(limit) do
    GenServer.call(server, {:suggest, prefix, limit})
  end

  @doc """
  Returns index statistics: the number of indexed documents and unique vocabulary terms.
  """
  @spec stats(server()) :: %{document_count: non_neg_integer(), term_count: non_neg_integer()}
  def stats(server) do
    GenServer.call(server, :stats)
  end

  # ----------------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------------

  @impl GenServer
  def init(stop_words) do
    {:ok, %State{stop_words: normalize_stop_words(stop_words)}}
  end

  @impl GenServer
  def handle_call({:index, id, fields}, _from, state) do
    state = do_remove(state, id)

    tokenized =
      Map.new(fields, fn {field, text} -> {field, tokenize(text, state.stop_words)} end)

    state = %State{
      state
      | documents: Map.put(state.documents, id, tokenized),
        postings: add_postings(state.postings, id, tokenized)
    }

    {:reply, :ok, state}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, do_remove(state, id)}
  end

  def handle_call({:search, query}, _from, state) do
    {:reply, state |> evaluate(query) |> Enum.sort(), state}
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    {:reply, do_suggest(state, prefix, limit), state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      document_count: map_size(state.documents),
      term_count: map_size(state.postings)
    }

    {:reply, stats, state}
  end

  # ----------------------------------------------------------------------------------
  # Tokenization
  # ----------------------------------------------------------------------------------

  @spec normalize_stop_words(term()) :: MapSet.t(String.t())
  defp normalize_stop_words(%MapSet{} = stop_words) do
    stop_words
    |> Enum.map(&String.downcase(to_string(&1)))
    |> MapSet.new()
  end

  defp normalize_stop_words(nil), do: @default_stop_words

  defp normalize_stop_words(enumerable) when is_list(enumerable) do
    normalize_stop_words(MapSet.new(enumerable))
  end

  @spec tokenize(String.t(), MapSet.t(String.t())) :: [String.t()]
  defp tokenize(text, stop_words) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split(@token_splitter, trim: true)
    |> Enum.reject(&MapSet.member?(stop_words, &1))
  end

  defp tokenize(text, stop_words), do: tokenize(to_string(text), stop_words)

  # ----------------------------------------------------------------------------------
  # Index maintenance
  # ----------------------------------------------------------------------------------

  @spec add_postings(map(), doc_id(), map()) :: map()
  defp add_postings(postings, id, tokenized) do
    Enum.reduce(tokenized, postings, fn {field, tokens}, acc ->
      tokens
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {token, position}, inner ->
        put_position(inner, token, id, field, position)
      end)
    end)
  end

  @spec put_position(map(), String.t(), doc_id(), field(), non_neg_integer()) :: map()
  defp put_position(postings, token, id, field, position) do
    Map.update(postings, token, %{id => %{field => [position]}}, fn docs ->
      Map.update(docs, id, %{field => [position]}, fn field_positions ->
        Map.update(field_positions, field, [position], &[position | &1])
      end)
    end)
  end

  @spec do_remove(State.t(), doc_id()) :: State.t()
  defp do_remove(%State{} = state, id) do
    case Map.fetch(state.documents, id) do
      :error ->
        state

      {:ok, tokenized} ->
        terms =
          tokenized
          |> Enum.flat_map(fn {_field, tokens} -> tokens end)
          |> Enum.uniq()

        postings =
          Enum.reduce(terms, state.postings, fn term, acc ->
            case Map.fetch(acc, term) do
              :error ->
                acc

              {:ok, docs} ->
                docs = Map.delete(docs, id)
                if map_size(docs) == 0, do: Map.delete(acc, term), else: Map.put(acc, term, docs)
            end
          end)

        %State{state | documents: Map.delete(state.documents, id), postings: postings}
    end
  end

  # ----------------------------------------------------------------------------------
  # Query evaluation — every branch returns a MapSet of matching document ids
  # ----------------------------------------------------------------------------------

  @spec evaluate(State.t(), query()) :: MapSet.t(doc_id())
  defp evaluate(%State{} = state, {:term, word}) do
    case tokenize(word, state.stop_words) do
      [] -> MapSet.new()
      [term | _rest] -> term_matches(state, term)
    end
  end

  defp evaluate(%State{} = state, {:phrase, text}) do
    case tokenize(text, state.stop_words) do
      [] -> MapSet.new()
      [term] -> term_matches(state, term)
      terms -> phrase_matches(state, terms)
    end
  end

  defp evaluate(%State{} = state, {:and, []}), do: all_docs(state)

  defp evaluate(%State{} = state, {:and, [first | rest]}) do
    Enum.reduce_while(rest, evaluate(state, first), fn expr, acc ->
      case MapSet.size(acc) do
        0 -> {:halt, acc}
        _ -> {:cont, MapSet.intersection(acc, evaluate(state, expr))}
      end
    end)
  end

  defp evaluate(%State{}, {:or, []}), do: MapSet.new()

  defp evaluate(%State{} = state, {:or, exprs}) when is_list(exprs) do
    Enum.reduce(exprs, MapSet.new(), fn expr, acc ->
      MapSet.union(acc, evaluate(state, expr))
    end)
  end

  defp evaluate(%State{} = state, {:not, expr}) do
    MapSet.difference(all_docs(state), evaluate(state, expr))
  end

  @spec all_docs(State.t()) :: MapSet.t(doc_id())
  defp all_docs(%State{documents: documents}) do
    documents |> Map.keys() |> MapSet.new()
  end

  @spec term_matches(State.t(), String.t()) :: MapSet.t(doc_id())
  defp term_matches(%State{postings: postings}, term) do
    postings
    |> Map.get(term, %{})
    |> Map.keys()
    |> MapSet.new()
  end

  @spec phrase_matches(State.t(), [String.t()]) :: MapSet.t(doc_id())
  defp phrase_matches(%State{postings: postings}, [first | rest] = terms) do
    candidates =
      Enum.reduce_while(rest, postings |> Map.get(first, %{}) |> Map.keys() |> MapSet.new(), fn
        _term, acc when acc == %MapSet{} ->
          {:halt, acc}

        term, acc ->
          docs = postings |> Map.get(term, %{}) |> Map.keys() |> MapSet.new()
          {:cont, MapSet.intersection(acc, docs)}
      end)

    candidates
    |> Enum.filter(&phrase_in_doc?(postings, &1, terms))
    |> MapSet.new()
  end

  @spec phrase_in_doc?(map(), doc_id(), [String.t()]) :: boolean()
  defp phrase_in_doc?(postings, id, [first | rest] = _terms) do
    first_fields = doc_field_positions(postings, first, id)

    Enum.any?(first_fields, fn {field, positions} ->
      Enum.any?(positions, fn start ->
        consecutive?(postings, id, field, rest, start + 1)
      end)
    end)
  end

  @spec consecutive?(map(), doc_id(), field(), [String.t()], non_neg_integer()) :: boolean()
  defp consecutive?(_postings, _id, _field, [], _expected), do: true

  defp consecutive?(postings, id, field, [term | rest], expected) do
    positions =
      postings
      |> doc_field_positions(term, id)
      |> Map.get(field, [])

    if expected in positions do
      consecutive?(postings, id, field, rest, expected + 1)
    else
      false
    end
  end

  @spec doc_field_positions(map(), String.t(), doc_id()) :: %{
          optional(field()) => [non_neg_integer()]
        }
  defp doc_field_positions(postings, term, id) do
    postings
    |> Map.get(term, %{})
    |> Map.get(id, %{})
  end

  # ----------------------------------------------------------------------------------
  # Suggestions
  # ----------------------------------------------------------------------------------

  @spec do_suggest(State.t(), String.t(), integer()) :: [String.t()]
  defp do_suggest(_state, _prefix, limit) when limit <= 0, do: []

  defp do_suggest(%State{postings: postings}, prefix, limit) do
    prefix = String.downcase(prefix)

    postings
    |> Enum.filter(fn {term, _docs} -> String.starts_with?(term, prefix) end)
    |> Enum.map(fn {term, docs} -> {term, map_size(docs)} end)
    |> Enum.sort_by(fn {term, frequency} -> {-frequency, term} end)
    |> Enum.take(limit)
    |> Enum.map(fn {term, _frequency} -> term end)
  end
end