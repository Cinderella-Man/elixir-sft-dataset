# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule RateMonitor do
  @moduledoc """
  A GenServer that monitors registered services using a rolling-window failure
  rate rather than consecutive failure counts.

  Each service maintains a bounded list of recent check outcomes. When the
  failure rate (errors / total checks) in a full window meets or exceeds the
  configured threshold, the service transitions to `:down`. Recovery requires
  the rate to drop below the threshold — a single success is not sufficient
  if the window is still dominated by failures.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type service_name :: term()
  @type status :: :pending | :up | :down
  @type status_info :: %{
          status: status(),
          last_check_at: integer() | nil,
          failure_rate: float(),
          checks_in_window: non_neg_integer()
        }

  @typep service :: %{
           check_func: (-> :ok | {:error, term()}),
           interval_ms: pos_integer(),
           window_size: pos_integer(),
           threshold: float(),
           status: status(),
           last_check_at: integer() | nil,
           history: list(:ok | :error),
           notified_down: boolean()
         }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the RateMonitor GenServer.

  ## Options

    * `:clock`  – zero-arity function returning current time in milliseconds.
                  Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name`   – passed directly to `GenServer.start_link/3` for registration.
    * `:notify` – `fn service_name, failure_rate -> any()` called once whenever
                  a service transitions to `:down`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opt, gen_opts} =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> {[name: name], []}
        :error -> {[], []}
      end

    GenServer.start_link(__MODULE__, opts, gen_opts ++ name_opt)
  end

  @doc """
  Registers a service for monitoring.

  ## Options

    * `:window_size` – number of recent checks to consider (default 5).
    * `:threshold`   – failure rate (0.0–1.0) at which service is `:down` (default 0.6).

  Returns `:ok` on success, or `{:error, :already_registered}`.
  """
  @spec register(
          GenServer.server(),
          service_name(),
          (-> :ok | {:error, term()}),
          pos_integer(),
          keyword()
        ) :: :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, opts \\ []) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end

  @doc """
  Returns the current status information for a single service.

  Returns `{:ok, status_info}` or `{:error, :not_found}`.
  """
  @spec status(GenServer.server(), service_name()) ::
          {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @doc """
  Returns a map of every registered service name to its `status_info` map.
  """
  @spec statuses(GenServer.server()) :: %{service_name() => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  @doc """
  Deregisters a service. Always returns `:ok`.
  """
  @spec deregister(GenServer.server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    notify = Keyword.get(opts, :notify, nil)

    {:ok, %{services: %{}, clock: clock, notify: notify}}
  end

  @impl GenServer
  def handle_call({:register, name, check_func, interval_ms, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      window_size = Keyword.get(opts, :window_size, 5)
      threshold = Keyword.get(opts, :threshold, 0.6)

      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        window_size: window_size,
        threshold: threshold,
        status: :pending,
        last_check_at: nil,
        history: [],
        notified_down: false
      }

      schedule_check(name, interval_ms)

      {:reply, :ok, put_in(state.services[name], service)}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:reply, {:ok, to_status_info(service)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result = Map.new(state.services, fn {name, svc} -> {name, to_status_info(svc)} end)
    {:reply, result, state}
  end

  def handle_call({:deregister, name}, _from, state) do
    {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
  end

  @impl GenServer
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        # Service was deregistered; discard stale message.
        {:noreply, state}

      {:ok, service} ->
        now = state.clock.()
        result = service.check_func.()

        {new_service, notify?} = apply_check_result(service, result, now)

        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

        if notify? do
          fire_notify(state.notify, name, compute_failure_rate(new_service.history))
        end

        {:noreply, new_state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec apply_check_result(service(), :ok | {:error, term()}, integer()) ::
          {service(), boolean()}
  defp apply_check_result(service, result, now) do
    outcome =
      case result do
        :ok -> :ok
        {:error, _} -> :error
      end

    # Append to history, bounded by window_size.
    new_history =
      (service.history ++ [outcome])
      |> Enum.take(-service.window_size)

    failure_rate = compute_failure_rate(new_history)
    window_full = length(new_history) >= service.window_size

    new_status =
      cond do
        window_full && failure_rate >= service.threshold -> :down
        window_full -> :up
        # Window not yet full: if there are no errors so far, show :up;
        # otherwise stay :pending.
        failure_rate == 0.0 && length(new_history) > 0 -> :up
        true -> service.status |> maybe_upgrade_pending(outcome)
      end

    # Notification fires exactly on the transition into :down.
    notify? = new_status == :down && !service.notified_down && service.status != :down

    notified_down =
      cond do
        new_status == :down -> service.notified_down || notify?
        # When recovering from :down, reset the flag so future transitions
        # trigger a fresh notification.
        service.status == :down -> false
        true -> service.notified_down
      end

    new_service = %{
      service
      | status: new_status,
        last_check_at: now,
        history: new_history,
        notified_down: notified_down
    }

    {new_service, notify?}
  end

  # If pending and we just got an :ok, move to :up. Otherwise keep current.
  defp maybe_upgrade_pending(:pending, :ok), do: :up
  defp maybe_upgrade_pending(current, _), do: current

  @spec compute_failure_rate(list(:ok | :error)) :: float()
  defp compute_failure_rate([]), do: 0.0

  defp compute_failure_rate(history) do
    errors = Enum.count(history, &(&1 == :error))
    errors / length(history)
  end

  @spec schedule_check(service_name(), pos_integer()) :: reference()
  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end

  @spec to_status_info(service()) :: status_info()
  defp to_status_info(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      failure_rate: compute_failure_rate(service.history),
      checks_in_window: length(service.history)
    }
  end

  @spec fire_notify((service_name(), float() -> any()) | nil, service_name(), float()) :: any()
  defp fire_notify(nil, _name, _rate), do: :ok
  defp fire_notify(notify_fn, name, rate), do: notify_fn.(name, rate)
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule RateMonitorTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  # --- Notification collector ---

  defmodule Notifications do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def record(service, failure_rate) do
      Agent.update(__MODULE__, &[{service, failure_rate} | &1])
    end

    def all, do: Agent.get(__MODULE__, &Enum.reverse/1)
    def count, do: Agent.get(__MODULE__, &length/1)
    def clear, do: Agent.update(__MODULE__, fn _ -> [] end)
  end

  # --- Controllable check function ---

  defmodule CheckFn do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def set_result(service, result) do
      Agent.update(__MODULE__, &Map.put(&1, service, result))
    end

    def build(service) do
      fn -> Agent.get(__MODULE__, &Map.get(&1, service, :ok)) end
    end
  end

  setup do
    start_supervised!({Clock, 0})
    start_supervised!(Notifications)
    start_supervised!(CheckFn)

    {:ok, pid} =
      RateMonitor.start_link(
        clock: &Clock.now/0,
        notify: &Notifications.record/2
      )

    %{mon: pid}
  end

  defp trigger_check(mon, service_name) do
    send(mon, {:check, service_name})
    _ = RateMonitor.status(mon, service_name)
  end

  # Poll `fun` until it returns true or the deadline is exhausted. Used to
  # observe an effect that surfaces only through the public API, without
  # sizing a single fixed sleep to any interval.
  defp poll_until(fun, deadline_ms) do
    cond do
      fun.() ->
        :ok

      deadline_ms <= 0 ->
        :timeout

      true ->
        Process.sleep(5)
        poll_until(fun, deadline_ms - 5)
    end
  end

  # -------------------------------------------------------
  # Registration
  # -------------------------------------------------------

  test "newly registered service starts in :pending status", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = RateMonitor.register(mon, "web", check, 5_000)

    assert {:ok, info} = RateMonitor.status(mon, "web")
    assert info.status == :pending
    assert info.failure_rate == 0.0
    assert info.checks_in_window == 0
    assert info.last_check_at == nil
  end

  test "cannot register the same service name twice", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = RateMonitor.register(mon, "web", check, 5_000)
    assert {:error, :already_registered} = RateMonitor.register(mon, "web", check, 5_000)
  end

  test "status returns :not_found for unregistered service", %{mon: mon} do
    assert {:error, :not_found} = RateMonitor.status(mon, "ghost")
  end

  # -------------------------------------------------------
  # Automatic periodic scheduling
  # -------------------------------------------------------

  test "registered checks run automatically on the periodic timer", %{mon: mon} do
    CheckFn.set_result("timer_svc", :ok)
    RateMonitor.register(mon, "timer_svc", CheckFn.build("timer_svc"), 25)

    # No manual {:check, _} is ever sent here; only the periodic timer can
    # advance the window, so observing a completed check proves scheduling.
    assert :ok =
             poll_until(
               fn ->
                 case RateMonitor.status(mon, "timer_svc") do
                   {:ok, %{checks_in_window: n}} -> n >= 1
                   _ -> false
                 end
               end,
               2_000
             )
  end

  # -------------------------------------------------------
  # Successful checks → :up
  # -------------------------------------------------------

  test "service becomes :up after a successful check", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 5_000)

    Clock.advance(5_000)
    trigger_check(mon, "web")

    assert {:ok, info} = RateMonitor.status(mon, "web")
    assert info.status == :up
    assert info.failure_rate == 0.0
    assert info.last_check_at == 5_000
  end

  # -------------------------------------------------------
  # Failure rate and :down transition
  # -------------------------------------------------------

  test "service does NOT go :down before window is full", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    # window_size=5, threshold=0.6
    RateMonitor.register(mon, "db", check, 1_000, window_size: 5, threshold: 0.6)

    # 4 failures — window not full yet (need 5 checks)
    for _i <- 1..4 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, info} = RateMonitor.status(mon, "db")
    refute info.status == :down, "should not be :down before window is full"
    assert info.checks_in_window == 4
  end

  test "a failing check keeps a :pending service :pending before the window fills",
       %{mon: mon} do
    CheckFn.set_result("db2", {:error, :timeout})
    RateMonitor.register(mon, "db2", CheckFn.build("db2"), 1_000, window_size: 5, threshold: 0.6)

    # One failed check in a partial window: it cannot be :down, and because the
    # single outcome is an error the service must stay :pending (not flip :up).
    Clock.advance(1_000)
    trigger_check(mon, "db2")

    assert {:ok, info} = RateMonitor.status(mon, "db2")
    assert info.status == :pending
    assert info.checks_in_window == 1
  end

  test "service goes :down when failure rate >= threshold with full window", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    RateMonitor.register(mon, "db", check, 1_000, window_size: 5, threshold: 0.6)

    # 5 failures → rate = 1.0 >= 0.6
    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, %{status: :down, failure_rate: rate}} = RateMonitor.status(mon, "db")
    assert rate == 1.0
  end

  test "notification fires exactly once on transition to :down", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    RateMonitor.register(mon, "db", check, 1_000, window_size: 3, threshold: 0.6)

    # 3 failures → rate = 1.0 >= 0.6 → :down
    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert Notifications.count() == 1

    # A 4th failure should NOT trigger another notification
    Clock.advance(1_000)
    trigger_check(mon, "db")

    assert Notifications.count() == 1
  end

  test "notification includes the failure rate", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    RateMonitor.register(mon, "db", check, 1_000, window_size: 3, threshold: 0.6)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    [{name, rate}] = Notifications.all()
    assert name == "db"
    assert rate == 1.0
  end

  # -------------------------------------------------------
  # Mixed results — rate-based detection
  # -------------------------------------------------------

  test "intermittent failures below threshold keep service :up", %{mon: mon} do
    check = CheckFn.build("flaky")
    RateMonitor.register(mon, "flaky", check, 1_000, window_size: 5, threshold: 0.6)

    # Pattern: ok, error, ok, ok, error → 2/5 = 0.4 < 0.6
    results = [:ok, {:error, :flaky}, :ok, :ok, {:error, :flaky}]

    for result <- results do
      CheckFn.set_result("flaky", result)
      Clock.advance(1_000)
      trigger_check(mon, "flaky")
    end

    assert {:ok, %{status: :up, failure_rate: rate}} = RateMonitor.status(mon, "flaky")
    assert_in_delta rate, 0.4, 0.01
    assert Notifications.count() == 0
  end

  test "failure rate at exactly threshold triggers :down", %{mon: mon} do
    check = CheckFn.build("svc")
    # window_size=5, threshold=0.6 → need 3/5 errors = 0.6
    RateMonitor.register(mon, "svc", check, 1_000, window_size: 5, threshold: 0.6)

    # 2 ok then 3 errors → 3/5 = 0.6
    results = [:ok, :ok, {:error, :a}, {:error, :b}, {:error, :c}]

    for result <- results do
      CheckFn.set_result("svc", result)
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: :down, failure_rate: rate}} = RateMonitor.status(mon, "svc")
    assert_in_delta rate, 0.6, 0.01
    assert Notifications.count() == 1
  end

  # -------------------------------------------------------
  # Recovery from :down → :up
  # -------------------------------------------------------

  test "a :down service recovers when failure rate drops below threshold", %{mon: mon} do
    # TODO
  end

  test "notification fires again if service goes down a second time after recovery", %{mon: mon} do
    check = CheckFn.build("api")
    RateMonitor.register(mon, "api", check, 1_000, window_size: 3, threshold: 0.6)

    # First down: 3 errors
    CheckFn.set_result("api", {:error, :crash})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 1

    # Recover: 3 successes push all errors out → [ok, ok, ok] → rate = 0.0
    CheckFn.set_result("api", :ok)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert {:ok, %{status: :up}} = RateMonitor.status(mon, "api")

    # Second down: 3 errors again
    CheckFn.set_result("api", {:error, :oom})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 2
  end

  # -------------------------------------------------------
  # Window sliding behavior
  # -------------------------------------------------------

  test "old results are evicted from the window", %{mon: mon} do
    check = CheckFn.build("svc")
    RateMonitor.register(mon, "svc", check, 1_000, window_size: 3, threshold: 0.6)

    # 3 errors → [err, err, err] → :down
    CheckFn.set_result("svc", {:error, :x})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "svc")

    # 3 successes → [ok, ok, ok] — old errors are fully evicted
    CheckFn.set_result("svc", :ok)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: :up, failure_rate: +0.0, checks_in_window: 3}} =
             RateMonitor.status(mon, "svc")
  end

  test "checks_in_window never exceeds window_size", %{mon: mon} do
    check = CheckFn.build("svc")
    RateMonitor.register(mon, "svc", check, 1_000, window_size: 3)

    CheckFn.set_result("svc", :ok)

    for _ <- 1..10 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{checks_in_window: 3}} = RateMonitor.status(mon, "svc")
  end

  # -------------------------------------------------------
  # Custom window_size and threshold
  # -------------------------------------------------------

  test "custom window_size and threshold are respected", %{mon: mon} do
    check = CheckFn.build("cache")
    # window_size=4, threshold=0.75 → need 3/4 errors
    RateMonitor.register(mon, "cache", check, 500, window_size: 4, threshold: 0.75)

    # 2 errors, 2 ok → rate = 0.5 < 0.75
    CheckFn.set_result("cache", {:error, :conn_refused})
    Clock.advance(500)
    trigger_check(mon, "cache")
    Clock.advance(500)
    trigger_check(mon, "cache")

    CheckFn.set_result("cache", :ok)
    Clock.advance(500)
    trigger_check(mon, "cache")
    Clock.advance(500)
    trigger_check(mon, "cache")

    assert {:ok, %{status: :up}} = RateMonitor.status(mon, "cache")
    assert Notifications.count() == 0
  end

  # -------------------------------------------------------
  # Deregistration
  # -------------------------------------------------------

  test "deregistering a service removes it from statuses", %{mon: mon} do
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 1_000)

    assert :ok = RateMonitor.deregister(mon, "web")
    assert {:error, :not_found} = RateMonitor.status(mon, "web")
    assert RateMonitor.statuses(mon) == %{}
  end

  test "deregistering is idempotent", %{mon: mon} do
    assert :ok = RateMonitor.deregister(mon, "nonexistent")
  end

  test "stale check message after deregister has no effect", %{mon: mon} do
    CheckFn.set_result("web", {:error, :boom})
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 1_000)
    RateMonitor.deregister(mon, "web")

    send(mon, {:check, "web"})
    _ = RateMonitor.statuses(mon)

    assert {:error, :not_found} = RateMonitor.status(mon, "web")
    assert Notifications.count() == 0
  end

  test "can re-register a service after deregistering it", %{mon: mon} do
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 1_000)
    RateMonitor.deregister(mon, "web")
    assert :ok = RateMonitor.register(mon, "web", check, 1_000)

    assert {:ok, %{status: :pending, checks_in_window: 0}} =
             RateMonitor.status(mon, "web")
  end

  # -------------------------------------------------------
  # statuses/1 returns all services
  # -------------------------------------------------------

  test "statuses returns a map of all registered services", %{mon: mon} do
    RateMonitor.register(mon, "web", CheckFn.build("web"), 1_000)
    RateMonitor.register(mon, "db", CheckFn.build("db"), 2_000)
    RateMonitor.register(mon, "cache", CheckFn.build("cache"), 500)

    all = RateMonitor.statuses(mon)
    assert Map.keys(all) |> Enum.sort() == ["cache", "db", "web"]

    for {_name, info} <- all do
      assert info.status == :pending
    end
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "failure on one service does not affect another", %{mon: mon} do
    CheckFn.set_result("bad", {:error, :fail})
    CheckFn.set_result("good", :ok)
    RateMonitor.register(mon, "bad", CheckFn.build("bad"), 1_000, window_size: 3, threshold: 0.6)
    RateMonitor.register(mon, "good", CheckFn.build("good"), 1_000)

    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "bad")
      trigger_check(mon, "good")
    end

    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "bad")
    assert {:ok, %{status: :up, failure_rate: +0.0}} = RateMonitor.status(mon, "good")
  end

  # -------------------------------------------------------
  # Robustness — unexpected messages
  # -------------------------------------------------------

  test "unexpected messages are ignored and do not alter service state", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    RateMonitor.register(mon, "web", CheckFn.build("web"), 5_000)

    send(mon, :some_unexpected_message)
    send(mon, {:not_a_check, "web"})

    # A synchronous call after the sends is processed strictly after them, so
    # it proves the process survived and no service state was disturbed.
    assert {:ok, info} = RateMonitor.status(mon, "web")
    assert info.status == :pending
    assert info.checks_in_window == 0
    assert info.last_check_at == nil
    assert Process.alive?(mon)
  end

  # -------------------------------------------------------
  # last_check_at tracking
  # -------------------------------------------------------

  test "last_check_at reflects the timestamp of the most recent check", %{mon: mon} do
    CheckFn.set_result("svc", :ok)
    RateMonitor.register(mon, "svc", CheckFn.build("svc"), 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 1_000}} = RateMonitor.status(mon, "svc")

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 2_000}} = RateMonitor.status(mon, "svc")
  end
end
```
