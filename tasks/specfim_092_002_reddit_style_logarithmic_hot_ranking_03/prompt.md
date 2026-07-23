# Reconstruct the missing typespec

In the otherwise-complete module below, the `@spec` for
`rank/2` has been removed; `# TODO: @spec` holds its place.
Write that one attribute — a `@spec` for `rank/2` faithful to
the arguments, guards, and every return shape the code can actually
produce. Nothing else changes.

## The module with the `@spec` for `rank/2` missing

```elixir
defmodule Ranking do
  @moduledoc """
  A Reddit-style logarithmic "hot" ranking for content items.

  Each item is a plain map with atom keys:

    * `:upvotes` — non-negative integer
    * `:downvotes` — non-negative integer
    * `:created_at` — integer Unix timestamp in seconds

  Items may carry any number of additional keys (such as an `:id`); those are
  ignored and items are never mutated.

  The hot score blends a logarithmic vote term with a linear time term:

      net_votes = upvotes - downvotes
      order     = log10(max(abs(net_votes), 1))
      sign      = 1 | -1 | 0   (per the sign of net_votes)
      seconds   = created_at - epoch
      score     = round(sign * order + seconds / divisor, 7)
  """

  @default_epoch 1_134_028_003
  @default_divisor 45_000

  @doc """
  Computes the hot score of a single `item` as a float.

  ## Options

    * `:epoch` — integer Unix timestamp (seconds) used as the time origin.
      Defaults to `1_134_028_003`.
    * `:divisor` — a positive number controlling the weight of elapsed time
      relative to an order-of-magnitude of votes. Defaults to `45_000`.
  """
  @spec score(map(), keyword()) :: float()
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

  @doc """
  Returns `items` sorted by score, highest first.

  The same `opts` are passed through to `score/2`.

  Ties are broken, in order, by:

    1. Higher score first.
    2. More recently created item (larger `:created_at`) first.
    3. Original relative order (stable sort).
  """
  # TODO: @spec
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

Reply with the `@spec` attribute alone, however many lines it needs —
not the module.
