# Ranking — implement `score/2`

Implement the public `score/2` function for the `Ranking` module.

`score(item, opts \\ [])` computes the Reddit-style "hot" score of a single
`item` (a map with atom keys `:upvotes`, `:downvotes`, and `:created_at`) and
returns it as a float.

Start by reading the two options, both optional:

- `:epoch` — an integer Unix timestamp (seconds) used as the time origin,
  defaulting to `@default_epoch`.
- `:divisor` — a positive number weighting elapsed time against an
  order-of-magnitude of votes, defaulting to `@default_divisor`.

Fetch `:upvotes`, `:downvotes`, and `:created_at` from `item` with
`Map.fetch!/2` (a missing key should raise). Then compute the score exactly as
follows:

- `net_votes = upvotes - downvotes` (may be negative).
- `order = :math.log10(max(abs(net_votes), 1))`, so zero/one net votes yield
  `0.0` and vote contribution grows logarithmically.
- `sign` is `1` when `net_votes > 0`, `-1` when `net_votes < 0`, and `0` when
  `net_votes == 0` (use a `cond`).
- `seconds = created_at - epoch` (may be negative).

Finally return `Float.round(sign * order + seconds / divisor, 7)` — the blended
score rounded to 7 decimal places.

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
    # TODO
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