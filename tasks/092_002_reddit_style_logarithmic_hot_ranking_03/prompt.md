# Implement `rank/2`

You are given the complete `Ranking` module below, but the body of the public
`rank/2` function has been removed and replaced with `# TODO`. Implement it.

`Ranking.rank(items, opts \\ [])` takes a list of item maps and returns the same
item maps sorted by their hot score, **highest first**. It must thread the same
`opts` through to `score/2` when computing each item's score, and it must return
the item maps **unchanged** (never mutate them).

Sorting is by a compound key. Ties are broken, in order, by:

1. **Higher score first** — an item with a larger `score/2` value comes before one
   with a smaller value.
2. **More recent first** — if two items have equal scores, the one with the larger
   `:created_at` comes first.
3. **Stable** — if both the score and `:created_at` are equal, preserve the items'
   original relative order.

A reliable approach is to decorate each item with a tuple of
`{score, created_at, item}`, sort by a comparator implementing the rules above,
then strip the decoration to recover the item maps. Because the final comparator
branch returns `true` when both keys are equal, `Enum.sort/2` preserves the
original order for genuine ties.

`rank/2` must handle the empty list and a single-item list gracefully, and it is
guarded with `when is_list(items) and is_list(opts)`.

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
  @spec rank([map()], keyword()) :: [map()]
  def rank(items, opts \\ []) when is_list(items) and is_list(opts) do
    # TODO
  end
end
```