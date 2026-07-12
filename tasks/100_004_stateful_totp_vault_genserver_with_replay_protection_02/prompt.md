# Fill in the middle: `hotp/2`

Implement the private `hotp/2` function. It receives a base32 secret string and a
non-negative integer `step` (the 30-second time step, i.e. `div(time, 30)`), and it
must return the RFC 6238 code for that step as a 6-character, zero-padded string.

It should:

1. Decode the base32 `secret` into the raw HMAC key using `base32_decode/1`.
2. Compute an HMAC-SHA1 over the big-endian 8-byte step (`<<step::64>>`) with that
   key, using `:crypto.mac(:hmac, :sha, key, ...)`.
3. Apply RFC 4226 dynamic truncation: take the low 4 bits of the hash's last byte as
   the `offset` (`rem(last_byte, @offset_modulo)`), then read the 4 bytes starting at
   `offset` and combine them big-endian into a 32-bit integer.
4. Mask off the top bit by taking the value modulo `@truncate_modulo` (2^31), then take
   the result modulo `@modulo` (1_000_000).
5. Convert to a string and left-pad with zeros to `@digits` (6) characters.

Use the module attributes (`@offset_modulo`, `@truncate_modulo`, `@modulo`, `@digits`)
already defined in the module, and the `base32_decode/1` helper. Do not use bitwise
operators — the truncation masks are expressed as moduli.

