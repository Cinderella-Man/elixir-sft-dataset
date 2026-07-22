defmodule PooledFetcher do
  @moduledoc """
  Concurrent fetching from many sources with a bounded worker pool and a single
  global wall-clock timeout.

  `fetch_all/3` takes a list of `{name, fetch_fn}` pairs and runs at most
  `max_concurrency` fetches at any instant. Sources are started in list order:
  the first `max_concurrency` start immediately and each remaining one starts as
  soon as a running fetch finishes and frees a slot.

  The timeout is a *global* budget: the deadline is computed once, when
  `fetch_all/3` is entered, using a monotonic clock (so it is immune to system
  clock changes). It is never reset — not per source, and not when a queued
  source finally starts running. Once the deadline passes, no further results are
  collected, every still-running process is killed, and every source that has not
  already produced a result is reported as `{:error, :timeout}`.

  Every fetch runs in its own process and every outcome is normalised into a
  tagged two-tuple, so a misbehaving `fetch_fn` can never crash the caller:

    * `{:ok, value}` — returned unchanged by `fetch_fn`
    * `{:error, reason}` — returned unchanged by `fetch_fn`
    * `{:error, %RuntimeError{}}` — `fetch_fn` raised (the exception struct itself)
    * `{:error, {:throw, value}}` — `fetch_fn` threw
    * `{:error, {:exit, reason}}` — `fetch_fn` exited
    * `{:error, {:unexpected_return, term}}` — `fetch_fn` returned some other term
    * `{:error, reason}` — the fetch process died without delivering a result
    * `{:error, :timeout}` — the global deadline expired first

  The function keeps no shared or global state: each call gets a fresh pool, a
  fresh deadline and an independent result map, so concurrent and repeated calls
  are safe.
  """

  @typedoc "An arbitrary term identifying a source; used as the result map key."
  @type name :: term()

  @typedoc "A zero-arity fetch function."
  @type fetch_fn :: (-> {:ok, term()} | {:error, term()} | term())

  @typedoc "A single source: a name paired with the function that fetches it."
  @type source :: {name(), fetch_fn()}

  @typedoc "The normalised outcome recorded for each source."
  @type result :: {:ok, term()} | {:error, term()}

  @doc """
  Fetches all `sources` concurrently, at most `max_concurrency` at a time, under a
  single global budget of `timeout_ms` milliseconds.

  Returns a map of `%{name => result}` with one entry per distinct name in
  `sources`. Maps are unordered, so callers get no ordering guarantee. If a name
  is repeated in `sources`, the entries collapse into a single key holding the
  last recorded value.

  Sources that never finish before the deadline — whether they were running or
  still queued — are reported as `{:error, :timeout}`. With `timeout_ms: 0` the
  budget is already spent, so every source times out even if its `fetch_fn` would
  have returned instantly.

  An empty `sources` list returns `%{}` immediately without spawning anything.

  ## Examples

      iex> PooledFetcher.fetch_all([{:a, fn -> {:ok, 1} end}], 2, 1_000)
      %{a: {:ok, 1}}

      iex> PooledFetcher.fetch_all([{:a, fn -> 42 end}], 1, 1_000)
      %{a: {:error, {:unexpected_return, 42}}}

      iex> PooledFetcher.fetch_all([{:a, fn -> Process.sleep(50); {:ok, 1} end}], 1, 0)
      %{a: {:error, :timeout}}

  """
  @spec fetch_all([source()], pos_integer(), non_neg_integer()) :: %{name() => result()}
  def fetch_all(sources, max_concurrency, timeout_ms)
      when is_list(sources) and is_integer(max_concurrency) and max_concurrency > 0 and
             is_integer(timeout_ms) and timeout_ms >= 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    case sources do
      [] -> %{}
      _ -> run(sources, max_concurrency, deadline)
    end
  end

  # -- Pool driver -----------------------------------------------------------

  @spec run([source()], pos_integer(), integer()) :: %{name() => result()}
  defp run(sources, max_concurrency, deadline) do
    {to_start, queued} = Enum.split(sources, max_concurrency)

    running =
      to_start
      |> Enum.map(&spawn_fetch/1)
      |> Map.new()

    pending = Map.new(sources, fn {name, _fun} -> {name, {:error, :timeout}} end)

    loop(running, queued, pending, deadline)
  end

  # `running` : %{ref => {pid, name}} for the currently executing fetches
  # `queued`  : sources still waiting for a free slot, in order
  # `results` : accumulator pre-seeded with {:error, :timeout} for every name
  @spec loop(%{reference() => {pid(), name()}}, [source()], %{name() => result()}, integer()) ::
          %{name() => result()}
  defp loop(running, queued, results, deadline) do
    cond do
      running == %{} and queued == [] ->
        results

      time_left(deadline) == 0 ->
        shutdown(running)
        results

      true ->
        collect_one(running, queued, results, deadline)
    end
  end

  @spec collect_one(%{reference() => {pid(), name()}}, [source()], %{name() => result()}, integer()) ::
          %{name() => result()}
  defp collect_one(running, queued, results, deadline) do
    receive do
      {:pooled_fetcher_result, ref, result} when is_map_key(running, ref) ->
        {{_pid, name}, running} = Map.pop(running, ref)
        Process.demonitor(ref, [:flush])
        advance(running, queued, Map.put(results, name, result), deadline)

      {:DOWN, ref, :process, _pid, reason} when is_map_key(running, ref) ->
        {{_pid, name}, running} = Map.pop(running, ref)
        advance(running, queued, Map.put(results, name, {:error, reason}), deadline)
    after
      time_left(deadline) ->
        shutdown(running)
        results
    end
  end

  # A slot just freed up: start the next queued source, if any, then keep looping.
  @spec advance(%{reference() => {pid(), name()}}, [source()], %{name() => result()}, integer()) ::
          %{name() => result()}
  defp advance(running, [], results, deadline), do: loop(running, [], results, deadline)

  defp advance(running, [next | rest], results, deadline) do
    if time_left(deadline) == 0 do
      # Deadline already gone: do not start more work, just tear down and report.
      shutdown(running)
      results
    else
      {ref, entry} = spawn_fetch(next)
      loop(Map.put(running, ref, entry), rest, results, deadline)
    end
  end

  # -- Workers ---------------------------------------------------------------

  @spec spawn_fetch(source()) :: {reference(), {pid(), name()}}
  defp spawn_fetch({name, fun}) when is_function(fun, 0) do
    parent = self()
    # spawn_monitor gives us a single reference that identifies both the worker
    # and its :DOWN message, so results and crashes cannot be confused.
    {pid, ref} =
      spawn_monitor(fn ->
        send(parent, {:pooled_fetcher_result, self_ref(), normalise(fun)})
      end)

    # The child needs the monitor ref to tag its reply; hand it over now that we
    # have it. The child blocks until it arrives.
    send(pid, {:pooled_fetcher_ref, ref})
    {ref, {pid, name}}
  end

  # Receives the monitor reference handed down by the parent right after spawn.
  @spec self_ref() :: reference()
  defp self_ref do
    receive do
      {:pooled_fetcher_ref, ref} -> ref
    end
  end

  @spec normalise(fetch_fn()) :: result()
  defp normalise(fun) do
    try do
      fun.()
    rescue
      exception -> {:error, exception}
    catch
      :throw, value -> {:error, {:throw, value}}
      :exit, reason -> {:error, {:exit, reason}}
    else
      {:ok, _value} = ok -> ok
      {:error, _reason} = error -> error
      other -> {:error, {:unexpected_return, other}}
    end
  end

  # -- Teardown --------------------------------------------------------------

  # Kill every still-running worker and confirm each one is dead before returning,
  # so no zombie process survives and no late result reaches the caller.
  @spec shutdown(%{reference() => {pid(), name()}}) :: :ok
  defp shutdown(running) do
    Enum.each(running, fn {ref, {pid, _name}} ->
      Process.exit(pid, :kill)
      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      end

      Process.demonitor(ref, [:flush])
      flush_result(ref)
    end)
  end

  # Drop a result message that raced the kill, so it cannot leak into the caller's
  # mailbox after fetch_all/3 returns.
  @spec flush_result(reference()) :: :ok
  defp flush_result(ref) do
    receive do
      {:pooled_fetcher_result, ^ref, _result} -> :ok
    after
      0 -> :ok
    end
  end

  # -- Clock -----------------------------------------------------------------

  @spec time_left(integer()) :: non_neg_integer()
  defp time_left(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 0)
  end
end