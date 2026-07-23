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
  @default_z 1.96

  def score(item, opts \\ []) when is_map(item) and is_list(opts) do
    z = Keyword.get(opts, :z, @default_z)

    upvotes = Map.fetch!(item, :upvotes)
    downvotes = Map.fetch!(item, :downvotes)
    n = upvotes + downvotes

    if n == 0 do
      0.0
    else
      p = upvotes / n
      z2 = z * z

      denominator = 1 + z2 / n
      center = p + z2 / (2 * n)
      margin = z * :math.sqrt((p * (1 - p) + z2 / (4 * n)) / n)

      (center - margin) / denominator
    end
  end

  def rank(items, opts \\ []) when is_list(items) and is_list(opts) do
    items
    |> Enum.map(fn item ->
      total = Map.fetch!(item, :upvotes) + Map.fetch!(item, :downvotes)
      {score(item, opts), total, item}
    end)
    |> Enum.sort(fn {score_a, total_a, _a}, {score_b, total_b, _b} ->
      cond do
        score_a > score_b -> true
        score_a < score_b -> false
        total_a > total_b -> true
        total_a < total_b -> false
        true -> true
      end
    end)
    |> Enum.map(fn {_score, _total, item} -> item end)
  end
end
```
