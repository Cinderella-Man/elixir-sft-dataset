# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule RankingTest do
  use ExUnit.Case, async: false

  # Deterministic time origin and divisor for every test.
  @epoch 1_600_000_000
  @divisor 45_000

  defp item(overrides) do
    base = %{id: nil, upvotes: 0, downvotes: 0, created_at: @epoch}
    Map.merge(base, Map.new(overrides))
  end

  defp ids(items), do: Enum.map(items, & &1.id)

  defp opts, do: [epoch: @epoch, divisor: @divisor]

  # -------------------------------------------------------
  # score/2 — exact formula
  # -------------------------------------------------------

  test "at the epoch, score is just the logarithmic vote term" do
    # net 10 -> log10(10) = 1.0 ; net 100 -> log10(100) = 2.0
    assert_in_delta Ranking.score(item(upvotes: 10, created_at: @epoch), opts()), 1.0, 1.0e-9
    assert_in_delta Ranking.score(item(upvotes: 100, created_at: @epoch), opts()), 2.0, 1.0e-9
  end

  test "score is a float" do
    assert is_float(Ranking.score(item(upvotes: 3, created_at: @epoch), opts()))
  end

  test "vote term grows logarithmically (10x votes adds a constant)" do
    s10 = Ranking.score(item(upvotes: 10, created_at: @epoch), opts())
    s100 = Ranking.score(item(upvotes: 100, created_at: @epoch), opts())
    s1000 = Ranking.score(item(upvotes: 1000, created_at: @epoch), opts())

    assert_in_delta s100 - s10, 1.0, 1.0e-9
    assert_in_delta s1000 - s100, 1.0, 1.0e-9
  end

  test "net_votes of zero contributes nothing from the vote term" do
    it = item(upvotes: 5, downvotes: 5, created_at: @epoch)
    assert_in_delta Ranking.score(it, opts()), 0.0, 1.0e-9
  end

  test "negative net votes make the vote term negative" do
    it = item(upvotes: 0, downvotes: 10, created_at: @epoch)
    # sign = -1, order = log10(10) = 1.0 -> -1.0
    assert_in_delta Ranking.score(it, opts()), -1.0, 1.0e-9
  end

  test "time term is additive and linear in elapsed seconds" do
    # net 1 -> order 0 ; created one divisor-worth of seconds after epoch -> +1.0
    it = item(upvotes: 1, created_at: @epoch + @divisor)
    assert_in_delta Ranking.score(it, opts()), 1.0, 1.0e-9
  end

  test "divisor is configurable" do
    it = item(upvotes: 1, created_at: @epoch + 90_000)
    # net 1 -> order 0 ; 90_000 / 45_000 = 2.0
    assert_in_delta Ranking.score(it, epoch: @epoch, divisor: 45_000), 2.0, 1.0e-9
    # 90_000 / 90_000 = 1.0
    assert_in_delta Ranking.score(it, epoch: @epoch, divisor: 90_000), 1.0, 1.0e-9
  end

  # -------------------------------------------------------
  # Relative ordering
  # -------------------------------------------------------

  test "newer item ranks above an older one with equal votes" do
    recent = item(id: :recent, upvotes: 50, created_at: @epoch)
    old = item(id: :old, upvotes: 50, created_at: @epoch - 100 * @divisor)
    assert Ranking.score(recent, opts()) > Ranking.score(old, opts())
  end

  test "more net votes ranks above fewer given equal age" do
    high = item(id: :high, upvotes: 100, created_at: @epoch)
    low = item(id: :low, upvotes: 2, created_at: @epoch)
    assert Ranking.score(high, opts()) > Ranking.score(low, opts())
  end

  test "rank sorts items by score descending" do
    a = item(id: :a, upvotes: 1000, created_at: @epoch)
    b = item(id: :b, upvotes: 10, created_at: @epoch)
    c = item(id: :c, upvotes: 0, downvotes: 100, created_at: @epoch)

    assert ids(Ranking.rank([c, b, a], opts())) == [:a, :b, :c]
  end

  test "rank returns the item maps unchanged" do
    a = item(id: :a, upvotes: 5, created_at: @epoch)
    b = item(id: :b, upvotes: 9, created_at: @epoch)
    ranked = Ranking.rank([a, b], opts())
    assert Enum.sort_by(ranked, & &1.id) == Enum.sort_by([a, b], & &1.id)
  end

  # -------------------------------------------------------
  # Tie-breaking
  # -------------------------------------------------------

  test "ties on score are broken by created_at descending" do
    # A: net 10 -> order 1.0, at epoch -> score 1.0
    # B: net 1  -> order 0.0, at epoch + divisor -> time term 1.0 -> score 1.0
    a = item(id: :a, upvotes: 10, created_at: @epoch)
    b = item(id: :b, upvotes: 1, created_at: @epoch + @divisor)

    assert_in_delta Ranking.score(a, opts()), Ranking.score(b, opts()), 1.0e-9
    assert ids(Ranking.rank([a, b], opts())) == [:b, :a]
    assert ids(Ranking.rank([b, a], opts())) == [:b, :a]
  end

  test "fully-equal items preserve original input order (stable)" do
    x = item(id: :x, upvotes: 7, created_at: @epoch)
    y = item(id: :y, upvotes: 7, created_at: @epoch)
    z = item(id: :z, upvotes: 7, created_at: @epoch)

    assert ids(Ranking.rank([x, y, z], opts())) == [:x, :y, :z]
    assert ids(Ranking.rank([z, x, y], opts())) == [:z, :x, :y]
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "rank handles the empty list" do
    assert Ranking.rank([], opts()) == []
  end

  test "rank handles a single item" do
    only = item(id: :only, upvotes: 3, created_at: @epoch)
    assert Ranking.rank([only], opts()) == [only]
  end

  test "score uses the default epoch when :epoch is not given" do
    # net 10 -> order 1.0 ; created exactly at the default epoch -> time term 0.0
    at_default_epoch = item(upvotes: 10, created_at: 1_134_028_003)
    assert_in_delta Ranking.score(at_default_epoch), 1.0, 1.0e-9

    # one default-divisor of seconds later -> +1.0 from the time term
    later = item(upvotes: 10, created_at: 1_134_028_003 + 45_000)
    assert_in_delta Ranking.score(later), 2.0, 1.0e-9
  end

  test "score uses the default divisor of 45_000 when :divisor is not given" do
    # net 1 -> order 0.0 ; 45_000 seconds after the given epoch -> +1.0
    it = item(upvotes: 1, created_at: @epoch + 45_000)
    assert_in_delta Ranking.score(it, epoch: @epoch), 1.0, 1.0e-9

    # 90_000 seconds -> +2.0 under the default divisor
    it2 = item(upvotes: 1, created_at: @epoch + 90_000)
    assert_in_delta Ranking.score(it2, epoch: @epoch), 2.0, 1.0e-9
  end

  test "score is rounded to exactly 7 decimal places" do
    # net 1 -> order 0.0 ; 1 second / divisor 3 -> 0.333333... -> 0.3333333
    it = item(upvotes: 1, created_at: @epoch + 1)
    assert Ranking.score(it, epoch: @epoch, divisor: 3) === 0.3333333

    # 2 seconds / divisor 3 -> 0.666666... -> 0.6666667 (rounds up at the 7th place)
    it2 = item(upvotes: 1, created_at: @epoch + 2)
    assert Ranking.score(it2, epoch: @epoch, divisor: 3) === 0.6666667
  end

  test "divisor magnitude flips whether time or votes dominate the ranking" do
    votes = item(id: :votes, upvotes: 100, created_at: @epoch)
    fresh = item(id: :fresh, upvotes: 1, created_at: @epoch + 45_000)

    # small divisor: 45_000 seconds is worth 3.0, beating the 2.0 vote term
    assert ids(Ranking.rank([votes, fresh], epoch: @epoch, divisor: 15_000)) == [:fresh, :votes]

    # large divisor: 45_000 seconds is worth only 0.1, so votes win
    assert ids(Ranking.rank([fresh, votes], epoch: @epoch, divisor: 450_000)) == [:votes, :fresh]
  end

  test "items created before the epoch get a negative time term" do
    # TODO
  end

  test "extra item keys are ignored and returned untouched by rank" do
    a = item(id: :a, upvotes: 10, created_at: @epoch) |> Map.merge(%{title: "a", tags: [:x]})

    b =
      item(id: :b, upvotes: 1000, created_at: @epoch) |> Map.merge(%{author: "b", score: :bogus})

    assert_in_delta Ranking.score(a, opts()), 1.0, 1.0e-9
    assert Ranking.rank([a, b], opts()) == [b, a]
  end
end
```
