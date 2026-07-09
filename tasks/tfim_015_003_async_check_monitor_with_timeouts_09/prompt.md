# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule AsyncMonitor do
  @moduledoc """
  A GenServer that monitors registered services via periodic health checks
  where each check runs asynchronously in a spawned Task with a configurable
  timeout.

  Unlike a synchronous monitor, this design prevents slow check functions from
  blocking the GenServer. Each check is spawned as a separate process, and a
  timeout timer ensures the GenServer isn't stuck waiting indefinitely.
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
          consecutive_failures: non_neg_integer(),
          check_in_flight: boolean()
        }

  @typep service :: %{
           check_func: (-> :ok | {:error, term()}),
           interval_ms: pos_integer(),
           max_failures: pos_integer(),
           timeout_ms: pos_integer(),
           status: status(),
           last_check_at: integer() | nil,
           consecutive_failures: non_neg_integer(),
           notified_down: boolean(),
           task_ref: reference() | nil,
           task_pid: pid() | nil
         }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opt, gen_opts} =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> {[name: name], []}
        :error -> {[], []}
      end

    GenServer.start_link(__MODULE__, opts, gen_opts ++ name_opt)
  end

  @doc "Registers `service_name` with an async `check_func`. Returns `:ok`."
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

  @spec status(GenServer.server(), service_name()) ::
          {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @spec statuses(GenServer.server()) :: %{service_name() => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

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
      max_failures = Keyword.get(opts, :max_failures, 3)
      timeout_ms = Keyword.get(opts, :timeout_ms, 5_000)

      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        max_failures: max_failures,
        timeout_ms: timeout_ms,
        status: :pending,
        last_check_at: nil,
        consecutive_failures: 0,
        notified_down: false,
        task_ref: nil,
        task_pid: nil
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
    case Map.fetch(state.services, name) do
      {:ok, service} ->
        # Kill any in-flight task.
        if service.task_pid do
          Process.exit(service.task_pid, :kill)
        end

        {:reply, :ok, %{state | services: Map.delete(state.services, name)}}

      :error ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_info({:schedule_check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, service} ->
        # Spawn a Task to run the check function.
        gen_server = self()
        ref = make_ref()

        {:ok, pid} =
          Task.start(fn ->
            result =
              try do
                service.check_func.()
              rescue
                e -> {:error, {:exception, Exception.message(e)}}
              catch
                kind, value -> {:error, {kind, value}}
              end

            send(gen_server, {:check_result, name, ref, result})
          end)

        # Monitor the task so we know if it crashes.
        Process.monitor(pid)

        # Schedule a timeout message.
        Process.send_after(self(), {:check_timeout, name, ref}, service.timeout_ms)

        new_service = %{service | task_ref: ref, task_pid: pid}
        {:noreply, put_in(state.services[name], new_service)}
    end
  end

  def handle_info({:check_result, name, ref, result}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, %{task_ref: ^ref} = service} ->
        now = state.clock.()
        {new_service, notify?} = apply_check_result(service, result, now)
        new_service = %{new_service | task_ref: nil, task_pid: nil}

        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

        if notify? do
          {:error, reason} = result
          fire_notify(state.notify, name, reason)
        end

        {:noreply, new_state}

      {:ok, _service} ->
        # Stale ref — result from an old task. Discard.
        {:noreply, state}
    end
  end

  def handle_info({:check_timeout, name, ref}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, %{task_ref: ^ref, task_pid: pid} = service} ->
        # Kill the timed-out task.
        if pid, do: Process.exit(pid, :kill)

        now = state.clock.()
        {new_service, notify?} = apply_check_result(service, {:error, :timeout}, now)
        new_service = %{new_service | task_ref: nil, task_pid: nil}

        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

        if notify? do
          fire_notify(state.notify, name, :timeout)
        end

        {:noreply, new_state}

      {:ok, _service} ->
        # Stale ref — timeout for an already-completed or replaced task.
        {:noreply, state}
    end
  end

  # Handle DOWN messages from monitored tasks — just ignore them.
  # We handle lifecycle via check_result/check_timeout.
  def handle_info({:DOWN, _monitor_ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec apply_check_result(service(), :ok | {:error, term()}, integer()) ::
          {service(), boolean()}
  defp apply_check_result(service, :ok, now) do
    new_service = %{
      service
      | status: :up,
        last_check_at: now,
        consecutive_failures: 0,
        notified_down: false
    }

    {new_service, false}
  end

  defp apply_check_result(service, {:error, _reason}, now) do
    new_failures = service.consecutive_failures + 1
    threshold_reached = new_failures >= service.max_failures

    notify? = threshold_reached && !service.notified_down

    new_status = if threshold_reached, do: :down, else: service.status

    new_service = %{
      service
      | status: new_status,
        last_check_at: now,
        consecutive_failures: new_failures,
        notified_down: service.notified_down || notify?
    }

    {new_service, notify?}
  end

  @spec schedule_check(service_name(), pos_integer()) :: reference()
  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:schedule_check, name}, interval_ms)
  end

  @spec to_status_info(service()) :: status_info()
  defp to_status_info(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      check_in_flight: service.task_ref != nil
    }
  end

  @spec fire_notify((service_name(), term() -> any()) | nil, service_name(), term()) :: any()
  defp fire_notify(nil, _name, _reason), do: :ok
  defp fire_notify(notify_fn, name, reason), do: notify_fn.(name, reason)
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule AsyncMonitorTest do
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

    def record(service, reason) do
      Agent.update(__MODULE__, &[{service, reason} | &1])
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

    @doc "Build a check function that blocks forever (for timeout tests)."
    def build_blocking do
      fn -> Process.sleep(:infinity) end
    end
  end

  setup do
    start_supervised!({Clock, 0})
    start_supervised!(Notifications)
    start_supervised!(CheckFn)

    {:ok, pid} =
      AsyncMonitor.start_link(
        clock: &Clock.now/0,
        notify: &Notifications.record/2
      )

    %{mon: pid}
  end

  # Helper: trigger the async check cycle and wait for the result to be
  # processed. We send :schedule_check, then do a synchronous call to
  # ensure both the spawn and the result message have been processed.
  defp trigger_check(mon, service_name) do
    send(mon, {:schedule_check, service_name})
    # First sync: ensures the task is spawned.
    _ = AsyncMonitor.status(mon, service_name)
    # Small sleep to let the Task execute and send its result back.
    Process.sleep(10)
    # Second sync: ensures the result message is processed.
    _ = AsyncMonitor.status(mon, service_name)
  end

  # Helper: trigger a check and then fire the timeout (for timeout tests).
  defp trigger_check_with_timeout(mon, service_name) do
    send(mon, {:schedule_check, service_name})
    # Sync to ensure task is spawned.
    {:ok, _info} = AsyncMonitor.status(mon, service_name)

    # Now manually send the timeout message (the real timer would fire later).
    # We need to get the task_ref, but it's internal. Instead, we send the
    # timeout as if the timer fired — the GenServer will match on the ref.
    # Since we can't easily access the ref, we trigger it by sending the
    # :check_timeout with the current ref by asking the GenServer to process it.
    # In practice, we simulate by waiting briefly then checking status.

    # For testing, we use a very short timeout_ms so the real timer fires.
    Process.sleep(20)
    _ = AsyncMonitor.status(mon, service_name)
  end

  # -------------------------------------------------------
  # Registration
  # -------------------------------------------------------

  test "newly registered service starts in :pending status", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = AsyncMonitor.register(mon, "web", check, 5_000)

    assert {:ok, info} = AsyncMonitor.status(mon, "web")
    assert info.status == :pending
    assert info.consecutive_failures == 0
    assert info.last_check_at == nil
    assert info.check_in_flight == false
  end

  test "cannot register the same service name twice", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = AsyncMonitor.register(mon, "web", check, 5_000)
    assert {:error, :already_registered} = AsyncMonitor.register(mon, "web", check, 5_000)
  end

  test "status returns :not_found for unregistered service", %{mon: mon} do
    assert {:error, :not_found} = AsyncMonitor.status(mon, "ghost")
  end

  # -------------------------------------------------------
  # Successful checks → :up
  # -------------------------------------------------------

  test "service becomes :up after a successful async check", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 5_000)

    Clock.advance(5_000)
    trigger_check(mon, "web")

    assert {:ok, info} = AsyncMonitor.status(mon, "web")
    assert info.status == :up
    assert info.consecutive_failures == 0
    assert info.last_check_at == 5_000
    assert info.check_in_flight == false
  end

  # -------------------------------------------------------
  # Failures and :down transition
  # -------------------------------------------------------

  test "service goes :down after max_failures consecutive failures (default 3)", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    AsyncMonitor.register(mon, "db", check, 1_000)

    for _i <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, %{status: :down, consecutive_failures: 3}} =
             AsyncMonitor.status(mon, "db")
  end

  test "notification fires exactly once on transition to :down", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    AsyncMonitor.register(mon, "db", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert Notifications.all() == [{"db", :timeout}]

    # A 4th failure should NOT trigger another notification
    Clock.advance(1_000)
    trigger_check(mon, "db")

    assert Notifications.count() == 1
  end

  test "custom max_failures is respected", %{mon: mon} do
    CheckFn.set_result("cache", {:error, :conn_refused})
    check = CheckFn.build("cache")
    AsyncMonitor.register(mon, "cache", check, 500, max_failures: 5)

    for _ <- 1..4 do
      Clock.advance(500)
      trigger_check(mon, "cache")
    end

    assert {:ok, %{status: status}} = AsyncMonitor.status(mon, "cache")
    refute status == :down, "should not be :down after only 4 failures with max_failures=5"

    Clock.advance(500)
    trigger_check(mon, "cache")

    assert {:ok, %{status: :down, consecutive_failures: 5}} =
             AsyncMonitor.status(mon, "cache")

    assert Notifications.count() == 1
  end

  # -------------------------------------------------------
  # Timeout handling
  # -------------------------------------------------------

  test "a check that exceeds timeout_ms is treated as a failure", %{mon: mon} do
    # TODO
  end

  # -------------------------------------------------------
  # Recovery from :down → :up
  # -------------------------------------------------------

  test "a :down service recovers to :up when check succeeds", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    AsyncMonitor.register(mon, "api", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert {:ok, %{status: :down}} = AsyncMonitor.status(mon, "api")

    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    assert {:ok, %{status: :up, consecutive_failures: 0}} =
             AsyncMonitor.status(mon, "api")
  end

  test "notification fires again on a second down after recovery", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    AsyncMonitor.register(mon, "api", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 1

    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    CheckFn.set_result("api", {:error, :oom})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 2
    assert Notifications.all() == [{"api", :crash}, {"api", :oom}]
  end

  # -------------------------------------------------------
  # Success resets failure counter
  # -------------------------------------------------------

  test "a success in between failures resets the counter", %{mon: mon} do
    CheckFn.set_result("svc", {:error, :flaky})
    check = CheckFn.build("svc")
    AsyncMonitor.register(mon, "svc", check, 1_000)

    for _ <- 1..2 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{consecutive_failures: 2}} = AsyncMonitor.status(mon, "svc")

    CheckFn.set_result("svc", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "svc")

    assert {:ok, %{consecutive_failures: 0, status: :up}} =
             AsyncMonitor.status(mon, "svc")

    CheckFn.set_result("svc", {:error, :flaky})

    for _ <- 1..2 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: status}} = AsyncMonitor.status(mon, "svc")
    refute status == :down
  end

  # -------------------------------------------------------
  # Deregistration
  # -------------------------------------------------------

  test "deregistering a service removes it from statuses", %{mon: mon} do
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 1_000)

    assert :ok = AsyncMonitor.deregister(mon, "web")
    assert {:error, :not_found} = AsyncMonitor.status(mon, "web")
    assert AsyncMonitor.statuses(mon) == %{}
  end

  test "deregistering is idempotent", %{mon: mon} do
    assert :ok = AsyncMonitor.deregister(mon, "nonexistent")
  end

  test "stale schedule message after deregister has no effect", %{mon: mon} do
    CheckFn.set_result("web", {:error, :boom})
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 1_000)
    AsyncMonitor.deregister(mon, "web")

    send(mon, {:schedule_check, "web"})
    _ = AsyncMonitor.statuses(mon)
    Process.sleep(10)
    _ = AsyncMonitor.statuses(mon)

    assert {:error, :not_found} = AsyncMonitor.status(mon, "web")
    assert Notifications.count() == 0
  end

  test "can re-register a service after deregistering it", %{mon: mon} do
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 1_000)
    AsyncMonitor.deregister(mon, "web")
    assert :ok = AsyncMonitor.register(mon, "web", check, 1_000)

    assert {:ok, %{status: :pending}} = AsyncMonitor.status(mon, "web")
  end

  # -------------------------------------------------------
  # statuses/1 returns all services
  # -------------------------------------------------------

  test "statuses returns a map of all registered services", %{mon: mon} do
    AsyncMonitor.register(mon, "web", CheckFn.build("web"), 1_000)
    AsyncMonitor.register(mon, "db", CheckFn.build("db"), 2_000)
    AsyncMonitor.register(mon, "cache", CheckFn.build("cache"), 500)

    all = AsyncMonitor.statuses(mon)
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
    AsyncMonitor.register(mon, "bad", CheckFn.build("bad"), 1_000)
    AsyncMonitor.register(mon, "good", CheckFn.build("good"), 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "bad")
      trigger_check(mon, "good")
    end

    assert {:ok, %{status: :down}} = AsyncMonitor.status(mon, "bad")
    assert {:ok, %{status: :up, consecutive_failures: 0}} = AsyncMonitor.status(mon, "good")
  end

  # -------------------------------------------------------
  # last_check_at tracking
  # -------------------------------------------------------

  test "last_check_at reflects the timestamp of the most recent check", %{mon: mon} do
    CheckFn.set_result("svc", :ok)
    AsyncMonitor.register(mon, "svc", CheckFn.build("svc"), 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 1_000}} = AsyncMonitor.status(mon, "svc")

    Clock.advance(1_000)
    trigger_check(mon, "svc")
    assert {:ok, %{last_check_at: 2_000}} = AsyncMonitor.status(mon, "svc")
  end

  # -------------------------------------------------------
  # Notification reason accuracy
  # -------------------------------------------------------

  test "notification carries the reason from the final failing check", %{mon: mon} do
    check = CheckFn.build("svc")
    AsyncMonitor.register(mon, "svc", check, 1_000)

    CheckFn.set_result("svc", {:error, :first_issue})
    Clock.advance(1_000)
    trigger_check(mon, "svc")

    CheckFn.set_result("svc", {:error, :second_issue})
    Clock.advance(1_000)
    trigger_check(mon, "svc")

    CheckFn.set_result("svc", {:error, :final_issue})
    Clock.advance(1_000)
    trigger_check(mon, "svc")

    assert [{"svc", :final_issue}] = Notifications.all()
  end
end
```
