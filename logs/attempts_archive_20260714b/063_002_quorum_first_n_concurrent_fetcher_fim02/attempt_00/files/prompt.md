# Implement `fetch_first/3`

Implement the public `fetch_first/3` function for `QuorumFetcher`. It races the
given `sources` concurrently under a single global timeout and returns a map of
`%{name => result_tuple}` covering **every** source, returning the instant a
quorum of `count` successes is reached.

Behaviour to implement:

- Handle the trivial cases first:
  - When `sources` is empty, return `%{}` immediately.
  - When `count <= 0`, the quorum is already satisfied: run nothing and report
    every source as `{:error, :cancelled}`.
- Otherwise (a list of sources, integer `count`, and non-negative integer
  `timeout_ms`):
  - Compute a single wall-clock `deadline` from `System.monotonic_time(:millisecond)`
    plus `timeout_ms`, shared across every fetch.
  - Start **all** fetches concurrently the moment the function is called, using
    `Task.async/1` wrapping each `fetch_fn` in `safe_call/1`. Keep the mapping
    from each task's `ref` to its `name` and to its `task`.
  - Drive the collection loop with `collect/5`, which blocks until either the
    quorum is met, every task has reported, or the deadline elapses. It returns
    `{results_by_ref, reached_quorum?}`.
  - Decide the fill value for any source that never reported: `{:error, :cancelled}`
    if the quorum was reached, otherwise `{:error, :timeout}`.
  - For every ref without a result, `Task.shutdown(task, :brutal_kill)` the
    still-running task (no zombies) and record the fill value.
  - Finally, translate the ref-keyed map back into a `name`-keyed map and return it.

Only the body of `fetch_first/3` is missing (marked `# TODO`). Every other
function is already implemented. Do not use external dependencies.

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
  def fetch_first(sources, count, timeout_ms) do
    # TODO
  end

  # Blocks until the quorum is met, every task has reported, or the deadline
  # elapses. Returns `{results_by_ref, reached_quorum?}`.
  defp collect(results, success_count, quorum, all_refs, deadline) do
    cond do
      success_count >= quorum ->
        {results, true}

      map_size(results) == MapSet.size(all_refs) ->
        {results, false}

      true ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {results, false}
        else
          receive do
            {ref, reply} when is_reference(ref) ->
              if MapSet.member?(all_refs, ref) and not Map.has_key?(results, ref) do
                Process.demonitor(ref, [:flush])

                new_success =
                  case reply do
                    {:ok, _} -> success_count + 1
                    _ -> success_count
                  end

                collect(Map.put(results, ref, reply), new_success, quorum, all_refs, deadline)
              else
                collect(results, success_count, quorum, all_refs, deadline)
              end

            {:DOWN, ref, :process, _pid, reason} ->
              if MapSet.member?(all_refs, ref) and not Map.has_key?(results, ref) do
                collect(
                  Map.put(results, ref, {:error, reason}),
                  success_count,
                  quorum,
                  all_refs,
                  deadline
                )
              else
                collect(results, success_count, quorum, all_refs, deadline)
              end
          after
            remaining ->
              {results, false}
          end
        end
    end
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