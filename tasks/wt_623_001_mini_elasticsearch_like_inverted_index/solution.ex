defmodule InvertedIndex do
  @moduledoc """
  A full-text search engine backed by a GenServer, supporting TF-IDF scoring,
  field-level boosting, prefix-based term suggestion, and optional suffix-stripping stemming.
  """

  use GenServer

  @default_stop_words MapSet.new([
    "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to",
    "of", "and", "or", "it", "this", "that", "for", "with", "as", "by",
    "not", "be", "has", "had", "have", "do", "does", "did", "but", "if", "from"
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
