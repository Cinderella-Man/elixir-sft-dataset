# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule TOTPVault do
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

  ## Public API

  def start_link(opts \\ []) do
    {gen_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, %{}, gen_opts)
  end

  def register(server, account_id) do
    GenServer.call(server, {:register, account_id})
  end

  def secret(server, account_id) do
    GenServer.call(server, {:secret, account_id})
  end

  def current_code(server, account_id, opts \\ []) do
    time = Keyword.get(opts, :time, System.system_time(:second))
    GenServer.call(server, {:current_code, account_id, time})
  end

  def consume(server, account_id, code, opts \\ []) do
    time = Keyword.get(opts, :time, System.system_time(:second))
    window = Keyword.get(opts, :window, 1)
    GenServer.call(server, {:consume, account_id, normalize_code(code), time, window})
  end

  ## GenServer callbacks

  @impl true
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

  defp generate_secret do
    @secret_bytes
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  defp normalize_code(code) when is_integer(code) do
    code
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  defp normalize_code(code) when is_binary(code), do: code

  defp match_step(secret, code, base, window) do
    lo = max(base - window, 0)
    hi = base + window
    Enum.find(lo..hi, fn step -> hotp(secret, step) == code end)
  end

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

  defp base32_encode(binary) do
    for <<index::5 <- binary>>, into: "", do: binary_part(@alphabet, index, 1)
  end

  defp base32_decode(string) do
    bits = for <<char <- string>>, into: <<>>, do: <<decode_char(char)::5>>
    for <<byte::8 <- bits>>, into: <<>>, do: <<byte>>
  end

  defp decode_char(char) when char in ?A..?Z, do: char - ?A
  defp decode_char(char) when char in ?2..?7, do: char - ?2 + 26
end
```
