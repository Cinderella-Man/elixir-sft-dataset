defmodule TOTPVault do
  @moduledoc """
  A `GenServer` that manages per-account TOTP secrets and validates codes with
  replay protection.

  The server holds, for every registered account, a base32-encoded 160-bit shared
  secret and the highest 30-second time step that has already been *spent*. Once a
  code for a given step is consumed, that code — and any code for an earlier step —
  can never be accepted again.

  Because a `GenServer` processes messages one at a time, replay protection holds
  under concurrency: if several callers submit the same valid code simultaneously,
  exactly one `consume/4` call returns `:ok` and every other one returns
  `{:error, :replayed}`.

  Codes follow RFC 6238 (TOTP) on top of RFC 4226 (HOTP):

    * the counter is `div(unix_time, 30)`, encoded as a big-endian 8-byte integer;
    * the MAC is HMAC-SHA1 over that counter with the raw (base32-decoded) secret;
    * RFC 4226 dynamic truncation yields a 31-bit integer, taken modulo 1_000_000
      and left-padded with zeroes to exactly six characters.

  Base32 (RFC 4648, uppercase alphabet, unpadded) is implemented in this module;
  only the OTP standard library is used.

  ## Example

      {:ok, vault} = TOTPVault.start_link(name: MyVault)
      {:ok, _secret} = TOTPVault.register(MyVault, "alice")
      {:ok, code} = TOTPVault.current_code(MyVault, "alice")
      :ok = TOTPVault.consume(MyVault, "alice", code)
      {:error, :replayed} = TOTPVault.consume(MyVault, "alice", code)

  """

  use GenServer

  @period 30
  @digits 6
  @modulo 1_000_000
  @secret_bytes 20
  @alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @type account_id :: term()
  @type secret :: String.t()
  @type code :: String.t()

  @typedoc "Internal per-account entry: the base32 secret and the highest consumed step."
  @type entry :: %{secret: secret(), last_step: non_neg_integer() | nil}

  @typedoc "Server state: a map from account id to its entry."
  @type state :: %{optional(account_id()) => entry()}

  ## Public API

  @doc """
  Starts the vault server.

  Accepts the standard `GenServer` options, notably `:name` for registering the
  process. Returns `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, _rest} = Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])
    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Generates a fresh 160-bit secret for `account_id`, stores it and returns
  `{:ok, secret}` where `secret` is the unpadded base32 encoding.

  If `account_id` is already registered, returns `{:error, :already_registered}`
  and leaves the stored secret untouched.
  """
  @spec register(GenServer.server(), account_id()) ::
          {:ok, secret()} | {:error, :already_registered}
  def register(server, account_id) do
    GenServer.call(server, {:register, account_id})
  end

  @doc """
  Returns `{:ok, secret}` for a registered account, or `{:error, :not_found}`.
  """
  @spec secret(GenServer.server(), account_id()) :: {:ok, secret()} | {:error, :not_found}
  def secret(server, account_id) do
    GenServer.call(server, {:secret, account_id})
  end

  @doc """
  Returns `{:ok, code}` — the six-digit code for `account_id` at the given time —
  or `{:error, :not_found}` when the account is unknown.

  This call is read-only: it never consumes a step and never mutates state.

  ## Options

    * `:time` — UNIX time in seconds (defaults to the current system time).

  """
  @spec current_code(GenServer.server(), account_id(), keyword()) ::
          {:ok, code()} | {:error, :not_found}
  def current_code(server, account_id, opts \\ []) do
    time = Keyword.get_lazy(opts, :time, &unix_now/0)
    GenServer.call(server, {:current_code, account_id, time})
  end

  @doc """
  Validates `code` for `account_id` and, on success, spends it.

  `code` may be given as a string or an integer. Let `base = div(time, 30)`; the
  steps `base - window .. base + window` (restricted to non-negative steps) are
  checked in order.

  Returns:

    * `{:error, :not_found}` if the account is not registered;
    * `{:error, :invalid}` if `code` matches no step in the window;
    * `{:error, :replayed}` if the matched step is less than or equal to the highest
      step already consumed for the account (state is left unchanged);
    * `:ok` otherwise, recording the matched step as the account's new highest
      consumed step.

  ## Options

    * `:time` — UNIX time in seconds (defaults to the current system time);
    * `:window` — number of 30-second steps accepted in each direction (default `1`).

  """
  @spec consume(GenServer.server(), account_id(), code() | integer(), keyword()) ::
          :ok | {:error, :not_found | :invalid | :replayed}
  def consume(server, account_id, code, opts \\ []) do
    time = Keyword.get_lazy(opts, :time, &unix_now/0)
    window = Keyword.get(opts, :window, 1)
    GenServer.call(server, {:consume, account_id, code, time, window})
  end

  ## GenServer callbacks

  @impl GenServer
  def init(:ok) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:register, account_id}, _from, state) do
    case Map.fetch(state, account_id) do
      {:ok, _entry} ->
        {:reply, {:error, :already_registered}, state}

      :error ->
        secret = generate_secret()
        entry = %{secret: secret, last_step: nil}
        {:reply, {:ok, secret}, Map.put(state, account_id, entry)}
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
        {:reply, {:ok, code_at(secret, step_for(time))}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:consume, account_id, code, time, window}, _from, state) do
    case Map.fetch(state, account_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, entry} ->
        do_consume(account_id, entry, code, time, window, state)
    end
  end

  ## Internal — consumption

  @spec do_consume(account_id(), entry(), code() | integer(), integer(), integer(), state()) ::
          {:reply, :ok | {:error, :invalid | :replayed}, state()}
  defp do_consume(account_id, entry, code, time, window, state) do
    normalized = normalize_code(code)

    case match_step(entry.secret, normalized, time, window) do
      nil ->
        {:reply, {:error, :invalid}, state}

      matched ->
        last = entry.last_step

        if is_integer(last) and matched <= last do
          {:reply, {:error, :replayed}, state}
        else
          new_state = Map.put(state, account_id, %{entry | last_step: matched})
          {:reply, :ok, new_state}
        end
    end
  end

  @spec match_step(secret(), code(), integer(), integer()) :: non_neg_integer() | nil
  defp match_step(secret, code, time, window) do
    base = step_for(time)
    window = max(window, 0)
    low = max(base - window, 0)
    high = base + window

    if high < low do
      nil
    else
      Enum.find(low..high//1, fn step -> secure_equal?(code_at(secret, step), code) end)
    end
  end

  @spec normalize_code(code() | integer()) :: code()
  defp normalize_code(code) when is_integer(code) do
    code |> Integer.to_string() |> String.pad_leading(@digits, "0")
  end

  defp normalize_code(code) when is_binary(code), do: code

  @spec secure_equal?(binary(), binary()) :: boolean()
  defp secure_equal?(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash_equals(left, right)
  end

  defp secure_equal?(_left, _right), do: false

  ## Internal — TOTP

  @spec step_for(integer()) :: integer()
  defp step_for(time), do: div(time, @period)

  @spec unix_now() :: integer()
  defp unix_now, do: System.os_time(:second)

  @spec generate_secret() :: secret()
  defp generate_secret do
    @secret_bytes |> :crypto.strong_rand_bytes() |> base32_encode()
  end

  @spec code_at(secret(), integer()) :: code()
  defp code_at(secret, step) do
    key = base32_decode!(secret)
    mac = :crypto.mac(:hmac, :sha, key, <<step::unsigned-big-integer-size(64)>>)
    truncate(mac)
  end

  @spec truncate(binary()) :: code()
  defp truncate(mac) do
    offset = :binary.last(mac) &&& 0x0F
    <<_skip::binary-size(offset), value::unsigned-big-integer-size(32), _rest::binary>> = mac

    (value &&& 0x7FFFFFFF)
    |> rem(@modulo)
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  ## Internal — base32 (RFC 4648, uppercase, unpadded)

  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(binary) when is_binary(binary) do
    binary
    |> encode_chunks([])
    |> Enum.reverse()
    |> List.to_string()
  end

  @spec encode_chunks(bitstring(), [char()]) :: [char()]
  defp encode_chunks(<<>>, acc), do: acc

  defp encode_chunks(<<index::size(5), rest::bitstring>>, acc) do
    encode_chunks(rest, [Enum.at(@alphabet, index) | acc])
  end

  defp encode_chunks(rest, acc) when is_bitstring(rest) do
    pad = 5 - bit_size(rest)
    <<index::size(5)>> = <<rest::bitstring, 0::size(pad)>>
    [Enum.at(@alphabet, index) | acc]
  end

  @spec base32_decode!(String.t()) :: binary()
  defp base32_decode!(string) when is_binary(string) do
    bits =
      string
      |> String.to_charlist()
      |> Enum.reduce(<<>>, fn char, acc ->
        <<acc::bitstring, char_to_index!(char)::size(5)>>
      end)

    take_bytes(bits)
  end

  @spec take_bytes(bitstring()) :: binary()
  defp take_bytes(bits) do
    usable = div(bit_size(bits), 8) * 8
    <<bytes::binary-size(^usable)-unit(1), _leftover::bitstring>> = bits
    bytes
  end

  @spec char_to_index!(char()) :: non_neg_integer()
  defp char_to_index!(char) do
    case Enum.find_index(@alphabet, &(&1 == char)) do
      nil -> raise ArgumentError, "invalid base32 character: #{inspect(<<char::utf8>>)}"
      index -> index
    end
  end

  # `&&&` without importing all of Bitwise's operators into scope.
  import Bitwise, only: [&&&: 2]
end