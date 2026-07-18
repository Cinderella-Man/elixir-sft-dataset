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
  @default_epoch 1_134_028_003
  @default_divisor 45_000

  def score(item, opts \\ []) when is_map(item) and is_list(opts) do
    epoch = Keyword.get(opts, :epoch, @default_epoch)
    divisor = Keyword.get(opts, :divisor, @default_divisor)

    upvotes = Map.fetch!(item, :upvotes)
    downvotes = Map.fetch!(item, :downvotes)
    created_at = Map.fetch!(item, :created_at)

    net_votes = upvotes - downvotes
    order = :math.log10(max(abs(net_votes), 1))

    sign =
      cond do
        net_votes > 0 -> 1
        net_votes < 0 -> -1
        true -> 0
      end

    seconds = created_at - epoch

    Float.round(sign * order + seconds / divisor, 7)
  end

  def rank(items, opts \\ []) when is_list(items) and is_list(opts) do
    items
    |> Enum.map(fn item -> {score(item, opts), Map.fetch!(item, :created_at), item} end)
    |> Enum.sort(fn {score_a, created_a, _a}, {score_b, created_b, _b} ->
      cond do
        score_a > score_b -> true
        score_a < score_b -> false
        created_a > created_b -> true
        created_a < created_b -> false
        true -> true
      end
    end)
    |> Enum.map(fn {_score, _created_at, item} -> item end)
  end
end
```
