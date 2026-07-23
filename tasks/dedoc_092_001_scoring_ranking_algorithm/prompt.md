# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule Ranking do
  @default_weights %{votes: 1.0, recency: 1.0, engagement: 1.0}
  @default_half_life_hours 12
  @seconds_per_hour 3600

  def score(item, opts \\ []) when is_map(item) and is_list(opts) do
    now = Keyword.get(opts, :now, System.os_time(:second))
    half_life_hours = Keyword.get(opts, :half_life_hours, @default_half_life_hours)
    weights = Map.merge(@default_weights, Keyword.get(opts, :weights, %{}))

    upvotes = Map.fetch!(item, :upvotes)
    downvotes = Map.fetch!(item, :downvotes)
    created_at = Map.fetch!(item, :created_at)
    view_count = Map.fetch!(item, :view_count)
    comment_count = Map.fetch!(item, :comment_count)

    net_votes = upvotes - downvotes

    age_hours = max(now - created_at, 0) / @seconds_per_hour
    recency = :math.pow(2, -age_hours / half_life_hours)

    engagement = if view_count > 0, do: comment_count / view_count, else: 0.0

    weights.votes * net_votes +
      weights.recency * recency +
      weights.engagement * engagement
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
        # Equal score and created_at: keep original order (stable sort).
        true -> true
      end
    end)
    |> Enum.map(fn {_score, _created_at, item} -> item end)
  end
end
```
