# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `start_link` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

# TOTPVault — stateful TOTP vault with replay protection

**Summary:** Implement an Elixir module `TOTPVault`, a `GenServer` that manages per-account TOTP secrets and validates codes with replay protection. OTP standard library only — no external dependencies. Deliver the complete module in a single file.

**State model**
- A single server process holds every account's secret plus the highest 30-second step already "spent" for that account.
- Once a code for a given step is consumed, that same code — and any code for an earlier step — must never be accepted again, including under concurrent submissions.

**Code derivation (RFC 6238)**
- Secret: base32, 160 bits / 20 random bytes, no padding, generated with `:crypto.strong_rand_bytes/1`.
- HMAC-SHA1 over the big-endian 8-byte step `div(time, 30)`.
- RFC 4226 dynamic truncation, modulo 1_000_000, left-padded to a 6-character string.

**Public API**
- `TOTPVault.start_link(opts \\ [])` — starts the server, returns `{:ok, pid}`. Accepts the standard `:name` option for registering the process.
- `TOTPVault.register(server, account_id)` — generates a fresh secret for `account_id`, stores it, returns `{:ok, secret}` (the base32 secret string). If `account_id` is already registered, returns `{:error, :already_registered}` and leaves the stored secret unchanged.
- `TOTPVault.secret(server, account_id)` — returns `{:ok, secret}` for a registered account, else `{:error, :not_found}`.
- `TOTPVault.current_code(server, account_id, opts \\ [])` — returns `{:ok, code}`, the 6-digit code for the account at the given time, or `{:error, :not_found}`. Accepts a `:time` option (UNIX seconds, default: current time). Read-only: never consumes anything.
- `TOTPVault.consume(server, account_id, code, opts \\ [])` — validates and, on success, spends a code. Options: `:time` (UNIX seconds, default: current time); `:window` (number of 30-second steps accepted in each direction, default: `1`).

**consume/4 semantics**
- Let `base = div(time, 30)`. Consider the steps `base - window .. base + window`, restricted to those `>= 0`.
- `account_id` not registered → `{:error, :not_found}`.
- `code` (accepted as a string or integer) matches no step in the window → `{:error, :invalid}`.
- `code` matches a step in the window: let `matched` be that step. If the account already has a consumed step `last` and `matched <= last` → `{:error, :replayed}`, stored state unchanged.
- Otherwise (match with `matched` greater than any previously consumed step, or no prior consumption) → record `matched` as the account's new highest consumed step and return `:ok`.

**Concurrency**
- Because the server processes messages one at a time, when several callers submit the *same* valid code concurrently, exactly one `consume/4` call returns `:ok` and every other returns `{:error, :replayed}`.

**Implementation constraints**
- Base32 encoding/decoding must follow RFC 4648: uppercase alphabet A–Z, 2–7, unpadded. Implement it yourself.
- HMAC-SHA1 via Erlang's `:crypto.mac/4`.
- Dynamic truncation: last byte masked with `0x0F` is the offset; read 4 bytes from that offset; mask the top bit with `0x7F`; take modulo 1_000_000.
- Generated codes are always exactly 6 characters, zero-padded.

## The module with `start_link` missing

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

  def start_link(opts \\ []) do
    # TODO
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

  @spec hotp(secret(), non_neg_integer()) :: String.t()
  defp hotp(secret, step) do
    key = base32_decode(secret)
    hash = :crypto.mac(:hmac, :sha, key, <<step::64>>)
    offset = rem(:binary.at(hash, byte_size(hash) - 1), @offset_modulo)

    truncated =
      :binary.at(hash, offset) * 16_777_216 +
        :binary.at(hash, offset + 1) * 65_536 +
        :binary.at(hash, offset + 2) * 256 +
        :binary.at(hash, offset + 3)

    truncated
    |> rem(@truncate_modulo)
    |> rem(@modulo)
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
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

Reply with `start_link` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
