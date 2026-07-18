# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule InvertedIndex do
  use GenServer

  @token_regex ~r/[^a-z0-9]+/

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

  # ── Public API ──────────────────────────────────────────────────────────

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def index(server, id, fields) do
    GenServer.call(server, {:index, id, fields})
  end

  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end

  def search(server, query, opts \\ []) do
    GenServer.call(server, {:search, query, opts})
  end

  def suggest(server, prefix, limit \\ 10) do
    GenServer.call(server, {:suggest, prefix, limit})
  end

  def stats(server) do
    GenServer.call(server, :stats)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    state = %{
      stop_words: Keyword.get(opts, :stop_words, @default_stop_words),
      k1: Keyword.get(opts, :k1, 1.2),
      b: Keyword.get(opts, :b, 0.75),
      docs: %{},
      postings: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:index, id, fields}, _from, state) do
    state = do_remove(state, id)
    {terms, lengths} = build_document(fields, state.stop_words)
    doc = %{terms: terms, lengths: lengths}
    postings = add_postings(state.postings, id, terms)
    {:reply, :ok, %{state | docs: Map.put(state.docs, id, doc), postings: postings}}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, do_remove(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    boosts = Keyword.get(opts, :boosts, %{})
    limit = Keyword.get(opts, :limit)
    query_terms = query |> tokenize(state.stop_words) |> Enum.uniq()
    results = do_search(state, query_terms, boosts)
    results = if limit, do: Enum.take(results, limit), else: results
    {:reply, results, state}
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    prefix = String.downcase(prefix)

    terms =
      state.postings
      |> Enum.filter(fn {term, _ids} -> String.starts_with?(term, prefix) end)
      |> Enum.sort_by(fn {_term, ids} -> MapSet.size(ids) end, :desc)
      |> Enum.take(limit)
      |> Enum.map(fn {term, _ids} -> term end)

    {:reply, terms, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      document_count: map_size(state.docs),
      term_count: map_size(state.postings)
    }

    {:reply, stats, state}
  end

  # ── Indexing helpers ────────────────────────────────────────────────────

  defp build_document(fields, stop_words) do
    Enum.reduce(fields, {%{}, %{}}, fn {field, text}, {terms_acc, lengths_acc} ->
      tokens = tokenize(text, stop_words)

      {Map.put(terms_acc, field, count_tokens(tokens)),
       Map.put(lengths_acc, field, length(tokens))}
    end)
  end

  defp count_tokens(tokens) do
    Enum.reduce(tokens, %{}, fn token, acc ->
      Map.update(acc, token, 1, &(&1 + 1))
    end)
  end

  defp tokenize(text, stop_words) do
    text
    |> String.downcase()
    |> then(&Regex.split(@token_regex, &1, trim: true))
    |> Enum.reject(&MapSet.member?(stop_words, &1))
  end

  defp doc_terms(terms) do
    terms
    |> Map.values()
    |> Enum.reduce(MapSet.new(), fn tmap, acc ->
      MapSet.union(acc, MapSet.new(Map.keys(tmap)))
    end)
  end

  defp add_postings(postings, id, terms) do
    Enum.reduce(doc_terms(terms), postings, fn t, acc ->
      Map.update(acc, t, MapSet.new([id]), &MapSet.put(&1, id))
    end)
  end

  defp do_remove(state, id) do
    case Map.get(state.docs, id) do
      nil ->
        state

      doc ->
        postings = remove_postings(state.postings, id, doc.terms)
        %{state | docs: Map.delete(state.docs, id), postings: postings}
    end
  end

  defp remove_postings(postings, id, terms) do
    Enum.reduce(doc_terms(terms), postings, fn t, acc ->
      case Map.get(acc, t) do
        nil ->
          acc

        ids ->
          ids = MapSet.delete(ids, id)
          if MapSet.size(ids) == 0, do: Map.delete(acc, t), else: Map.put(acc, t, ids)
      end
    end)
  end

  # ── Search / scoring helpers ────────────────────────────────────────────

  defp do_search(_state, [], _boosts), do: []

  defp do_search(state, query_terms, boosts) do
    n = map_size(state.docs)
    avgdl = average_length(state.docs, n, boosts)

    query_terms
    |> candidates(state.postings)
    |> Enum.map(fn id ->
      doc = Map.fetch!(state.docs, id)

      score =
        score_doc(doc, query_terms, state.postings, n, avgdl, state.k1, state.b, boosts)

      %{id: id, score: score}
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp candidates(query_terms, postings) do
    Enum.reduce(query_terms, MapSet.new(), fn t, acc ->
      case Map.get(postings, t) do
        nil -> acc
        ids -> MapSet.union(acc, ids)
      end
    end)
  end

  defp score_doc(doc, query_terms, postings, n, avgdl, k1, b, boosts) do
    wlen = weighted_length(doc, boosts)
    ratio = if avgdl == +0.0, do: +0.0, else: wlen / avgdl

    Enum.reduce(query_terms, +0.0, fn t, acc ->
      f = term_frequency(doc, t, boosts)

      if f == +0.0 do
        acc
      else
        df = postings |> Map.get(t, MapSet.new()) |> MapSet.size()
        idf = :math.log(1 + (n - df + 0.5) / (df + 0.5))
        denom = f + k1 * (1 - b + b * ratio)
        acc + idf * (f * (k1 + 1)) / denom
      end
    end)
  end

  defp term_frequency(doc, term, boosts) do
    Enum.reduce(doc.terms, +0.0, fn {field, tmap}, acc ->
      acc + Map.get(tmap, term, 0) * boost(field, boosts)
    end)
  end

  defp weighted_length(doc, boosts) do
    Enum.reduce(doc.lengths, +0.0, fn {field, len}, acc ->
      acc + len * boost(field, boosts)
    end)
  end

  defp average_length(_docs, 0, _boosts), do: +0.0

  defp average_length(docs, n, boosts) do
    total =
      Enum.reduce(docs, +0.0, fn {_id, doc}, acc ->
        acc + weighted_length(doc, boosts)
      end)

    total / n
  end

  defp boost(field, boosts), do: Map.get(boosts, field, 1)
end
```
