# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule OneTimeTokenStore do
  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_ttl_ms 3_600_000
  @default_cleanup_interval_ms 60_000
  @default_clock &__MODULE__.__default_clock__/0

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

  def mint(server, payload, opts \\ []) do
    GenServer.call(server, {:mint, payload, opts})
  end

  def verify(server, token_id) do
    GenServer.call(server, {:verify, token_id})
  end

  def redeem(server, token_id) do
    GenServer.call(server, {:redeem, token_id})
  end

  def revoke(server, token_id) do
    GenServer.call(server, {:revoke, token_id})
  end

  def active_count(server) do
    GenServer.call(server, :active_count)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    default_ttl_ms = Keyword.get(opts, :default_ttl_ms, @default_ttl_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, @default_clock)

    state = %{
      tokens: %{},
      default_ttl_ms: default_ttl_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:mint, payload, opts}, _from, state) do
    token_id = generate_token_id()
    now = state.clock.()
    ttl_ms = Keyword.get(opts, :ttl_ms, state.default_ttl_ms)

    token = %{payload: payload, expires_at: now + ttl_ms}
    new_tokens = Map.put(state.tokens, token_id, token)

    {:reply, {:ok, token_id}, %{state | tokens: new_tokens}}
  end

  def handle_call({:verify, token_id}, _from, state) do
    now = state.clock.()

    case fetch_live_token(state.tokens, token_id, now) do
      {:ok, token} ->
        {:reply, {:ok, token.payload}, state}

      :expired ->
        new_tokens = Map.delete(state.tokens, token_id)
        {:reply, {:error, :not_found}, %{state | tokens: new_tokens}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:redeem, token_id}, _from, state) do
    now = state.clock.()

    case fetch_live_token(state.tokens, token_id, now) do
      {:ok, token} ->
        new_tokens = Map.delete(state.tokens, token_id)
        {:reply, {:ok, token.payload}, %{state | tokens: new_tokens}}

      :expired ->
        new_tokens = Map.delete(state.tokens, token_id)
        {:reply, {:error, :not_found}, %{state | tokens: new_tokens}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:revoke, token_id}, _from, state) do
    new_tokens = Map.delete(state.tokens, token_id)
    {:reply, :ok, %{state | tokens: new_tokens}}
  end

  def handle_call(:active_count, _from, state) do
    now = state.clock.()

    count =
      Enum.count(state.tokens, fn {_id, token} ->
        not expired?(token, now)
      end)

    {:reply, count, state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    surviving_tokens =
      Map.filter(state.tokens, fn {_id, token} ->
        not expired?(token, now)
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | tokens: surviving_tokens}}
  end

  def handle_info(msg, state) do
    require Logger
    Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp generate_token_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp schedule_cleanup(_), do: :ok

  defp expired?(token, now) do
    now >= token.expires_at
  end

  defp fetch_live_token(tokens, token_id, now) do
    case Map.fetch(tokens, token_id) do
      {:ok, token} ->
        if expired?(token, now), do: :expired, else: {:ok, token}

      :error ->
        :missing
    end
  end
end
```
