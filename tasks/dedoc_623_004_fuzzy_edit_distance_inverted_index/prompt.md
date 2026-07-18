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
defmodule FuzzyIndex do
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

  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  def index(server, id, text) do
    GenServer.call(server, {:index, id, text})
  end

  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end

  def search(server, query, opts \\ []) do
    GenServer.call(server, {:search, query, opts})
  end

  def terms_like(server, term, max_distance \\ 1) do
    GenServer.call(server, {:terms_like, term, max_distance})
  end

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

  defp apply_limit(results, nil), do: results
  defp apply_limit(results, limit) when is_integer(limit), do: Enum.take(results, limit)

  defp tokenize(text, stop_words) do
    text
    |> String.downcase()
    |> then(fn lowered -> Regex.split(~r/[^a-z0-9]+/, lowered, trim: true) end)
    |> Enum.reject(fn token -> MapSet.member?(stop_words, token) end)
  end

  defp token_counts(tokens) do
    Enum.reduce(tokens, %{}, fn token, acc ->
      Map.update(acc, token, 1, &(&1 + 1))
    end)
  end

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
