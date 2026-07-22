defmodule InvertedIndex do
  @moduledoc """
  A small in-memory full-text search engine backed by a `GenServer`.

  Documents are maps of field names to text. Text is tokenized by lowercasing,
  splitting on any non-alphanumeric run, and dropping stop words. An optional
  suffix-stripping stemmer can be enabled per call via `opts[:stem]`.

  Searching ranks documents with TF-IDF:

      tf(term, doc, field) = count of term in field / total tokens in field
      idf(term)           = log(total documents / documents containing term)

  A document's score for a term is the sum over its fields of
  `tf * idf * boost`, where boosts come from `opts[:boosts]` (default `1`).
  Scores for multiple query terms are summed.

  The index also exposes prefix completion over its vocabulary via `suggest/3`
  and basic counters via `stats/1`.
  """

  use GenServer

  @default_stop_words MapSet.new(~w(
    the a an is are was were in on at to of and or it this that for with as by
    not be has had have do does did but if from
  ))

  @token_splitter ~r/[^a-z0-9]+/

  @typedoc "A search result entry."
  @type result :: %{id: String.t(), score: float()}

  defmodule State do
    @moduledoc false

    defstruct stop_words: MapSet.new(),
              docs: %{},
              postings: %{}

    @type t :: %__MODULE__{
            stop_words: MapSet.t(String.t()),
            docs: %{optional(String.t()) => %{optional(atom() | String.t()) => pos_integer()}},
            postings: %{
              optional(String.t()) => %{
                optional(String.t()) => %{optional(atom() | String.t()) => pos_integer()}
              }
            }
          }
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the index process.

  Options:

    * `:name` - optional process name for registration.
    * `:stop_words` - a `MapSet` of words removed during tokenization. Defaults
      to a small built-in English stop word set.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Indexes `fields` (a map of field name to text) under the document `id`.

  Re-indexing an existing `id` fully replaces the previous version. Pass
  `stem: true` in `opts` to stem tokens before storing them.
  """
  @spec index(GenServer.server(), String.t(), map(), keyword()) :: :ok
  def index(server, id, fields, opts \\ []) do
    GenServer.call(server, {:index, id, fields, opts})
  end

  @doc """
  Removes the document `id` from the index. Unknown ids are ignored.
  """
  @spec remove(GenServer.server(), String.t()) :: :ok
  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end

  @doc """
  Searches the index and returns `%{id: id, score: score}` maps, best first.

  Options:

    * `:boosts` - map of field name to multiplier, e.g. `%{title: 3, body: 1}`.
    * `:limit` - maximum number of results returned.
    * `:stem` - stem query terms before lookup (must match how documents were
      indexed).
  """
  @spec search(GenServer.server(), String.t(), keyword()) :: [result()]
  def search(server, query, opts \\ []) do
    GenServer.call(server, {:search, query, opts})
  end

  @doc """
  Returns up to `limit` vocabulary terms starting with `prefix`, ordered by
  document frequency descending (ties broken alphabetically).
  """
  @spec suggest(GenServer.server(), String.t(), pos_integer()) :: [String.t()]
  def suggest(server, prefix, limit \\ 10) do
    GenServer.call(server, {:suggest, prefix, limit})
  end

  @doc """
  Returns `%{document_count: integer, term_count: integer}` for the index.
  """
  @spec stats(GenServer.server()) :: %{document_count: non_neg_integer(), term_count: non_neg_integer()}
  def stats(server) do
    GenServer.call(server, :stats)
  end

  @doc """
  Tokenizes `text` with the given stop word set, optionally stemming.

  Exposed mainly for testing and for callers that want to preview the exact
  token stream the index will store.
  """
  @spec tokenize(String.t(), MapSet.t(String.t()), boolean()) :: [String.t()]
  def tokenize(text, stop_words \\ @default_stop_words, stem? \\ false) do
    text
    |> to_string()
    |> String.downcase()
    |> String.split(@token_splitter, trim: true)
    |> Enum.reject(&MapSet.member?(stop_words, &1))
    |> Enum.map(fn token -> if stem?, do: stem(token), else: token end)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Applies the built-in suffix-stripping stemmer to a single lowercase `word`.
  """
  @spec stem(String.t()) :: String.t()
  def stem(word) do
    word
    |> strip_suffix()
    |> collapse_double_consonant()
  end

  @doc """
  Returns the built-in default stop word set.
  """
  @spec default_stop_words() :: MapSet.t(String.t())
  def default_stop_words, do: @default_stop_words

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    stop_words =
      case Keyword.get(opts, :stop_words) do
        nil -> @default_stop_words
        %MapSet{} = set -> set
        list when is_list(list) -> MapSet.new(list)
      end

    {:ok, %State{stop_words: stop_words}}
  end

  @impl GenServer
  def handle_call({:index, id, fields, opts}, _from, state) do
    stem? = Keyword.get(opts, :stem, false)
    state = purge(state, id)

    field_tokens =
      Enum.map(fields, fn {field, text} ->
        {field, tokenize(text, state.stop_words, stem?)}
      end)

    lengths =
      for {field, tokens} <- field_tokens, tokens != [], into: %{} do
        {field, length(tokens)}
      end

    postings =
      Enum.reduce(field_tokens, state.postings, fn {field, tokens}, acc ->
        tokens
        |> Enum.frequencies()
        |> Enum.reduce(acc, fn {term, count}, acc2 ->
          by_doc = Map.get(acc2, term, %{})
          by_field = by_doc |> Map.get(id, %{}) |> Map.put(field, count)
          Map.put(acc2, term, Map.put(by_doc, id, by_field))
        end)
      end)

    {:reply, :ok, %State{state | docs: Map.put(state.docs, id, lengths), postings: postings}}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, purge(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    stem? = Keyword.get(opts, :stem, false)
    boosts = Keyword.get(opts, :boosts, %{})
    limit = Keyword.get(opts, :limit)
    terms = query |> tokenize(state.stop_words, stem?) |> Enum.uniq()

    results =
      terms
      |> Enum.reduce(%{}, fn term, acc -> accumulate(acc, term, state, boosts) end)
      |> Enum.map(fn {id, score} -> %{id: id, score: score} end)
      |> Enum.sort_by(fn %{id: id, score: score} -> {-score, id} end)
      |> maybe_limit(limit)

    {:reply, results, state}
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    prefix = prefix |> to_string() |> String.downcase()

    terms =
      state.postings
      |> Enum.filter(fn {term, _docs} -> String.starts_with?(term, prefix) end)
      |> Enum.sort_by(fn {term, docs} -> {-map_size(docs), term} end)
      |> Enum.take(max(limit, 0))
      |> Enum.map(&elem(&1, 0))

    {:reply, terms, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{document_count: map_size(state.docs), term_count: map_size(state.postings)}
    {:reply, stats, state}
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  @spec accumulate(map(), String.t(), State.t(), map()) :: map()
  defp accumulate(acc, term, state, boosts) do
    doc_postings = Map.get(state.postings, term, %{})
    doc_freq = map_size(doc_postings)
    total_docs = map_size(state.docs)

    if doc_freq == 0 or total_docs == 0 do
      acc
    else
      idf = :math.log(total_docs / doc_freq)

      Enum.reduce(doc_postings, acc, fn {id, by_field}, acc2 ->
        lengths = Map.get(state.docs, id, %{})
        score = term_score(by_field, lengths, idf, boosts)
        Map.update(acc2, id, score, &(&1 + score))
      end)
    end
  end

  @spec term_score(map(), map(), float(), map()) :: float()
  defp term_score(by_field, lengths, idf, boosts) do
    Enum.reduce(by_field, 0.0, fn {field, count}, sum ->
      case Map.get(lengths, field, 0) do
        0 ->
          sum

        total ->
          boost = boosts |> Map.get(field, 1) |> :erlang.float()
          sum + count / total * idf * boost
      end
    end)
  end

  @spec maybe_limit([result()], nil | integer()) :: [result()]
  defp maybe_limit(results, nil), do: results
  defp maybe_limit(_results, limit) when limit <= 0, do: []
  defp maybe_limit(results, limit), do: Enum.take(results, limit)

  @spec purge(State.t(), String.t()) :: State.t()
  defp purge(%State{} = state, id) do
    if Map.has_key?(state.docs, id) do
      postings =
        Enum.reduce(state.postings, %{}, fn {term, by_doc}, acc ->
          case Map.delete(by_doc, id) do
            empty when map_size(empty) == 0 -> acc
            rest -> Map.put(acc, term, rest)
          end
        end)

      %State{state | docs: Map.delete(state.docs, id), postings: postings}
    else
      state
    end
  end

  @suffixes [{"tion", "t"}, {"ment", ""}, {"ing", ""}, {"ed", ""}, {"ly", ""}, {"s", ""}]

  @spec strip_suffix(String.t()) :: String.t()
  defp strip_suffix(word) do
    Enum.reduce_while(@suffixes, word, fn {suffix, replacement}, acc ->
      stripped = strip_one(acc, suffix, replacement)
      if stripped == acc, do: {:cont, acc}, else: {:halt, stripped}
    end)
  end

  @spec strip_one(String.t(), String.t(), String.t()) :: String.t()
  defp strip_one(word, suffix, replacement) do
    if String.ends_with?(word, suffix) do
      base = binary_part(word, 0, byte_size(word) - byte_size(suffix))
      candidate = base <> replacement
      if String.length(candidate) >= 3, do: candidate, else: word
    else
      word
    end
  end

  @vowels ["a", "e", "i", "o", "u", "y"]

  @spec collapse_double_consonant(String.t()) :: String.t()
  defp collapse_double_consonant(word) do
    with true <- String.length(word) >= 3,
         [last, prev] <- word |> String.last() |> then(&[&1, second_last(word)]),
         true <- last == prev,
         false <- last in @vowels do
      binary_part(word, 0, byte_size(word) - byte_size(last))
    else
      _ -> word
    end
  end

  @spec second_last(String.t()) :: String.t()
  defp second_last(word) do
    word |> String.graphemes() |> Enum.at(-2, "")
  end
end