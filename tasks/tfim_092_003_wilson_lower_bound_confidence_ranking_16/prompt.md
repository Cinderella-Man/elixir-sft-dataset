# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule RankingTest do
  use ExUnit.Case, async: false

  defp item(overrides) do
    base = %{id: nil, upvotes: 0, downvotes: 0}
    Map.merge(base, Map.new(overrides))
  end

  defp ids(items), do: Enum.map(items, & &1.id)

  # -------------------------------------------------------
  # score/2 — exact formula (against known Wilson values)
  # -------------------------------------------------------

  test "1 upvote / 0 downvotes matches the known Wilson lower bound" do
    assert_in_delta Ranking.score(item(upvotes: 1, downvotes: 0)), 0.2065432, 1.0e-6
  end

  test "10 upvotes / 0 downvotes matches the known Wilson lower bound" do
    assert_in_delta Ranking.score(item(upvotes: 10, downvotes: 0)), 0.7224598, 1.0e-6
  end

  test "score is a float" do
    assert is_float(Ranking.score(item(upvotes: 3, downvotes: 1)))
  end

  test "no votes scores exactly 0.0 and never raises" do
    assert Ranking.score(item(upvotes: 0, downvotes: 0)) === 0.0
  end

  # -------------------------------------------------------
  # Behavioral properties
  # -------------------------------------------------------

  test "more votes at the same ratio raise the score" do
    small = Ranking.score(item(upvotes: 1, downvotes: 0))
    big = Ranking.score(item(upvotes: 10, downvotes: 0))
    assert big > small
  end

  test "adding a downvote lowers the score" do
    clean = Ranking.score(item(upvotes: 10, downvotes: 0))
    dinged = Ranking.score(item(upvotes: 10, downvotes: 1))
    assert dinged < clean
  end

  test "proven quality beats uncertain perfection" do
    perfect_tiny = Ranking.score(item(upvotes: 1, downvotes: 0))
    strong_large = Ranking.score(item(upvotes: 50, downvotes: 10))
    assert strong_large > perfect_tiny
  end

  test "larger sample with a higher ratio wins convincingly" do
    a = Ranking.score(item(upvotes: 100, downvotes: 10))
    b = Ranking.score(item(upvotes: 5, downvotes: 1))
    assert a > b
  end

  test "a higher z (more confidence demanded) lowers the score" do
    it = item(upvotes: 10, downvotes: 2)
    s95 = Ranking.score(it, z: 1.96)
    s99 = Ranking.score(it, z: 2.58)
    assert s99 < s95
  end

  # -------------------------------------------------------
  # rank/2 — ordering
  # -------------------------------------------------------

  test "rank sorts items by score descending" do
    a = item(id: :a, upvotes: 100, downvotes: 5)
    b = item(id: :b, upvotes: 10, downvotes: 1)
    c = item(id: :c, upvotes: 1, downvotes: 0)
    d = item(id: :d, upvotes: 2, downvotes: 20)

    assert ids(Ranking.rank([c, d, a, b])) == [:a, :b, :c, :d]
  end

  test "rank returns the item maps unchanged" do
    a = item(id: :a, upvotes: 5, downvotes: 2)
    b = item(id: :b, upvotes: 9, downvotes: 0)
    ranked = Ranking.rank([a, b])
    assert Enum.sort_by(ranked, & &1.id) == Enum.sort_by([a, b], & &1.id)
  end

  test "identical items preserve original input order (stable)" do
    x = item(id: :x, upvotes: 7, downvotes: 1)
    y = item(id: :y, upvotes: 7, downvotes: 1)
    z = item(id: :z, upvotes: 7, downvotes: 1)

    assert ids(Ranking.rank([x, y, z])) == [:x, :y, :z]
    assert ids(Ranking.rank([z, x, y])) == [:z, :x, :y]
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "rank handles the empty list" do
    assert Ranking.rank([]) == []
  end

  test "rank handles a single item" do
    only = item(id: :only, upvotes: 3, downvotes: 1)
    assert Ranking.rank([only]) == [only]
  end

  test "omitting :z is identical to passing z: 1.96 for both score and rank" do
    # TODO
  end

  # -------------------------------------------------------
  # rank/2 — opts threading and the total-votes tiebreak
  # -------------------------------------------------------

  test "rank threads a non-default :z through, reordering the results" do
    tiny = item(id: :tiny, upvotes: 1, downvotes: 0)
    small = item(id: :small, upvotes: 5, downvotes: 0)
    big = item(id: :big, upvotes: 50, downvotes: 10)

    # At the default z the wide interval punishes the small samples, so the
    # large, well-supported item leads. A narrow interval (z: 0.25) barely
    # penalizes uncertainty, so the perfect-ratio items lead instead.
    assert ids(Ranking.rank([tiny, small, big])) == [:big, :small, :tiny]
    assert ids(Ranking.rank([tiny, small, big], z: 0.25)) == [:small, :tiny, :big]
  end

  test "equal scores are broken by more total votes first" do
    none = item(id: :none, upvotes: 0, downvotes: 0)
    two = item(id: :two, upvotes: 0, downvotes: 2)
    eight = item(id: :eight, upvotes: 0, downvotes: 8)

    # With no upvotes the centre and the margin cancel exactly, so all three
    # score 0.0 and only the total-vote count can order them.
    assert Ranking.score(two) === Ranking.score(none)
    assert Ranking.score(eight) === Ranking.score(none)

    assert ids(Ranking.rank([none, two, eight])) == [:eight, :two, :none]
    assert ids(Ranking.rank([two, eight, none])) == [:eight, :two, :none]
  end
end
```