```elixir
defmodule TOTPVault do
  @moduledoc """
  A `GenServer` that manages per-account TOTP (RFC 6238) secrets and validates
  codes with replay protection.

  A single server process owns every account's base32 secret together with the
  highest 30-second time step that has already been "spent". Once a code for a
  given step is consumed, that same code — and any code for an earlier step —
  can never be accepted again. Because the server handles one message at a time,
  concurrent submissions of the same valid code resolve deterministically:
  exactly one `consume/4` returns `:ok`, all others return `{:error, :replayed}`.

  The implementation relies only on the OTP standard library. Base32
  (RFC 4648, unpadded) is implemented in this module and HMAC-SHA1 is computed
  with `:crypto.mac/4`.
  """

  use GenServer

  @alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
  @step_seconds 30
  @digits 6
  @modulo 1_000_000
  @secret_bytes 20

  # RFC 4226 dynamic-truncation masks expressed as moduli so no bitwise ops are
  # needed: `rem(byte, 16)` == `byte &&& 0x0F`, and `rem(v, 2^31)` == the low 31
  # bits of a 32-bit value (`v &&& 0x7FFFFFFF`).
  @offset_modulo 16
  @truncate_modulo 2_147_483_648

  @type server :: GenServer.server()
  @type account_id :: term()
  @type secret :: String.t()

  @typep account :: %{secret: secret(), last: non_neg_integer() | nil}
  @typep state :: %{optional(account_id()) => account()}

  ## Public API

  @doc """
  Starts the vault server.

  Accepts the standard `:name` option for registering the process. Returns
  `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, %{}, gen_opts)
  end

  @doc """
  Generates and stores a fresh secret for `account_id`.

  Returns `{:ok, secret}` with the base32 secret string. If the account is
  already registered, returns `{:error, :already_registered}` and leaves the
  stored secret unchanged.
  """
  @spec register(server(), account_id()) ::
          {:ok, secret()} | {:error, :already_registered}
  def register(server, account_id) do
    GenServer.call(server, {:register, account_id})
  end

  @doc """
  Returns `{:ok, secret}` for a registered account, or `{:error, :not_found}`.
  """
  @spec secret(server(), account_id()) :: {:ok, secret()} | {:error, :not_found}
  def secret(server, account_id) do
    GenServer.call(server, {:secret, account_id})
  end

  @doc """
  Returns `{:ok, code}` — the 6-digit code for the account at the given time —
  or `{:error, :not_found}`.

  Options:

    * `:time` — UNIX seconds (default: current system time)

  This function is read-only and never consumes anything.
  """
  @spec current_code(server(), account_id(), keyword()) ::
          {:ok, String.t()} | {:error, :not_found}
  def current_code(server, account_id, opts \\ []) do
    time = Keyword.get(opts, :time, System.system_time(:second))
    GenServer.call(server, {:current_code, account_id, time})
  end

  @doc """
  Validates `code` and, on success, spends it for `account_id`.

  Options:

    * `:time` — UNIX seconds (default: current system time)
    * `:window` — 30-second steps accepted in each direction (default: `1`)

  With `base = div(time, 30)`, the steps `base - window .. base + window`
  (only those `>= 0`) are considered. Returns:

    * `{:error, :not_found}` if the account is not registered
    * `{:error, :invalid}` if `code` matches no step in the window
    * `{:error, :replayed}` if the matched step is `<= last`
    * `:ok` otherwise, recording the matched step as the new highest step

  `code` may be given as a string or an integer.
  """
  @spec consume(server(), account_id(), String.t() | integer(), keyword()) ::
          :ok | {:error, :not_found | :invalid | :replayed}
  def consume(server, account_id, code, opts \\ []) do
    time = Keyword.get(opts, :time, System.system_time(:second))
    window = Keyword.get(opts, :window, 1)
    GenServer.call(server, {:consume, account_id, normalize_code(code), time, window})
  end

  ## GenServer callbacks

  @impl true
  @spec init(state()) :: {:ok, state()}
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:register, account_id}, _from, state) do
    case Map.fetch(state, account_id) do
      {:ok, _account} ->
        {:reply, {:error, :already_registered}, state}

      :error ->
        secret = generate_secret()
        account = %{secret: secret, last: nil}
        {:reply, {:ok, secret}, Map.put(state, account_id, account)}
    end
  end

  def handle_call({:secret, account_id}, _from, state) do
    case Map.fetch(state, account_id) do
      {:ok, %{secret: secret}} -> {:reply, {:ok, secret}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:current_code, account_id, time}, _from, state) do
    case Map.fetch(state, account_id) do
      {:ok, %{secret: secret}} ->
        code = hotp(secret, div(time, @step_seconds))
        {:reply, {:ok, code}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:consume, account_id, code, time, window}, _from, state) do
    case Map.fetch(state, account_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{secret: secret, last: last} = account} ->
        base = div(time, @step_seconds)

        case match_step(secret, code, base, window) do
          nil ->
            {:reply, {:error, :invalid}, state}

          matched when is_integer(last) and matched <= last ->
            {:reply, {:error, :replayed}, state}

          matched ->
            updated = Map.put(state, account_id, %{account | last: matched})
            {:reply, :ok, updated}
        end
    end
  end

  ## Internal helpers

  @spec generate_secret() :: secret()
  defp generate_secret do
    @secret_bytes
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  @spec normalize_code(String.t() | integer()) :: String.t()
  defp normalize_code(code) when is_integer(code) do
    code
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  defp normalize_code(code) when is_binary(code), do: code

  @spec match_step(secret(), String.t(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer() | nil
  defp match_step(secret, code, base, window) do
    lo = max(base - window, 0)
    hi = base + window
    Enum.find(lo..hi, fn step -> hotp(secret, step) == code end)
  end

  defp hotp(secret, step) do
    # TODO
  end

  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(binary) do
    for <<index::5 <- binary>>, into: "", do: binary_part(@alphabet, index, 1)
  end

  @spec base32_decode(String.t()) :: binary()
  defp base32_decode(string) do
    bits = for <<char <- string>>, into: <<>>, do: <<decode_char(char)::5>>
    for <<byte::8 <- bits>>, into: <<>>, do: <<byte>>
  end

  @spec decode_char(byte()) :: non_neg_integer()
  defp decode_char(char) when char in ?A..?Z, do: char - ?A
  defp decode_char(char) when char in ?2..?7, do: char - ?2 + 26
end
```