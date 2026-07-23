# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

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
