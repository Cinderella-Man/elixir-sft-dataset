# Fill in the middle: `Monitor.handle_call/3`

Implement the `handle_call/3` GenServer callback for the `Monitor` singleton. It
must handle every synchronous request the public API sends via `GenServer.call/2`,
and it must ignore any unrecognized request without crashing. Implement all of the
following clauses:

1. **`{:register, name, func, interval, opts}`** — Register (or re-register) a
   service. Mint a fresh generation token with `make_ref/0`. Read `:threshold`
   from `opts` (default `3`) and `:notify` from `opts` (default a two-arity no-op
   `fn _name, _reason -> :ok end`). Build the per-service record with the given
   `check_func`, `interval_ms`, `threshold`, `notify`, a starting `status` of
   `:up`, a `failures` count of `0`, and the new `generation`. Schedule the first
   check with `schedule(name, generation, interval)` (which does not run the check
   now — it fires one interval later), store the record in `state` under `name`,
   and reply `:ok`. Because a new generation token is minted, any previously
   scheduled check chain for `name` is superseded and will be ignored.

2. **`{:status, name}`** — Look up `name` in `state`. If absent, reply
   `{:error, :not_found}`. Otherwise reply the service's `status` (`:up`/`:down`).

3. **`:statuses`** — Reply a map `%{service_name => status}` built from every
   registered service.

4. **`{:check_now, name}`** — Look up `name`. If absent, reply
   `{:error, :not_found}`. Otherwise run exactly one check via `run_check(service,
   name)` (which updates the failure count/status and fires `notify` on an
   `:up` -> `:down` transition), store the updated service back into `state`, and
   reply `{:ok, status}` with the resulting status. Do not touch the periodic
   timer.

5. **Any other request** — Reply `{:error, :unknown_request}` and leave `state`
   unchanged.

In every clause return the appropriate `{:reply, reply, state}` tuple.

```elixir
defmodule Monitor do
  @moduledoc """
  A singleton `GenServer` that supervises registered services by periodically
  calling a zero-arity check function for each one, tracking each service's
  `:up`/`:down` status, and firing a notification when a service transitions
  from `:up` to `:down`.

  The server is registered under the name `Monitor` (`__MODULE__`) so that the
  no-argument convenience API (`register/4`, `status/1`, `statuses/0`,
  `check_now/1`) can locate it without an explicit server reference.

  Each registration is tagged with a generation token (a `make_ref/0` value).
  Scheduled check messages whose token no longer matches the current
  registration are ignored, guaranteeing that a re-registration's superseded
  timer chain is dead and can never call the old check function again.
  """

  use GenServer

  @typedoc "The status of a monitored service."
  @type status :: :up | :down

  @typedoc "A zero-arity check function returning health of a service."
  @type check_func :: (-> :ok | {:error, term()})

  @typedoc "A two-arity notification function invoked on a down transition."
  @type notify_func :: (term(), term() -> any())

  # Internal per-service record kept in the server state map.
  @typep service :: %{
           check_func: check_func(),
           interval_ms: pos_integer(),
           threshold: pos_integer(),
           notify: notify_func(),
           status: status(),
           failures: non_neg_integer(),
           generation: reference()
         }

  # --- Public API --------------------------------------------------------

  @doc """
  Starts and links the `Monitor` singleton.

  `opts` is a keyword list (default `[]`). A `:name` option may override the
  registered name, but the convenience functions always target `Monitor`.
  A freshly started server tracks zero services.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers (or re-registers) `service_name` with the given zero-arity
  `check_func`, positive `interval_ms`, and options.

  Options:

    * `:threshold` — positive integer `N`; the service is marked `:down` after
      `N` consecutive failed checks (default `3`).
    * `:notify` — a two-arity function `notify.(service_name, reason)` invoked
      once on each `:up` -> `:down` transition (default no-op).

  Registration resets the status to `:up` with a failure count of `0` and does
  not itself run `check_func`; the first check happens one `interval_ms` later.
  Re-registering replaces the configuration and resets status. Always returns
  `:ok`.
  """
  @spec register(term(), check_func(), pos_integer(), keyword()) :: :ok
  def register(service_name, check_func, interval_ms, opts \\ [])
      when is_function(check_func, 0) and is_integer(interval_ms) and interval_ms > 0 do
    GenServer.call(__MODULE__, {:register, service_name, check_func, interval_ms, opts})
  end

  @doc """
  Returns `:up` or `:down` for a registered service, or `{:error, :not_found}`
  if the service is unknown.
  """
  @spec status(term()) :: status() | {:error, :not_found}
  def status(service_name) do
    GenServer.call(__MODULE__, {:status, service_name})
  end

  @doc """
  Returns a map `%{service_name => status}` for every currently registered
  service. Returns `%{}` when no services are registered.
  """
  @spec statuses() :: %{optional(term()) => status()}
  def statuses do
    GenServer.call(__MODULE__, :statuses)
  end

  @doc """
  Synchronously performs exactly one check for `service_name` immediately,
  doing identical work to a scheduled interval tick (calling the check
  function, updating the failure count and status, and firing the notify
  function on an `:up` -> `:down` transition).

  Returns `{:ok, status}` with the resulting status, or `{:error, :not_found}`
  if the service is unknown. Does not alter or reschedule the periodic timer.
  """
  @spec check_now(term()) :: {:ok, status()} | {:error, :not_found}
  def check_now(service_name) do
    GenServer.call(__MODULE__, {:check_now, service_name})
  end

  # --- GenServer callbacks ----------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, %{optional(term()) => service()}}
  def init(_opts) do
    {:ok, %{}}
  end

  def handle_call({:register, name, func, interval, opts}, _from, state) do
    # TODO
  end

  @impl true
  def handle_info({:check, name, generation}, state) do
    case Map.get(state, name) do
      %{generation: ^generation} = service ->
        {updated, _status} = run_check(service, name)
        schedule(name, generation, updated.interval_ms)
        {:noreply, Map.put(state, name, updated)}

      _other ->
        # Unknown service or a superseded generation token: ignore.
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Internal helpers --------------------------------------------------

  # Schedules the next check tick for `name` under the given generation token.
  @spec schedule(term(), reference(), pos_integer()) :: reference()
  defp schedule(name, generation, interval) do
    Process.send_after(self(), {:check, name, generation}, interval)
  end

  # Runs one check, updating failure count/status and firing notify on an
  # `:up` -> `:down` transition. Returns `{updated_service, resulting_status}`.
  @spec run_check(service(), term()) :: {service(), status()}
  defp run_check(service, name) do
    case service.check_func.() do
      :ok ->
        {%{service | failures: 0, status: :up}, :up}

      {:error, reason} ->
        failures = service.failures + 1

        if service.status == :up and failures >= service.threshold do
          service.notify.(name, reason)
          {%{service | failures: failures, status: :down}, :down}
        else
          {%{service | failures: failures}, service.status}
        end
    end
  end
end
```