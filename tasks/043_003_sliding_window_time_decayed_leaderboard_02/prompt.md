Implement the private `active_scores/2` function.

It is the shared internal helper that every read-side function
(`score/3`, `top/3`, `rank/3`) relies on. Given a `board` (the
`{tid, window}` tuple produced by `new/2`) and a millisecond timestamp
`now`, it must compute the active score for every player that currently
has at least one live event.

Specifically it should:

- Compute the cutoff as `now - window`.
- Read every stored event row from the ETS table `tid` using
  `:ets.tab2list/1`. Each row is a `{player_id, timestamp, points}` tuple.
- Keep only the events that are still inside the window — those whose
  `timestamp` is **strictly greater than** the cutoff (an event exactly at
  the cutoff is expired and must be dropped).
- Group the surviving events by `player_id`, collecting each event's
  `points`.
- Return a list of `{player_id, active_score}` tuples, where `active_score`
  is the sum of that player's surviving points. Players with no surviving
  events must not appear in the result.

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

  @type board :: {atom(), pos_integer()}
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
    # TODO
  end
end
```