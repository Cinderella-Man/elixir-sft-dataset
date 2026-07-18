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
defmodule Ranking do
  @default_min_votes 25

  def score(item, opts \\ []) when is_map(item) and is_list(opts) do
    m = Keyword.get(opts, :min_votes, @default_min_votes)
    c = Keyword.get(opts, :mean, 0.0)

    r = Map.fetch!(item, :rating)
    v = Map.fetch!(item, :vote_count)

    denom = v + m

    if denom == 0 do
      1.0 * c
    else
      v / denom * r + m / denom * c
    end
  end

  def rank(items, opts \\ []) when is_list(items) and is_list(opts) do
    opts =
      if Keyword.has_key?(opts, :mean) do
        opts
      else
        Keyword.put(opts, :mean, corpus_mean(items))
      end

    items
    |> Enum.map(fn item -> {score(item, opts), Map.fetch!(item, :vote_count), item} end)
    |> Enum.sort(fn {score_a, votes_a, _a}, {score_b, votes_b, _b} ->
      cond do
        score_a > score_b -> true
        score_a < score_b -> false
        votes_a > votes_b -> true
        votes_a < votes_b -> false
        true -> true
      end
    end)
    |> Enum.map(fn {_score, _votes, item} -> item end)
  end

  defp corpus_mean([]), do: 0.0

  defp corpus_mean(items) do
    ratings = Enum.map(items, &Map.fetch!(&1, :rating))
    Enum.sum(ratings) / length(ratings)
  end
end
```
