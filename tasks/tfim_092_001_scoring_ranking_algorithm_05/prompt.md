# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Ranking do
  @moduledoc """
  A configurable "hot score" ranking for content items.

  Each item is a plain map with atom keys:

    * `:upvotes` — non-negative integer
    * `:downvotes` — non-negative integer
    * `:created_at` — integer Unix timestamp in seconds
    * `:view_count` — non-negative integer
    * `:comment_count` — non-negative integer

  Items may carry any number of additional keys (such as an `:id`); those are
  ignored and items are never mutated.

  The hot score blends three components — net votes, recency, and engagement —
  each with a configurable weight:

      net_votes  = upvotes - downvotes
      age_hours  = max(now - created_at, 0) / 3600
      recency    = 2 ** (-age_hours / half_life_hours)
      engagement = if view_count > 0, do: comment_count / view_count, else: 0.0

      score = weights.votes      * net_votes
            + weights.recency     * recency
            + weights.engagement  * engagement
  """

  @default_weights %{votes: 1.0, recency: 1.0, engagement: 1.0}
  @default_half_life_hours 12
  @seconds_per_hour 3600

  @doc """
  Computes the hot score of a single `item` as a float.

  ## Options

    * `:now` — integer Unix timestamp in seconds used as the current-time
      reference. Defaults to `System.os_time(:second)`.
    * `:half_life_hours` — a positive number controlling how fast recency
      decays. Defaults to `12`.
    * `:weights` — a map merged over the defaults
      `%{votes: 1.0, recency: 1.0, engagement: 1.0}`.
  """
  @spec score(map(), keyword()) :: float()
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

  @doc """
  Returns `items` sorted by score, highest first.

  The same `opts` are passed through to `score/2`, so ranking honors any custom
  `:now`, `:half_life_hours`, or `:weights`.

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
        # Equal score and created_at: keep original order (stable sort).
        true -> true
      end
    end)
    |> Enum.map(fn {_score, _created_at, item} -> item end)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule RankingTest do
  use ExUnit.Case, async: false

  # Fixed reference "now" so every test is deterministic.
  @now 1_700_000_000
  @hour 3_600

  # Build an item map with sensible defaults; override any field via keyword list.
  defp item(overrides) do
    base = %{
      id: nil,
      upvotes: 0,
      downvotes: 0,
      created_at: @now,
      view_count: 0,
      comment_count: 0
    }

    Map.merge(base, Map.new(overrides))
  end

  defp ids(items), do: Enum.map(items, & &1.id)

  # -------------------------------------------------------
  # score/2 — exact formula
  # -------------------------------------------------------

  test "score matches the documented formula with default options" do
    # net = 10 - 4 = 6 ; age 0 -> recency 1.0 ; engagement 5/100 = 0.05
    # score = 1.0*6 + 1.0*1.0 + 1.0*0.05 = 7.05
    it = item(upvotes: 10, downvotes: 4, view_count: 100, comment_count: 5)
    assert_in_delta Ranking.score(it, now: @now), 7.05, 1.0e-9
  end

  test "score is a float" do
    assert is_float(Ranking.score(item(upvotes: 3), now: @now))
  end

  test "net votes can be negative and drag the score down" do
    up = item(upvotes: 20, downvotes: 0)
    down = item(upvotes: 0, downvotes: 20)

    w = %{votes: 1.0, recency: 0.0, engagement: 0.0}
    assert_in_delta Ranking.score(up, now: @now, weights: w), 20.0, 1.0e-9
    assert_in_delta Ranking.score(down, now: @now, weights: w), -20.0, 1.0e-9
  end

  # -------------------------------------------------------
  # Recency
  # -------------------------------------------------------

  test "recency is 1.0 at age zero and 0.5 at one half-life" do
    # TODO
  end

  test "half_life_hours is configurable" do
    w = %{votes: 0.0, recency: 1.0, engagement: 0.0}
    it = item(created_at: @now - 6 * @hour)

    # Age 6h with a 6h half-life -> recency 0.5
    assert_in_delta Ranking.score(it, now: @now, weights: w, half_life_hours: 6), 0.5, 1.0e-9
  end

  test "future created_at is clamped to age zero (recency never exceeds 1.0)" do
    w = %{votes: 0.0, recency: 1.0, engagement: 0.0}
    future = item(created_at: @now + 10_000)
    assert_in_delta Ranking.score(future, now: @now, weights: w), 1.0, 1.0e-9
  end

  test "recent item ranks above an older item with equal votes" do
    recent = item(id: :recent, upvotes: 100, created_at: @now)
    old = item(id: :old, upvotes: 100, created_at: @now - 100 * @hour)

    assert Ranking.score(recent, now: @now) > Ranking.score(old, now: @now)
  end

  # -------------------------------------------------------
  # Votes vs. engagement
  # -------------------------------------------------------

  test "highly-upvoted item ranks above a low-vote item of equal age" do
    high = item(id: :high, upvotes: 100, created_at: @now)
    low = item(id: :low, upvotes: 2, created_at: @now)

    assert Ranking.score(high, now: @now) > Ranking.score(low, now: @now)
  end

  test "higher comment/view engagement ratio increases the score" do
    w = %{votes: 0.0, recency: 0.0, engagement: 1.0}

    engaged = item(view_count: 100, comment_count: 50)
    meh = item(view_count: 100, comment_count: 10)

    assert_in_delta Ranking.score(engaged, now: @now, weights: w), 0.5, 1.0e-9
    assert_in_delta Ranking.score(meh, now: @now, weights: w), 0.1, 1.0e-9

    assert Ranking.score(engaged, now: @now, weights: w) >
             Ranking.score(meh, now: @now, weights: w)
  end

  test "zero view_count yields zero engagement and never raises" do
    w = %{votes: 0.0, recency: 0.0, engagement: 1.0}
    it = item(view_count: 0, comment_count: 25)
    assert_in_delta Ranking.score(it, now: @now, weights: w), 0.0, 1.0e-9
  end

  # -------------------------------------------------------
  # rank/2 — ordering
  # -------------------------------------------------------

  test "rank sorts items by score descending" do
    a = item(id: :a, upvotes: 100, created_at: @now)
    b = item(id: :b, upvotes: 100, created_at: @now - 100 * @hour)
    c = item(id: :c, upvotes: 2, created_at: @now)
    d = item(id: :d, upvotes: 0, downvotes: 50, created_at: @now)

    ranked = Ranking.rank([c, d, a, b], now: @now)
    assert ids(ranked) == [:a, :b, :c, :d]
  end

  test "rank returns the item maps unchanged" do
    a = item(id: :a, upvotes: 5, view_count: 10, comment_count: 2)
    b = item(id: :b, upvotes: 9)

    ranked = Ranking.rank([a, b], now: @now)
    assert Enum.sort_by(ranked, & &1.id) == Enum.sort_by([a, b], & &1.id)
  end

  test "weights are configurable enough to flip the ordering" do
    fresh_mid = item(id: :fresh, upvotes: 10, created_at: @now)
    stale_high = item(id: :stale, upvotes: 100, created_at: @now - 200 * @hour)

    # Default-ish weights: raw votes dominate, stale_high wins.
    default_order = ids(Ranking.rank([fresh_mid, stale_high], now: @now))
    assert default_order == [:stale, :fresh]

    # Crush the vote weight and amplify recency: the fresh item overtakes.
    w = %{votes: 0.01, recency: 100.0, engagement: 0.0}
    flipped = ids(Ranking.rank([stale_high, fresh_mid], now: @now, weights: w))
    assert flipped == [:fresh, :stale]
  end

  # -------------------------------------------------------
  # Tie-breaking
  # -------------------------------------------------------

  test "ties on score are broken by created_at descending" do
    w = %{votes: 1.0, recency: 0.0, engagement: 0.0}

    older = item(id: :older, upvotes: 5, created_at: @now - 50 * @hour)
    newer = item(id: :newer, upvotes: 5, created_at: @now - 1 * @hour)

    # Equal scores (recency/engagement zeroed, same net votes) -> newer first.
    assert ids(Ranking.rank([older, newer], now: @now, weights: w)) == [:newer, :older]
    assert ids(Ranking.rank([newer, older], now: @now, weights: w)) == [:newer, :older]
  end

  test "fully-equal items preserve original input order (stable)" do
    x = item(id: :x, upvotes: 7, created_at: @now)
    y = item(id: :y, upvotes: 7, created_at: @now)
    z = item(id: :z, upvotes: 7, created_at: @now)

    assert ids(Ranking.rank([x, y, z], now: @now)) == [:x, :y, :z]
    assert ids(Ranking.rank([z, x, y], now: @now)) == [:z, :x, :y]
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "rank handles the empty list" do
    assert Ranking.rank([], now: @now) == []
  end

  test "rank handles a single item" do
    only = item(id: :only, upvotes: 3)
    assert Ranking.rank([only], now: @now) == [only]
  end

  test "a partial weights map is merged over the defaults, leaving other weights at 1.0" do
    # net = 10 ; recency weight zeroed ; engagement = 5/100 = 0.05
    # score = 1.0*10 + 0.0*recency + 1.0*0.05 = 10.05
    it =
      item(
        upvotes: 10,
        downvotes: 0,
        created_at: @now - 12 * @hour,
        view_count: 100,
        comment_count: 5
      )

    assert_in_delta Ranking.score(it, now: @now, weights: %{recency: 0.0}), 10.05, 1.0e-9
  end

  test "half_life_hours defaults to 12 when the option is omitted" do
    w = %{votes: 0.0, recency: 1.0, engagement: 0.0}

    aged = item(created_at: @now - 12 * @hour)
    double_aged = item(created_at: @now - 24 * @hour)

    assert_in_delta Ranking.score(aged, now: @now, weights: w), 0.5, 1.0e-9
    assert_in_delta Ranking.score(double_aged, now: @now, weights: w), 0.25, 1.0e-9
  end

  test "rank passes half_life_hours through to scoring and it can change the order" do
    w = %{votes: 0.1, recency: 1.0, engagement: 0.0}

    old = item(id: :old, upvotes: 5, created_at: @now - 24 * @hour)
    fresh = item(id: :fresh, upvotes: 0, created_at: @now)

    # Short half-life: the old item's recency collapses -> 0.5 vs 1.0.
    short = ids(Ranking.rank([old, fresh], now: @now, weights: w, half_life_hours: 1))
    assert short == [:fresh, :old]

    # Long half-life: the old item keeps most of its recency -> ~1.207 vs 1.0.
    long = ids(Ranking.rank([old, fresh], now: @now, weights: w, half_life_hours: 48))
    assert long == [:old, :fresh]
  end

  # -------------------------------------------------------
  # Omitted options: :now defaults to the system clock in seconds
  # -------------------------------------------------------

  test "score/1 with no options at all ages the item against System.os_time(:second)" do
    # Zero net votes and zero views, so the score is the recency term alone.
    # Twelve real hours of age under the default 12h half-life -> recency 0.5.
    # A `now` of 0, of `created_at`, or of milliseconds would give 1.0, 1.0, or ~0.0.
    it = item(created_at: System.os_time(:second) - 12 * @hour)

    assert_in_delta Ranking.score(it), 0.5, 1.0e-3
  end

  test "rank/1 with no options orders against the system clock in seconds" do
    now = System.os_time(:second)

    # Fresh: recency ~1.0, engagement 0.0 -> ~1.0.
    # Old (100h): recency ~0.003, engagement 50/100 -> ~0.503.
    # Without real seconds-based aging the stale, engagement-heavy item would lead.
    fresh = item(id: :fresh, view_count: 100, comment_count: 0, created_at: now)
    old = item(id: :old, view_count: 100, comment_count: 50, created_at: now - 100 * @hour)

    assert ids(Ranking.rank([old, fresh])) == [:fresh, :old]
  end
end
```
