defmodule ConcurrentFetcher do
  @moduledoc """
  Concurrently fetches data from multiple named sources under a single global timeout.

  Every source is started at once via `Task.Supervisor`-free `Task.async_stream`-free
  primitives (plain `Task.async/1` linked to a temporary supervisor-less owner), so the
  clock starts ticking for all of them simultaneously. The timeout is *global*: it is
  measured from the moment `fetch_all/2` is invoked, not per source. Whichever fetches
  have completed by the deadline keep their results; the rest are reported as
  `{:error, :timeout}` and their processes are killed before `fetch_all/2` returns, so
  no orphaned work survives the call.

  Fetch functions are zero-arity closures which may:

    * return `{:ok, value}` — reported verbatim;
    * return `{:error, reason}` — reported verbatim;
    * return any other term — reported as `{:ok, term}`;
    * raise, throw, or exit — reported as `{:error, reason}`.

  Only the Elixir standard library and OTP primitives are used.
  """

  @typedoc "A source name — any term."
  @type name :: term()

  @typedoc "A zero-arity fetch function."
  @type fetch_fun :: (-> term())

  @typedoc "A source pairing a name with its fetch function."
  @type source :: {name(), fetch_fun()}

  @typedoc "The outcome recorded for a single source."
  @type result :: {:ok, term()} | {:error, term()}

  @doc """
  Runs every `{name, fetch_fn}` in `sources` concurrently under a global `timeout_ms`.

  Returns a map of `%{name => result}` where `result` is `{:ok, value}` for fetches that
  finished in time, `{:error, :timeout}` for fetches still running when the global
  deadline expired, and `{:error, reason}` for fetches that failed or returned an error
  tuple themselves.

  The deadline is shared by all sources and starts when this function is called. Any
  fetch still running at the deadline is killed and awaited before returning, so the
  call never leaves stray processes behind. An empty `sources` list returns `%{}`
  immediately without spawning anything.

  Duplicate names are permitted; the last completed entry for a given name wins.

  ## Examples

      iex> ConcurrentFetcher.fetch_all([{:a, fn -> {:ok, 1} end}], 1_000)
      %{a: {:ok, 1}}

      iex> ConcurrentFetcher.fetch_all([], 1_000)
      %{}

      iex> ConcurrentFetcher.fetch_all([{:slow, fn -> Process.sleep(:infinity) end}], 50)
      %{slow: {:error, :timeout}}
  """
  @spec fetch_all([source()], timeout()) :: %{optional(name()) => result()}
  def fetch_all(sources, timeout_ms)

  def fetch_all([], timeout_ms) when is_integer(timeout_ms) and timeout_ms >= 0 do
    %{}
  end

  def fetch_all([], :infinity), do: %{}

  def fetch_all(sources, timeout_ms) when is_list(sources) and length(sources) > 0 do
    validate_timeout!(timeout_ms)

    tasks = Enum.map(sources, &start_task/1)
    defaults = Map.new(sources, fn {name, _fun} -> {name, {:error, :timeout}} end)

    collected = collect(tasks, deadline(timeout_ms), %{})

    Map.merge(defaults, collected)
  end

  # -- internals ---------------------------------------------------------------------

  defp validate_timeout!(:infinity), do: :ok

  defp validate_timeout!(timeout_ms) when is_integer(timeout_ms) and timeout_ms >= 0, do: :ok

  defp validate_timeout!(other) do
    raise ArgumentError,
          "timeout_ms must be a non-negative integer or :infinity, got: #{inspect(other)}"
  end

  defp deadline(:infinity), do: :infinity
  defp deadline(timeout_ms), do: System.monotonic_time(:millisecond) + timeout_ms

  defp time_left(:infinity), do: :infinity

  defp time_left(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 0)
  end

  # Each task is unlinked from the caller (`Task.async/1` links, which would propagate a
  # fetch crash into the caller), so failures are observed purely through the monitor.
  defp start_task({name, fun}) when is_function(fun, 0) do
    task =
      Task.Supervisor.async_nolink(supervisor(), fn ->
        try do
          {:ok, fun.()}
        catch
          kind, reason -> {:raised, normalize(kind, reason, __STACKTRACE__)}
        end
      end)

    {name, task}
  end

  defp start_task({name, other}) do
    raise ArgumentError,
          "fetch function for source #{inspect(name)} must be a zero-arity function, " <>
            "got: #{inspect(other)}"
  end

  # A transient, per-call supervisor keeps ownership of the fetch processes local to this
  # call and guarantees they are torn down with it.
  defp supervisor do
    case Process.get(__MODULE__) do
      nil ->
        {:ok, pid} = Task.Supervisor.start_link()
        Process.put(__MODULE__, pid)
        pid

      pid ->
        pid
    end
  end

  defp collect([], _deadline, acc), do: acc

  defp collect(tasks, deadline, acc) do
    refs = Map.new(tasks, fn {name, task} -> {task.ref, {name, task}} end)

    acc = await_loop(refs, deadline, acc)

    Enum.each(tasks, fn {_name, task} -> Task.shutdown(task, :brutal_kill) end)
    stop_supervisor()

    acc
  end

  defp await_loop(refs, _deadline, acc) when map_size(refs) == 0, do: acc

  defp await_loop(refs, deadline, acc) do
    receive do
      {ref, payload} when is_map_key(refs, ref) ->
        {{name, _task}, rest} = Map.pop!(refs, ref)
        Process.demonitor(ref, [:flush])
        await_loop(rest, deadline, Map.put(acc, name, interpret(payload)))

      {:DOWN, ref, :process, _pid, reason} when is_map_key(refs, ref) ->
        {{name, _task}, rest} = Map.pop!(refs, ref)
        await_loop(rest, deadline, Map.put(acc, name, {:error, down_reason(reason)}))
    after
      time_left(deadline) -> acc
    end
  end

  defp stop_supervisor do
    case Process.delete(__MODULE__) do
      nil -> :ok
      pid -> Supervisor.stop(pid, :normal)
    end
  end

  # Successful returns are normalized: explicit result tuples pass through untouched,
  # anything else is wrapped as {:ok, term}.
  defp interpret({:ok, {:ok, value}}), do: {:ok, value}
  defp interpret({:ok, {:error, reason}}), do: {:error, reason}
  defp interpret({:ok, value}), do: {:ok, value}
  defp interpret({:raised, reason}), do: {:error, reason}

  defp normalize(:error, reason, stacktrace), do: Exception.normalize(:error, reason, stacktrace)
  defp normalize(:throw, value, _stacktrace), do: {:nocatch, value}
  defp normalize(:exit, reason, _stacktrace), do: reason

  defp down_reason({reason, _stacktrace}), do: reason
  defp down_reason(reason), do: reason
end