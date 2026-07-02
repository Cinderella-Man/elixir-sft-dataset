# Fill in the middle — implement `Ranking.rank/2`

The `Ranking` module below is complete except for the body of the public
`rank/2` function, which has been replaced with `# TODO`. Implement `rank/2`.

## What `rank/2` must do

`Ranking.rank(items, opts \\ [])` takes a list of item maps and returns those
same item maps sorted by their Wilson lower-bound score, **highest first**.

- The same `opts` must be threaded through to `score/2` so scoring respects
  options such as `:z`.
- The item maps must be returned **unchanged** (never mutated); only their
  order changes.
- Sorting must be **stable** and apply these tie-breaks, in order:
  1. Higher score comes first.
  2. If scores are equal, the item with more total votes
     (`upvotes + downvotes`) comes first.
  3. If both are equal, preserve the items' original relative order.
- It must handle the empty list and a single-item list gracefully.

A clean approach: decorate each item with a `{score, total_votes, item}` tuple,
sort by a comparator implementing the rules above, then strip the decoration to
return just the items.

```elixir
defmodule Ranking do
  @moduledoc """
  A Wilson lower-bound confidence ranking for content items.

  Each item is a plain map with atom keys:

    * `:upvotes` — non-negative integer
    * `:downvotes` — non-negative integer

  Items may carry any number of additional keys (such as an `:id`); those are
  ignored and items are never mutated.

  The score is the lower bound of the Wilson score confidence interval for the
  proportion of upvotes. It rewards a high upvote ratio while penalizing small
  sample sizes, so a single lucky upvote cannot beat a well-established item.
  """

  @default_z 1.96

  @doc """
  Computes the Wilson lower bound of an `item` as a float.

  ## Options

    * `:z` — the z-score for the desired confidence level. Defaults to `1.96`
      (≈ 95%). A larger `z` widens the interval and lowers the score.
  """
  @spec score(map(), keyword()) :: float()
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

  @doc """
  Returns `items` sorted by score, highest first.

  The same `opts` are passed through to `score/2`.

  Ties are broken, in order, by:

    1. Higher score first.
    2. More total votes (`upvotes + downvotes`) first.
    3. Original relative order (stable sort).
  """
  @spec rank([map()], keyword()) :: [map()]
  def rank(items, opts \\ []) when is_list(items) and is_list(opts) do
    # TODO
  end
end
```