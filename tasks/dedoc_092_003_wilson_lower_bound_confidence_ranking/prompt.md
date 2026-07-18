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
