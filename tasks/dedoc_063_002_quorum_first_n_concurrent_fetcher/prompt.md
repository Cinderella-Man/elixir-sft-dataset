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
defmodule QuorumFetcher do
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
          Task.shutdown(Map.fetch!(ref_to_task, ref), :brutal_kill)
          Map.put(acc, ref, fill_result)
        end
      end)

    Map.new(final, fn {ref, result} -> {Map.fetch!(ref_to_name, ref), result} end)
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
