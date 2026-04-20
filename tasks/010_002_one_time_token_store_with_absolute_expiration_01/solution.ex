defmodule OneTimeTokenStore do
  @moduledoc """
  A GenServer that manages single-use tokens with absolute expiration.

  Each token holds a payload and an absolute deadline computed at creation
  time. Tokens can be verified (non-destructive) or redeemed (one-time
  consumption). Expiration is absolute — accessing a token never extends
  its lifetime.

  ## Options

    * `:name`               - process registration name (optional)
    * `:default_ttl_ms`     - default token lifetime in ms (default: 3_600_000 / 1 hour)
    * `:cleanup_interval_ms`- how often the sweep runs in ms (default: 60_000 / 1 min)
    * `:clock`              - zero-arity fn returning current time in ms;
                              defaults to `fn -> System.monotonic_time(:millisecond) end`

  ## Examples

      {:ok, pid} = OneTimeTokenStore.start_link(default_ttl_ms: 5_000)

      {:ok, token} = OneTimeTokenStore.mint(pid, %{user_id: 42, action: :reset_password})
      {:ok, %{user_id: 42, action: :reset_password}} = OneTimeTokenStore.verify(pid, token)

      {:ok, %{user_id: 42, action: :reset_password}} = OneTimeTokenStore.redeem(pid, token)
      {:error, :not_found} = OneTimeTokenStore.redeem(pid, token)   # already consumed
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type server :: GenServer.server()
  @type token_id :: String.t()
  @type payload :: term()

  @type token :: %{
          payload: payload(),
          expires_at: integer()
        }

  @type state :: %{
          tokens: %{token_id() => token()},
          default_ttl_ms: non_neg_integer(),
          cleanup_interval_ms: non_neg_integer(),
          clock: (() -> integer())
        }

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_ttl_ms 3_600_000
  @default_cleanup_interval_ms 60_000
  @default_clock &__MODULE__.__default_clock__/0

  @doc false
  def __default_clock__, do: System.monotonic_time(:millisecond)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `OneTimeTokenStore` process.

  ## Options

    * `:name`                - passed directly to `GenServer.start_link/3`
    * `:default_ttl_ms`      - token lifetime (default #{@default_ttl_ms} ms)
    * `:cleanup_interval_ms` - sweep interval (default #{@default_cleanup_interval_ms} ms)
    * `:clock`               - zero-arity fn returning current time in ms
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opt, init_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, init_opts, name_opt)
  end

  @doc """
  Creates a new token containing `payload`.

  Returns `{:ok, token_id}`. The token expires at `now + ttl_ms` and is
  never extended — this is an absolute deadline.

  ## Options

    * `:ttl_ms` - override the default TTL for this specific token
  """
  @spec mint(server(), payload(), keyword()) :: {:ok, token_id()}
  def mint(server, payload, opts \\ []) do
    GenServer.call(server, {:mint, payload, opts})
  end

  @doc """
  Checks whether `token_id` is valid without consuming it.

  Returns `{:ok, payload}` if the token exists and has not expired or
  been redeemed, or `{:error, :not_found}` otherwise.
  """
  @spec verify(server(), token_id()) :: {:ok, payload()} | {:error, :not_found}
  def verify(server, token_id) do
    GenServer.call(server, {:verify, token_id})
  end

  @doc """
  Consumes a valid token, returning its payload and permanently removing it.

  Returns `{:ok, payload}` on success, or `{:error, :not_found}` if the
  token doesn't exist, was already redeemed, or has expired.
  """
  @spec redeem(server(), token_id()) :: {:ok, payload()} | {:error, :not_found}
  def redeem(server, token_id) do
    GenServer.call(server, {:redeem, token_id})
  end

  @doc """
  Invalidates a token without redeeming it.

  Always returns `:ok`, even if the token did not exist.
  """
  @spec revoke(server(), token_id()) :: :ok
  def revoke(server, token_id) do
    GenServer.call(server, {:revoke, token_id})
  end

  @doc """
  Returns the number of tokens that are still valid (not expired, not
  redeemed, not revoked).
  """
  @spec active_count(server()) :: non_neg_integer()
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

  @spec generate_token_id() :: token_id()
  defp generate_token_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp schedule_cleanup(_), do: :ok

  @spec expired?(token(), integer()) :: boolean()
  defp expired?(token, now) do
    now >= token.expires_at
  end

  @spec fetch_live_token(%{token_id() => token()}, token_id(), integer()) ::
          {:ok, token()} | :expired | :missing
  defp fetch_live_token(tokens, token_id, now) do
    case Map.fetch(tokens, token_id) do
      {:ok, token} ->
        if expired?(token, now), do: :expired, else: {:ok, token}

      :error ->
        :missing
    end
  end
end
