Implement the private `run_check/2` function.

`run_check(service, name)` performs exactly one check for a single service and
returns a `{updated_service, resulting_status}` tuple. It is the shared engine used
both by scheduled interval ticks (`handle_info/2`) and by the synchronous
`check_now/1` path, so it must do the full check-and-update in one place.

It calls the service's `check_func.()` exactly once and branches on the result:

- If the result is `:ok`: reset the consecutive-failure count to `0` and set the
  status to `:up` (recovering the service if it was `:down`). Recovery must **not**
  call the notify function. Return the updated service with status `:up`.
- If the result is `{:error, reason}`: increment the consecutive-failure count by
  one.
  - If the incremented count **reaches the threshold** (`failures >= threshold`)
    **and** the service is currently `:up`, transition it to `:down`, call
    `notify.(name, reason)` exactly once (with the `reason` from this failing
    check), and return the updated service with status `:down`.
  - Otherwise (still below threshold, or already `:down`), keep the current status
    and do **not** call the notify function. Return the service with the updated
    failure count and its unchanged status.

Return the resulting status as the second element of the tuple in every branch.

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

  @impl true
  def handle_call({:register, name, func, interval, opts}, _from, state) do
    generation = make_ref()
    threshold = Keyword.get(opts, :threshold, 3)
    notify = Keyword.get(opts, :notify, fn _name, _reason -> :ok end)

    service = %{
      check_func: func,
      interval_ms: interval,
      threshold: threshold,
      notify: notify,
      status: :up,
      failures: 0,
      generation: generation
    }

    schedule(name, generation, interval)
    {:reply, :ok, Map.put(state, name, service)}
  end

  def handle_call({:status, name}, _from, state) do
    case Map.get(state, name) do
      nil -> {:reply, {:error, :not_found}, state}
      service -> {:reply, service.status, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result = Map.new(state, fn {name, service} -> {name, service.status} end)
    {:reply, result, state}
  end

  def handle_call({:check_now, name}, _from, state) do
    case Map.get(state, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      service ->
        {updated, status} = run_check(service, name)
        {:reply, {:ok, status}, Map.put(state, name, updated)}
    end
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
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

  defp run_check(service, name) do
    # TODO
  end
end
```