Implement the `handle_call/3` GenServer callback for the `InvertedIndex` module. This is a single callback function made up of several clauses — one per synchronous request the server accepts. The state is a map with the shape:

```
%{
  stop_words: MapSet.t(),
  docs: %{doc_id => %{field_name => [token, ...]}},        # raw tokens per field
  postings: %{term => %{doc_id => %{field_name => count}}}, # inverted index
  doc_freq: %{term => pos_integer}                          # # docs containing term
}
```

Implement the following clauses. Each must return a `{:reply, reply, new_state}` tuple.

**`{:index, id, fields, opts}`** — Index (or re-index) a document. First remove any existing version of `id` via `do_remove/2` so counts stay consistent. Read the `:stem` flag from `opts` (default `false`). Tokenize every field's text with `tokenize/3` (using `state.stop_words` and the stem flag), building a map of `field => [token, ...]`. From those tokens, build per-term, per-field counts using `Enum.frequencies/1`, producing `%{term => %{field => count}}`. Merge this into `state.postings` (nesting the document under each term) and bump `state.doc_freq` by 1 for each term the document contains. Store the tokenized fields under `id` in `state.docs`. Reply `:ok` with the updated state.

**`{:remove, id}`** — Remove the document via `do_remove/2` and reply `:ok` with the resulting state.

**`{:search, query, opts}`** — Read `:stem` (default `false`), `:boosts` (default `%{}`), and `:limit` (default `nil`) from `opts`. Tokenize the query with `tokenize/3`. If the index is empty (`map_size(state.docs) == 0`) or no query terms survive tokenization, reply with `[]`. Otherwise, for each unique query term precompute its IDF as `:math.log(total_docs / doc_freq)` (or `0.0` when the term has no document frequency). Accumulate a per-document score: for each term, look up its postings and, for every document/field, compute `tf = count / total_tokens_in_field` (where `total_tokens_in_field` is the length of that field's token list in `state.docs`), multiply by the term's IDF and the field's boost (`Map.get(boosts, field, 1)`), and sum across fields and terms per document. Turn the score map into a list of `%{id: doc_id, score: score}`, sort by score descending, apply `:limit` with `Enum.take/2` when present, and reply with the list.

**`{:suggest, prefix, limit}`** — Downcase the prefix, filter `state.doc_freq` to terms starting with it, sort by document frequency descending, take `limit`, map to the bare term strings, and reply with that list.

**`:stats`** — Reply with `%{document_count: map_size(state.docs), term_count: map_size(state.doc_freq)}`.

All clauses leave the state unchanged except `{:index, ...}` and `{:remove, ...}`.

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
    # TODO
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