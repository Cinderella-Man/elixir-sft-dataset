# Concurrent Sweep Heartbeat Monitor — Implement `run_sweep/1`

Implement the private `run_sweep/1` function. It receives the `services` map
(keyed by service `name`, each value a service map holding at least a `:probe`)
and must probe **every** service concurrently, one probe per its **own separate
process**, returning a map of `%{name => :ok | :error}` — the normalised outcome
for each service.

It should:

1. Capture the server's own pid (`self()`) so the spawned processes can report
   back to it.
2. For each `{name, svc}` in `services`, create a fresh `make_ref/0` reference,
   read the service's `:probe`, and `spawn/1` a separate process whose only job
   is to run the probe via `run_probe/1` and `send/2` the message
   `{:probe_result, ref, result}` back to the server. All of these probe
   processes must be launched **before** the function waits for any result, so
   that a slow or blocking probe cannot delay the others. Collect the
   `{ref, name}` pairs produced along the way.
3. Once every probe process has been started, gather the results by calling the
   existing `gather/2` helper with the list of `{ref, name}` pairs and an empty
   accumulator map, and return the map it produces (`%{name => :ok | :error}`).

```elixir
defmodule AsyncMonitor do
  @moduledoc """
  A `GenServer` that watches enrolled services and probes them concurrently.

  Each enrolled service has a zero-arity probe function returning `:ok` or
  `{:error, reason}`. Calling `sweep/1` runs one probe for every enrolled
  service, dispatching each probe to its **own separate process** so that a
  slow or blocking probe cannot delay the others. A sweep blocks until every
  probe has finished and its result has been applied to the owning service.

  A service becomes `:down` only after `:threshold` *consecutive* failed
  probes while it was `:up`; any successful probe resets the failure count and
  brings a `:down` service back `:up`. On each actual status transition the
  service's `:on_change` callback is invoked exactly once as
  `on_change.(name, new_status)`.

  Services are fully independent: one service's result never affects another's.
  Unknown messages are ignored and never crash the server.
  """

  use GenServer

  @default_threshold 3

  @typedoc "Status of an enrolled service."
  @type status :: :up | :down

  @typedoc "A zero-arity probe function."
  @type probe :: (-> :ok | {:error, term()})

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the monitor linked to the caller.

  `opts` may contain a `:name` used for process registration; when absent the
  process is left unregistered. A freshly started server has zero enrolled
  services.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, rest} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, gen_opts)
  end

  @doc """
  Enrolls (or replaces) a service identified by `name`.

  `probe` must be a zero-arity function. `opts` accepts `:threshold` (a
  positive integer, default `#{@default_threshold}`) and `:on_change` (an
  arity-2 callback, default a no-op). The service starts `:up` with `0`
  consecutive failures; re-enrolling an existing `name` resets it to that
  initial state.
  """
  @spec enroll(GenServer.server(), term(), probe(), keyword()) :: :ok
  def enroll(server, name, probe, opts \\ []) when is_function(probe, 0) do
    GenServer.call(server, {:enroll, name, probe, opts})
  end

  @doc """
  Runs one probe for every currently enrolled service.

  Every service's probe runs in its own process and all probes of the sweep
  are launched before any of them must finish. Blocks and returns `:ok` only
  after every probe has finished and been applied. Returns `:ok` immediately
  when nothing is enrolled.
  """
  @spec sweep(GenServer.server()) :: :ok
  def sweep(server) do
    GenServer.call(server, :sweep, :infinity)
  end

  @doc """
  Returns `{:ok, status}` for an enrolled service, or `{:error, :not_found}`.
  """
  @spec status(GenServer.server(), term()) :: {:ok, status()} | {:error, :not_found}
  def status(server, name) do
    GenServer.call(server, {:status, name})
  end

  @doc """
  Returns a map of `%{name => status}` for every enrolled service.
  """
  @spec overview(GenServer.server()) :: %{optional(term()) => status()}
  def overview(server) do
    GenServer.call(server, :overview)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl true
  @spec init(keyword()) :: {:ok, %{services: map()}}
  def init(_opts) do
    {:ok, %{services: %{}}}
  end

  @impl true
  def handle_call({:enroll, name, probe, opts}, _from, state) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    on_change = Keyword.get(opts, :on_change, &default_on_change/2)

    svc = %{
      probe: probe,
      threshold: threshold,
      on_change: on_change,
      status: :up,
      count: 0
    }

    {:reply, :ok, %{state | services: Map.put(state.services, name, svc)}}
  end

  def handle_call(:sweep, _from, %{services: services} = state) do
    if map_size(services) == 0 do
      {:reply, :ok, state}
    else
      results = run_sweep(services)
      {:reply, :ok, apply_all(state, results)}
    end
  end

  def handle_call({:status, name}, _from, %{services: services} = state) do
    reply =
      case Map.fetch(services, name) do
        {:ok, svc} -> {:ok, svc.status}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call(:overview, _from, %{services: services} = state) do
    overview = Map.new(services, fn {name, svc} -> {name, svc.status} end)
    {:reply, overview, state}
  end

  def handle_call(_other, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast(_msg, state), do: {:noreply, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internals ───────────────────────────────────────────────────────────────

  defp run_sweep(services) do
    # TODO
  end

  @spec gather([{reference(), term()}], map()) :: map()
  defp gather([], acc), do: acc

  defp gather([{ref, name} | rest], acc) do
    receive do
      {:probe_result, ^ref, result} -> gather(rest, Map.put(acc, name, result))
    end
  end

  # Run a probe, normalising the outcome and shielding against raises/throws.
  @spec run_probe(probe()) :: :ok | :error
  defp run_probe(probe) do
    case probe.() do
      :ok -> :ok
      _other -> :error
    end
  rescue
    _error -> :error
  catch
    _kind, _value -> :error
  end

  # Apply every gathered result, then fire callbacks for actual transitions.
  @spec apply_all(map(), map()) :: map()
  defp apply_all(state, results) do
    {new_services, callbacks} =
      Enum.reduce(state.services, {%{}, []}, fn {name, svc}, {acc, cbs} ->
        result = Map.fetch!(results, name)
        {new_svc, transition?, new_status} = apply_result(svc, result)
        cbs = if transition?, do: [{svc.on_change, name, new_status} | cbs], else: cbs
        {Map.put(acc, name, new_svc), cbs}
      end)

    Enum.each(callbacks, fn {cb, name, status} -> cb.(name, status) end)
    %{state | services: new_services}
  end

  # Compute the new service state, plus whether the status changed.
  @spec apply_result(map(), :ok | :error) :: {map(), boolean(), status()}
  defp apply_result(%{status: st} = svc, :ok) do
    {%{svc | status: :up, count: 0}, st == :down, :up}
  end

  defp apply_result(%{status: st, count: c, threshold: t} = svc, :error) do
    new_count = c + 1

    if new_count >= t and st == :up do
      {%{svc | status: :down, count: new_count}, true, :down}
    else
      {%{svc | count: new_count}, false, st}
    end
  end

  @spec default_on_change(term(), status()) :: :ok
  defp default_on_change(_name, _status), do: :ok
end
```