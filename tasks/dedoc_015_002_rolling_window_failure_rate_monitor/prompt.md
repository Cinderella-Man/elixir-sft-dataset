# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule RateMonitor do
  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name_opt, gen_opts} =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> {[name: name], []}
        :error -> {[], []}
      end

    GenServer.start_link(__MODULE__, opts, gen_opts ++ name_opt)
  end

  def register(server, service_name, check_func, interval_ms, opts \\ []) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end

  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  def statuses(server) do
    GenServer.call(server, :statuses)
  end

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
        notified_down: false,
        check_timer: nil
      }

      service = %{service | check_timer: schedule_check(name, interval_ms)}

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
        # Kill the whole check chain: the armed timer AND any {:check, name}
        # already sitting in the mailbox — the old registration's leftover
        # timers must not drive a later re-registration of the same name.
        if service.check_timer, do: Process.cancel_timer(service.check_timer)

        receive do
          {:check, ^name} -> :ok
        after
          0 -> :ok
        end

      :error ->
        :ok
    end

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
        new_service = rearm(new_service, name)

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

  defp compute_failure_rate([]), do: 0.0

  defp compute_failure_rate(history) do
    errors = Enum.count(history, &(&1 == :error))
    errors / length(history)
  end

  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end

  # One chain per service, always: cancel whatever is armed before arming the
  # successor, so a manual {:check, name} reschedules the cadence instead of
  # spawning a second timer chain alongside the periodic one.
  defp rearm(service, name) do
    if service.check_timer, do: Process.cancel_timer(service.check_timer)
    %{service | check_timer: schedule_check(name, service.interval_ms)}
  end

  defp to_status_info(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      failure_rate: compute_failure_rate(service.history),
      checks_in_window: length(service.history)
    }
  end

  defp fire_notify(nil, _name, _rate), do: :ok
  defp fire_notify(notify_fn, name, rate), do: notify_fn.(name, rate)
end
```
