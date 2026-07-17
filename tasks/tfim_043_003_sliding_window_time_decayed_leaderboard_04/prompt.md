# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule SlidingWindowLeaderboard do
  @moduledoc """
  A time-decayed leaderboard backed by an ETS `:duplicate_bag`.

  Each scoring event is stored as its own row `{player_id, timestamp, points}`.
  A player's *active* score at time `now` is the sum of points from events whose
  timestamp is strictly greater than `now - window_ms`; older events "fall off"
  the window and no longer count.

  Time is always supplied by the caller as a millisecond integer, so the module
  is fully deterministic.  Recording is a single atomic `:ets.insert/2`, so many
  processes may record concurrently with no coordination and no lost writes.

  ## Rank contract

  `rank/3` uses standard competition ("1224") ranking over active scores: tied
  players share a rank and the next lower group is bumped by the tie-group size.
  """

  @type board :: {:ets.tid(), pos_integer()}
  @type player_id :: term()

  @doc """
  Creates a new sliding-window leaderboard with window `window_ms` milliseconds.
  """
  @spec new(atom(), pos_integer()) :: {:ok, board()}
  def new(board_name, window_ms)
      when is_atom(board_name) and is_integer(window_ms) and window_ms > 0 do
    tid =
      :ets.new(board_name, [
        :duplicate_bag,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, {tid, window_ms}}
  end

  @doc """
  Records a scoring event of `points` for `player_id` at `now`.  Atomic insert.
  """
  @spec record(board(), player_id(), number(), integer()) :: :ok
  def record({tid, _window}, player_id, points, now)
      when is_number(points) and is_integer(now) do
    :ets.insert(tid, {player_id, now, points})
    :ok
  end

  @doc """
  Returns `{:ok, active_score}` for a player at `now`, or `{:error, :not_found}`
  when the player has no active (unexpired) events.
  """
  @spec score(board(), player_id(), integer()) :: {:ok, number()} | {:error, :not_found}
  def score(board, player_id, now) do
    case Enum.find(active_scores(board, now), fn {p, _s} -> p == player_id end) do
      nil -> {:error, :not_found}
      {_p, s} -> {:ok, s}
    end
  end

  @doc """
  Returns the top `n` active players at `now`, sorted by active score descending.
  """
  @spec top(board(), non_neg_integer(), integer()) :: [{player_id(), number()}]
  def top(_board, 0, _now), do: []

  def top(board, n, now) when is_integer(n) and n > 0 do
    board
    |> active_scores(now)
    |> Enum.sort_by(fn {_p, s} -> s end, :desc)
    |> Enum.take(n)
  end

  @doc """
  Returns `{:ok, rank, active_score}` (1-based competition ranking) at `now`, or
  `{:error, :not_found}` when the player has no active events.
  """
  @spec rank(board(), player_id(), integer()) ::
          {:ok, pos_integer(), number()} | {:error, :not_found}
  def rank(board, player_id, now) do
    scores = active_scores(board, now)

    case Enum.find(scores, fn {p, _s} -> p == player_id end) do
      nil ->
        {:error, :not_found}

      {_p, s} ->
        above = Enum.count(scores, fn {_p2, other} -> other > s end)
        {:ok, above + 1, s}
    end
  end

  @doc """
  Deletes every event with `timestamp <= now - window_ms`.  Returns the count.
  """
  @spec prune(board(), integer()) :: non_neg_integer()
  def prune({tid, window}, now) when is_integer(now) do
    cutoff = now - window
    match_spec = [{{:_, :"$1", :_}, [{:"=<", :"$1", cutoff}], [true]}]
    :ets.select_delete(tid, match_spec)
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  # Returns [{player_id, active_score}] for every player with at least one event
  # whose timestamp is strictly greater than (now - window).
  defp active_scores({tid, window}, now) do
    cutoff = now - window

    tid
    |> :ets.tab2list()
    |> Enum.filter(fn {_p, ts, _pts} -> ts > cutoff end)
    |> Enum.group_by(fn {p, _ts, _pts} -> p end, fn {_p, _ts, pts} -> pts end)
    |> Enum.map(fn {p, points} -> {p, Enum.sum(points)} end)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule SlidingWindowLeaderboardTest do
  use ExUnit.Case, async: false

  setup do
    name = :"swboard_#{:erlang.unique_integer([:positive])}"
    {:ok, board} = SlidingWindowLeaderboard.new(name, 1000)
    %{board: board}
  end

  test "score is :not_found for unknown player", %{board: board} do
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "ghost", 10_000)
  end

  test "active events sum within the window", %{board: board} do
    :ok = SlidingWindowLeaderboard.record(board, "alice", 5, 10_000)
    :ok = SlidingWindowLeaderboard.record(board, "alice", 7, 10_200)
    assert {:ok, 12} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
  end

  test "expired events fall out of the window", %{board: board} do
    # TODO
  end

  test "player with only expired events is :not_found", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 100, 1_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
  end

  test "event exactly at the cutoff is expired", %{board: board} do
    # query at 10_000, window 1000 -> cutoff 9_000; event at 9_000 is expired
    SlidingWindowLeaderboard.record(board, "alice", 42, 9_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_000)

    # one millisecond later it is active
    SlidingWindowLeaderboard.record(board, "bob", 42, 9_001)
    assert {:ok, 42} = SlidingWindowLeaderboard.score(board, "bob", 10_000)
  end

  test "top excludes expired players and sorts descending", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 30, 10_000)
    SlidingWindowLeaderboard.record(board, "bob", 50, 10_100)
    SlidingWindowLeaderboard.record(board, "carol", 999, 1_000)

    assert [{"bob", 50}, {"alice", 30}] = SlidingWindowLeaderboard.top(board, 5, 10_500)
  end

  test "top(n) caps the result", %{board: board} do
    for i <- 1..6, do: SlidingWindowLeaderboard.record(board, "p:#{i}", i, 10_000)
    assert length(SlidingWindowLeaderboard.top(board, 3, 10_500)) == 3
  end

  test "rank uses competition ranking over active scores", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 50, 10_000)
    SlidingWindowLeaderboard.record(board, "bob", 50, 10_000)
    SlidingWindowLeaderboard.record(board, "carol", 10, 10_000)

    assert {:ok, 1, 50} = SlidingWindowLeaderboard.rank(board, "alice", 10_500)
    assert {:ok, 1, 50} = SlidingWindowLeaderboard.rank(board, "bob", 10_500)
    assert {:ok, 3, 10} = SlidingWindowLeaderboard.rank(board, "carol", 10_500)
  end

  test "rank is :not_found when the player has no active events", %{board: board} do
    assert {:error, :not_found} = SlidingWindowLeaderboard.rank(board, "ghost", 10_500)
  end

  test "prune deletes expired events and returns the count", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 1, 1_000)
    SlidingWindowLeaderboard.record(board, "alice", 2, 2_000)
    SlidingWindowLeaderboard.record(board, "bob", 3, 10_000)

    # at now = 10_500 cutoff = 9_500, both of alice's events expired
    assert 2 = SlidingWindowLeaderboard.prune(board, 10_500)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
    assert {:ok, 3} = SlidingWindowLeaderboard.score(board, "bob", 10_500)
  end

  test "score reflects the window sliding forward over time", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 10, 10_000)
    SlidingWindowLeaderboard.record(board, "alice", 20, 10_800)

    assert {:ok, 30} = SlidingWindowLeaderboard.score(board, "alice", 10_900)
    # advance so the first event (10_000) has expired: cutoff at 11_100 = 10_100
    assert {:ok, 20} = SlidingWindowLeaderboard.score(board, "alice", 11_100)
  end

  test "concurrent record calls are not lost", %{board: board} do
    1..100
    |> Enum.map(fn _ ->
      Task.async(fn -> SlidingWindowLeaderboard.record(board, "p", 1, 10_000) end)
    end)
    |> Enum.each(&Task.await/1)

    assert {:ok, 100} = SlidingWindowLeaderboard.score(board, "p", 10_500)
  end

  test "two boards do not share state" do
    {:ok, a} = SlidingWindowLeaderboard.new(:"swa_#{:erlang.unique_integer([:positive])}", 1000)
    {:ok, b} = SlidingWindowLeaderboard.new(:"swb_#{:erlang.unique_integer([:positive])}", 1000)
    SlidingWindowLeaderboard.record(a, "alice", 5, 10_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(b, "alice", 10_000)
  end

  test "prune deletes the event exactly at the cutoff but keeps cutoff+1", %{board: board} do
    # window 1000, prune at now = 10_000 -> cutoff 9_000
    :ok = SlidingWindowLeaderboard.record(board, "alice", 42, 9_000)
    :ok = SlidingWindowLeaderboard.record(board, "bob", 7, 9_001)

    assert 1 = SlidingWindowLeaderboard.prune(board, 10_000)
    assert {:error, :not_found} = SlidingWindowLeaderboard.score(board, "alice", 10_000)
    assert {:ok, 7} = SlidingWindowLeaderboard.score(board, "bob", 10_000)
  end

  test "a player whose active events sum to zero is found, not :not_found", %{board: board} do
    :ok = SlidingWindowLeaderboard.record(board, "zed", 0, 10_000)
    :ok = SlidingWindowLeaderboard.record(board, "nel", 5, 10_000)
    :ok = SlidingWindowLeaderboard.record(board, "nel", -5, 10_100)

    assert {:ok, 0} = SlidingWindowLeaderboard.score(board, "zed", 10_500)
    assert {:ok, 0} = SlidingWindowLeaderboard.score(board, "nel", 10_500)
    assert {:ok, 1, 0} = SlidingWindowLeaderboard.rank(board, "zed", 10_500)
    assert {"zed", 0} in SlidingWindowLeaderboard.top(board, 5, 10_500)
  end

  test "new/2 rejects a non-positive or non-integer window_ms" do
    name = :"swguard_#{:erlang.unique_integer([:positive])}"

    assert_raise FunctionClauseError, fn -> SlidingWindowLeaderboard.new(name, 0) end
    assert_raise FunctionClauseError, fn -> SlidingWindowLeaderboard.new(name, -1) end
    assert_raise FunctionClauseError, fn -> SlidingWindowLeaderboard.new(name, 100.0) end
    assert_raise FunctionClauseError, fn -> SlidingWindowLeaderboard.new("not_atom", 100) end
  end

  test "record accepts float points and they sum into the active score", %{board: board} do
    assert :ok = SlidingWindowLeaderboard.record(board, "alice", 1.5, 10_000)
    assert :ok = SlidingWindowLeaderboard.record(board, "alice", 2.25, 10_100)

    assert {:ok, 3.75} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
    assert [{"alice", 3.75}] = SlidingWindowLeaderboard.top(board, 3, 10_500)

    assert_raise FunctionClauseError, fn ->
      SlidingWindowLeaderboard.record(board, "alice", "five", 10_000)
    end
  end

  test "rank recomputes as the window slides and leaders expire", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 100, 10_000)
    SlidingWindowLeaderboard.record(board, "bob", 50, 10_800)
    SlidingWindowLeaderboard.record(board, "carol", 50, 10_800)

    assert {:ok, 1, 100} = SlidingWindowLeaderboard.rank(board, "alice", 10_900)
    assert {:ok, 2, 50} = SlidingWindowLeaderboard.rank(board, "bob", 10_900)

    # cutoff at 11_100 = 10_100, so alice's only event has expired
    assert {:error, :not_found} = SlidingWindowLeaderboard.rank(board, "alice", 11_100)
    assert {:ok, 1, 50} = SlidingWindowLeaderboard.rank(board, "bob", 11_100)
    assert {:ok, 1, 50} = SlidingWindowLeaderboard.rank(board, "carol", 11_100)
  end

  test "prune returns 0 and keeps every event when nothing has expired", %{board: board} do
    SlidingWindowLeaderboard.record(board, "alice", 5, 10_000)
    SlidingWindowLeaderboard.record(board, "bob", 9, 10_400)

    assert 0 = SlidingWindowLeaderboard.prune(board, 10_500)
    assert {:ok, 5} = SlidingWindowLeaderboard.score(board, "alice", 10_500)
    assert [{"bob", 9}, {"alice", 5}] = SlidingWindowLeaderboard.top(board, 5, 10_500)
    assert 0 = SlidingWindowLeaderboard.prune(board, 10_500)
  end
end
```
