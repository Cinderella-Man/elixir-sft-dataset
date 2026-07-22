# Implement `collect/5`

Implement the private `collect/5` function, the receive-loop engine that powers
`QuorumFetcher.fetch_first/3`. It is called with
`collect(results, success_count, quorum, all_refs, deadline)` where:

- `results` is a map of `%{task_ref => result_tuple}` accumulated so far.
- `success_count` is how many `{:ok, _}` results have been collected so far.
- `quorum` is the number of successes required to stop early.
- `all_refs` is a `MapSet` of every task's monitor reference.
- `deadline` is an absolute `System.monotonic_time(:millisecond)` value marking
  the shared wall-clock budget.

`collect/5` blocks until one of three things happens and returns
`{results_by_ref, reached_quorum?}`:

- **Quorum reached** — as soon as `success_count >= quorum`, return
  `{results, true}` immediately without waiting for anything else.
- **Everything reported** — if every ref has produced a result
  (`map_size(results) == MapSet.size(all_refs)`), return `{results, false}`.
- **Deadline elapsed** — compute the remaining time as
  `deadline - System.monotonic_time(:millisecond)`; if it is `<= 0`, return
  `{results, false}` at once.

Otherwise, wait (for at most `remaining` milliseconds) for the next message:

- A `Task` reply `{ref, reply}` where `ref` is a reference: if `ref` belongs to
  `all_refs` and hasn't already been recorded, demonitor it with
  `Process.demonitor(ref, [:flush])` (so the eventual `:DOWN` is discarded),
  increment `success_count` only when `reply` is `{:ok, _}`, record the reply in
  `results`, and recurse. If the ref is unknown or already recorded, recurse
  unchanged.
- A monitor `{:DOWN, ref, :process, _pid, reason}` message: if `ref` belongs to
  `all_refs` and hasn't already been recorded, record it as `{:error, reason}`
  and recurse (a crash is never a success). If the ref is unknown or already
  recorded, recurse unchanged.
- If the `after remaining` timeout fires first, return `{results, false}`.

Every recursive call must thread through the updated `results` and
`success_count` while leaving `quorum`, `all_refs`, and `deadline` unchanged.

```elixir
defmodule QuorumFetcher do
  @moduledoc """
  Races concurrent fetches under a single global timeout and returns as soon as
  a quorum of successful results is reached.

  All fetches start at the same instant. The moment the `count`-th success
  arrives, any source still running is killed and reported as
  `{:error, :cancelled}`. If the quorum cannot be met before the shared deadline
  fires, unfinished sources are reported as `{:error, :timeout}`.
  """

  @doc """
  Fetch concurrently, returning once `count` sources have succeeded.

  Returns a map of `%{name => result_tuple}` covering every source, where each
  value is `{:ok, value}`, `{:error, reason}`, `{:error, :cancelled}`, or
  `{:error, :timeout}`.
  """
  @spec fetch_first(
          [{term(), (-> {:ok, term()} | {:error, term()})}],
          integer(),
          non_neg_integer()
        ) :: %{term() => {:ok, term()} | {:error, term()}}
  def fetch_first([], _count, _timeout_ms), do: %{}

  def fetch_first(sources, count, _timeout_ms)
      when is_list(sources) and is_integer(count) and count <= 0 do
    Map.new(sources, fn {name, _fetch_fn} -> {name, {:error, :cancelled}} end)
  end

  def fetch_first(sources, count, timeout_ms)
      when is_list(sources) and is_integer(count) and is_integer(timeout_ms) and
             timeout_ms >= 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    tagged =
      Enum.map(sources, fn {name, fetch_fn} ->
        task = Task.async(fn -> safe_call(fetch_fn) end)
        {task.ref, name, task}
      end)

    ref_to_name = Map.new(tagged, fn {ref, name, _task} -> {ref, name} end)
    ref_to_task = Map.new(tagged, fn {ref, _name, task} -> {ref, task} end)
    all_refs = MapSet.new(Map.keys(ref_to_name))

    {results, reached?} = collect(%{}, 0, count, all_refs, deadline)

    fill_result = if reached?, do: {:error, :cancelled}, else: {:error, :timeout}

    final =
      Enum.reduce(all_refs, results, fn ref, acc ->
        if Map.has_key?(acc, ref) do
          acc
        else
          # A task that completed just before the kill has its reply in
          # Task.shutdown's return — that source "had already succeeded"
          # (or failed) and must be reported with its REAL outcome, not
          # blanket-cancelled.
          case Task.shutdown(Map.fetch!(ref_to_task, ref), :brutal_kill) do
            {:ok, real_outcome} -> Map.put(acc, ref, real_outcome)
            _ -> Map.put(acc, ref, fill_result)
          end
        end
      end)

    Map.new(final, fn {ref, result} -> {Map.fetch!(ref_to_name, ref), result} end)
  end

  # Blocks until the quorum is met, every task has reported, or the deadline
  # elapses. Returns `{results_by_ref, reached_quorum?}`.

  defp collect(results, success_count, quorum, all_refs, deadline) do
    # TODO
  end

  # Normalises any exception, throw, exit, or unexpected return into a tagged
  # `{:ok, _} | {:error, _}` tuple so a fetch can never crash the caller.
  defp safe_call(fetch_fn) do
    case fetch_fn.() do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, value -> {:error, {kind, value}}
  end
end
```