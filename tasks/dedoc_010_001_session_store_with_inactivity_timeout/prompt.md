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
defmodule SessionStore do
  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_timeout_ms 1_800_000
  @default_cleanup_interval_ms 60_000
  @default_clock &__MODULE__.__default_clock__/0

  # Public so the default fn literal can reference it without capturing a
  # private function (which would break in some compilation contexts).
  def __default_clock__, do: System.monotonic_time(:millisecond)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name_opt, init_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, init_opts, name_opt)
  end

  def create(server, session_data) do
    GenServer.call(server, {:create, session_data})
  end

  def get(server, session_id) do
    GenServer.call(server, {:get, session_id})
  end

  def update(server, session_id, new_data) do
    GenServer.call(server, {:update, session_id, new_data})
  end

  def touch(server, session_id) do
    GenServer.call(server, {:touch, session_id})
  end

  def destroy(server, session_id) do
    GenServer.call(server, {:destroy, session_id})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, @default_clock)

    state = %{
      sessions: %{},
      timeout_ms: timeout_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:create, session_data}, _from, state) do
    session_id = generate_session_id()
    now = state.clock.()

    session = %{data: session_data, last_active: now}
    new_sessions = Map.put(state.sessions, session_id, session)

    {:reply, {:ok, session_id}, %{state | sessions: new_sessions}}
  end

  def handle_call({:get, session_id}, _from, state) do
    now = state.clock.()

    case fetch_live_session(state.sessions, session_id, now, state.timeout_ms) do
      {:ok, session} ->
        updated_session = %{session | last_active: now}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        {:reply, {:ok, session.data}, %{state | sessions: new_sessions}}

      :expired ->
        new_sessions = Map.delete(state.sessions, session_id)
        {:reply, {:error, :not_found}, %{state | sessions: new_sessions}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:update, session_id, new_data}, _from, state) do
    now = state.clock.()

    case fetch_live_session(state.sessions, session_id, now, state.timeout_ms) do
      {:ok, session} ->
        updated_session = %{session | data: new_data, last_active: now}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        {:reply, {:ok, new_data}, %{state | sessions: new_sessions}}

      :expired ->
        new_sessions = Map.delete(state.sessions, session_id)
        {:reply, {:error, :not_found}, %{state | sessions: new_sessions}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:touch, session_id}, _from, state) do
    now = state.clock.()

    case fetch_live_session(state.sessions, session_id, now, state.timeout_ms) do
      {:ok, session} ->
        updated_session = %{session | last_active: now}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        {:reply, :ok, %{state | sessions: new_sessions}}

      :expired ->
        new_sessions = Map.delete(state.sessions, session_id)
        {:reply, {:error, :not_found}, %{state | sessions: new_sessions}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:destroy, session_id}, _from, state) do
    new_sessions = Map.delete(state.sessions, session_id)
    {:reply, :ok, %{state | sessions: new_sessions}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    surviving_sessions =
      Map.filter(state.sessions, fn {_id, session} ->
        not expired?(session, now, state.timeout_ms)
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | sessions: surviving_sessions}}
  end

  # Catch-all for unexpected messages — keeps the process alive and logs.
  def handle_info(msg, state) do
    require Logger
    Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Generates a URL-safe, base64-encoded, 16-byte random session ID (~22 chars).
  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  # Schedules the next periodic sweep.
  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp schedule_cleanup(_), do: :ok

  # Returns whether a session's sliding deadline has passed.
  defp expired?(session, now, timeout_ms) do
    now - session.last_active >= timeout_ms
  end

  # Looks up a session and classifies it as live, expired, or missing.
  defp fetch_live_session(sessions, session_id, now, timeout_ms) do
    case Map.fetch(sessions, session_id) do
      {:ok, session} ->
        if expired?(session, now, timeout_ms), do: :expired, else: {:ok, session}

      :error ->
        :missing
    end
  end
end
```
