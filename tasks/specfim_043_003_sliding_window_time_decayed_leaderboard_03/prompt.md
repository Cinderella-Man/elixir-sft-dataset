# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`record/4` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `record/4`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `record/4` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
