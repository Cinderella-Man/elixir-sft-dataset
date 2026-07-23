# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule SlidingWindowLeaderboard do
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

  def record({tid, _window}, player_id, points, now)
      when is_number(points) and is_integer(now) do
    :ets.insert(tid, {player_id, now, points})
    :ok
  end

  def score(board, player_id, now) do
    case Enum.find(active_scores(board, now), fn {p, _s} -> p == player_id end) do
      nil -> {:error, :not_found}
      {_p, s} -> {:ok, s}
    end
  end

  def top(_board, 0, _now), do: []

  def top(board, n, now) when is_integer(n) and n > 0 do
    board
    |> active_scores(now)
    |> Enum.sort_by(fn {_p, s} -> s end, :desc)
    |> Enum.take(n)
  end

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
