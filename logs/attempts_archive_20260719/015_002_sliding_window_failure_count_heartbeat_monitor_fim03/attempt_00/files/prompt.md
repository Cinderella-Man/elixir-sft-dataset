# Fill in the Middle: `maybe_schedule/3`

Below is the complete `WindowMonitor` module — a `GenServer` that watches
registered services and classifies each as `:up` or `:down` using a sliding
window of recent probe results — with the body of the private
`maybe_schedule/3` helper removed. Your task is to implement it.

Implement the private `maybe_schedule/3` function. It arranges the *next*
automatic probe for a watched service and is called both when a service is first
watched and after each automatic tick fires. It takes the service `name`, the
service's `interval`, and the service's `epoch` (a monotonic generation number
used to distinguish a service's current configuration from a stale one).

- When `interval` is a positive integer (a number of milliseconds), schedule a
  `{:tick, name, epoch}` message to be delivered to the server process itself
  after `interval` milliseconds using `Process.send_after/3`, then return `:ok`.
  Carrying `epoch` in the message lets `handle_info/2` ignore ticks left over
  from a previous configuration of the same `name`.
- When `interval` is the atom `:manual`, do nothing (no message is scheduled)
  and simply return `:ok`.

In both cases the function returns `:ok`. It should be written as two clauses —
one for the integer-interval case (guarded with `is_integer/1`) and one for the
`:manual` case.

```elixir
defmodule WindowMonitor do
  @moduledoc """
  A `GenServer` that watches registered services and classifies each as `:up`
  or `:down` using a **sliding window of recent probe results**.

  For every watched service the server retains only its `:window` most-recent
  probe outcomes. After each probe it counts how many of those retained results
  were failures (`f`) and compares against the configured `:threshold` (`t`):
  the service is `:down` when `f >= t`, otherwise `:up`. Because the window
  slides, failures need not be consecutive and a service recovers on its own
  once enough healthy results push failures out of the window.

  Services are independent — one service's results, window, or status never
  affect another's. On each actual status change the service's `:on_change`
  callback is invoked exactly once. Unknown messages are ignored.

  Only the OTP standard library is used.
  """

  use GenServer

  @typedoc "A zero-arity health probe."
  @type probe :: (-> :ok | {:error, term()})

  @typedoc "A service status."
  @type status :: :up | :down

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the monitor linked to the caller.

  When `opts` contains a `:name`, the process is registered under it; otherwise
  it starts unregistered. A freshly started server watches zero services.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Registers `name` to be watched using the zero-arity `probe`.

  Options: `:window` (positive integer, default `5`), `:threshold` (positive
  integer, default `3`), `:on_change` (arity-2 callback, default no-op) and
  `:interval` (positive integer milliseconds or `:manual`, default `:manual`).

  A newly watched service starts `:up` with an empty window. Re-watching an
  existing `name` replaces its configuration and resets it to this state.
  """
  @spec watch(GenServer.server(), term(), probe(), keyword()) :: :ok
  def watch(server, name, probe, opts \\ []) when is_function(probe, 0) do
    GenServer.call(server, {:watch, name, probe, opts})
  end

  @doc """
  Runs exactly one probe for `name` immediately, applies the result, and returns
  `{:ok, new_status}`. Returns `{:error, :not_found}` if `name` is not watched.
  """
  @spec probe_now(GenServer.server(), term()) ::
          {:ok, status()} | {:error, :not_found}
  def probe_now(server, name) do
    GenServer.call(server, {:probe_now, name})
  end

  @doc """
  Returns `{:ok, status}` for a watched service or `{:error, :not_found}`.
  """
  @spec health(GenServer.server(), term()) ::
          {:ok, status()} | {:error, :not_found}
  def health(server, name) do
    GenServer.call(server, {:health, name})
  end

  @doc """
  Returns a map `%{name => status}` for every currently watched service.
  """
  @spec report(GenServer.server()) :: %{optional(term()) => status()}
  def report(server) do
    GenServer.call(server, :report)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    {:ok, %{services: %{}, counter: 0}}
  end

  @impl true
  def handle_call({:watch, name, probe, opts}, _from, state) do
    window = Keyword.get(opts, :window, 5)
    threshold = Keyword.get(opts, :threshold, 3)
    on_change = Keyword.get(opts, :on_change, fn _name, _status -> :ok end)
    interval = Keyword.get(opts, :interval, :manual)
    epoch = state.counter + 1

    service = %{
      probe: probe,
      window: window,
      threshold: threshold,
      on_change: on_change,
      interval: interval,
      status: :up,
      results: [],
      epoch: epoch
    }

    maybe_schedule(name, interval, epoch)
    services = Map.put(state.services, name, service)
    {:reply, :ok, %{state | services: services, counter: epoch}}
  end

  def handle_call({:probe_now, name}, _from, state) do
    case Map.get(state.services, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      service ->
        {new_service, new_status} = probe_and_notify(name, service)
        services = Map.put(state.services, name, new_service)
        {:reply, {:ok, new_status}, %{state | services: services}}
    end
  end

  def handle_call({:health, name}, _from, state) do
    case Map.get(state.services, name) do
      nil -> {:reply, {:error, :not_found}, state}
      %{status: status} -> {:reply, {:ok, status}, state}
    end
  end

  def handle_call(:report, _from, state) do
    report = Map.new(state.services, fn {name, %{status: s}} -> {name, s} end)
    {:reply, report, state}
  end

  def handle_call(_other, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_info({:tick, name, epoch}, state) do
    case Map.get(state.services, name) do
      %{epoch: ^epoch, interval: interval} = service when is_integer(interval) ->
        {new_service, _status} = probe_and_notify(name, service)
        maybe_schedule(name, interval, epoch)
        services = Map.put(state.services, name, new_service)
        {:noreply, %{state | services: services}}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  # ── Internal helpers ──────────────────────────────────────────────────────

  defp maybe_schedule(name, interval, epoch) when is_integer(interval) do
    # TODO
  end

  @spec probe_and_notify(term(), map()) :: {map(), status()}
  defp probe_and_notify(name, service) do
    outcome = run_probe(service.probe)
    results = Enum.take([outcome | service.results], service.window)
    failures = Enum.count(results, &(&1 == :fail))
    new_status = if failures >= service.threshold, do: :down, else: :up

    if new_status != service.status do
      service.on_change.(name, new_status)
    end

    {%{service | results: results, status: new_status}, new_status}
  end

  @spec run_probe(probe()) :: :ok | :fail
  defp run_probe(probe) do
    case probe.() do
      :ok -> :ok
      _other -> :fail
    end
  end
end
```