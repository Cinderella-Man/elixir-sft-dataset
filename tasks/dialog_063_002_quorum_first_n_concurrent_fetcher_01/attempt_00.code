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
  @spec fetch_first([{term(), (-> {:ok, term()} | {:error, term()})}], integer(), non_neg_integer()) ::
          %{term() => {:ok, term()} | {:error, term()}}
  def fetch_first([], _count, _timeout_ms), do: %{}

  def fetch_first(sources, count, _timeout_ms)
      when is_list(sources) and is_integer(count) and count <= 0 do
    Map.new(sources, fn {name, _fetch_fn} -> {name, {:error, :cancelled}} end)
  end

  def fetch_first(sources, count, timeout_ms)
      when is_list(sources) and is_integer(count) and is_integer(timeout_ms) and timeout_ms >= 0 do
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