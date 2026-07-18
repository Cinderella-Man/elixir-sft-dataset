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
defmodule SingleUseToken do
  use GenServer

  @nonce_size 16
  @mac_size 32

  defmodule State do
    defstruct [:secret, :clock, consumed: MapSet.new()]
  end

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  def start_link(opts) when is_list(opts) do
    secret = Keyword.fetch!(opts, :secret)

    if not is_binary(secret) do
      raise ArgumentError, ":secret must be a binary, got: #{inspect(secret)}"
    end

    clock = Keyword.get(opts, :clock, fn -> System.os_time(:second) end)

    if not is_function(clock, 0) do
      raise ArgumentError, ":clock must be a zero-arity function, got: #{inspect(clock)}"
    end

    server_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> [name: name]
        :error -> []
      end

    GenServer.start_link(__MODULE__, {secret, clock}, server_opts)
  end

  def issue(server, payload, ttl_seconds)
      when is_integer(ttl_seconds) and ttl_seconds > 0 do
    GenServer.call(server, {:issue, payload, ttl_seconds})
  end

  def redeem(server, token) do
    GenServer.call(server, {:redeem, token})
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  def init({secret, clock}) do
    {:ok, %State{secret: secret, clock: clock, consumed: MapSet.new()}}
  end

  @impl true
  def handle_call({:issue, payload, ttl_seconds}, _from, %State{} = state) do
    {:reply, build_token(state, payload, ttl_seconds), state}
  end

  def handle_call({:redeem, token}, _from, %State{} = state) do
    case verify(state, token) do
      {:ok, nonce, payload_bytes} ->
        consumed = MapSet.put(state.consumed, nonce)
        {:reply, {:ok, deserialize(payload_bytes)}, %State{state | consumed: consumed}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ------------------------------------------------------------------
  # Internals
  # ------------------------------------------------------------------

  defp build_token(%State{secret: secret, clock: clock}, payload, ttl_seconds) do
    nonce = :crypto.strong_rand_bytes(@nonce_size)
    issued_at = clock.()
    expires_at = issued_at + ttl_seconds
    payload_bytes = :erlang.term_to_binary(payload)

    signed =
      <<nonce::binary-size(@nonce_size), issued_at::signed-integer-64,
        expires_at::signed-integer-64, byte_size(payload_bytes)::unsigned-integer-32,
        payload_bytes::binary>>

    Base.url_encode64(signed <> mac(secret, signed), padding: false)
  end

  # Runs the full check pipeline. Returns the nonce and raw payload bytes so the
  # caller can consume the nonce only on the fully successful path.
  defp verify(%State{} = state, token) when is_binary(token) do
    with {:ok, raw} <- decode(token),
         {:ok, signed, candidate_mac} <- split_mac(raw),
         {:ok, nonce, expires_at, payload_bytes} <- parse(signed),
         :ok <- check_mac(state.secret, signed, candidate_mac),
         :ok <- check_replay(state.consumed, nonce),
         :ok <- check_expiry(state.clock.(), expires_at) do
      {:ok, nonce, payload_bytes}
    end
  end

  defp verify(%State{}, _token), do: {:error, :malformed}

  defp decode(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, :malformed}
    end
  end

  defp split_mac(raw) when byte_size(raw) > @mac_size do
    signed_size = byte_size(raw) - @mac_size
    {:ok, binary_part(raw, 0, signed_size), binary_part(raw, signed_size, @mac_size)}
  end

  defp split_mac(_raw), do: {:error, :malformed}

  defp parse(
         <<nonce::binary-size(@nonce_size), _issued_at::signed-integer-64,
           expires_at::signed-integer-64, payload_size::unsigned-integer-32,
           payload_bytes::binary>>
       )
       when byte_size(payload_bytes) == payload_size do
    {:ok, nonce, expires_at, payload_bytes}
  end

  defp parse(_signed), do: {:error, :malformed}

  defp check_mac(secret, signed, candidate_mac) do
    if constant_time_equal?(mac(secret, signed), candidate_mac) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp check_replay(consumed, nonce) do
    if MapSet.member?(consumed, nonce), do: {:error, :replayed}, else: :ok
  end

  defp check_expiry(now, expires_at) do
    if now < expires_at, do: :ok, else: {:error, :expired}
  end

  defp deserialize(payload_bytes) do
    :erlang.binary_to_term(payload_bytes, [:safe])
  end

  defp mac(secret, data), do: :crypto.mac(:hmac, :sha256, secret, data)

  # Non-short-circuiting comparison: every byte pair is always examined and the
  # per-byte differences are accumulated, so timing does not leak where two MACs
  # first differ. Binaries of differing size are rejected outright.
  defp constant_time_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    diff =
      left
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(right))
      |> Enum.reduce(0, fn {a, b}, acc -> acc + abs(a - b) end)

    diff === 0
  end

  defp constant_time_equal?(_left, _right), do: false
end
```
