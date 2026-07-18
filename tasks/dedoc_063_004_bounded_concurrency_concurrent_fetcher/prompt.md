# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule PooledFetcher do
  def fetch_all([], _max_concurrency, _timeout_ms), do: %{}

  def fetch_all(sources, max_concurrency, timeout_ms)
      when is_list(sources) and is_integer(max_concurrency) and max_concurrency > 0 and
             is_integer(timeout_ms) and timeout_ms >= 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    loop(sources, %{}, %{}, max_concurrency, deadline)
  end

  # Drives the pool: fill idle slots, then wait for the next completion or the
  # global deadline.
  #
  #   pending - list of {name, fetch_fn} not yet started
  #   running - map of pid => {monitor_ref, name} for in-flight fetches
  #   results - map of name => result_tuple
  defp loop(pending, running, results, max, deadline) do
    {pending, running} = fill(pending, running, max)

    if pending == [] and map_size(running) == 0 do
      results
    else
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        finalize_timeout(pending, running, results)
      else
        collect(pending, running, results, max, deadline, remaining)
      end
    end
  end

  # Waits for one worker message. The guards make sure only messages belonging
  # to this pool are consumed — unrelated mail in the caller's inbox is left
  # untouched.
  defp collect(pending, running, results, max, deadline, remaining) do
    receive do
      {:fetch_result, pid, reply} when is_map_key(running, pid) ->
        {ref, name} = Map.fetch!(running, pid)
        Process.demonitor(ref, [:flush])
        loop(pending, Map.delete(running, pid), Map.put(results, name, reply), max, deadline)

      {:DOWN, _ref, :process, pid, reason} when is_map_key(running, pid) ->
        {_ref, name} = Map.fetch!(running, pid)

        loop(
          pending,
          Map.delete(running, pid),
          Map.put(results, name, {:error, reason}),
          max,
          deadline
        )
    after
      remaining ->
        finalize_timeout(pending, running, results)
    end
  end

  # Starts queued fetches until the pool is full or the queue is empty.
  defp fill(pending, running, max) do
    if pending == [] or map_size(running) >= max do
      {pending, running}
    else
      [{name, fetch_fn} | rest] = pending
      parent = self()

      {pid, ref} =
        spawn_monitor(fn -> send(parent, {:fetch_result, self(), safe_call(fetch_fn)}) end)

      fill(rest, Map.put(running, pid, {ref, name}), max)
    end
  end

  # Kills every live fetch, waits for confirmation that it is gone, discards any
  # late result it may have sent, and marks running plus still-queued sources as
  # timed out.
  defp finalize_timeout(pending, running, results) do
    results =
      Enum.reduce(running, results, fn {pid, {ref, name}}, acc ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        end

        receive do
          {:fetch_result, ^pid, _reply} -> :ok
        after
          0 -> :ok
        end

        Map.put(acc, name, {:error, :timeout})
      end)

    Enum.reduce(pending, results, fn {name, _fetch_fn}, acc ->
      Map.put(acc, name, {:error, :timeout})
    end)
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
