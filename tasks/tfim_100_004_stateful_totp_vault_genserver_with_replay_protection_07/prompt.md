# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule TOTPVaultTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = TOTPVault.start_link()
    %{vault: pid}
  end

  # -------------------------------------------------------------------
  # register / secret
  # -------------------------------------------------------------------

  test "register returns a base32 secret", %{vault: v} do
    assert {:ok, secret} = TOTPVault.register(v, "alice")
    assert String.match?(secret, ~r/\A[A-Z2-7]+\z/)
  end

  test "register is idempotent-guarded: second call errors and keeps the secret", %{vault: v} do
    assert {:ok, secret} = TOTPVault.register(v, "alice")
    assert {:error, :already_registered} = TOTPVault.register(v, "alice")
    assert {:ok, ^secret} = TOTPVault.secret(v, "alice")
  end

  test "secret returns :not_found for an unknown account", %{vault: v} do
    assert {:error, :not_found} = TOTPVault.secret(v, "nobody")
  end

  test "different accounts get different secrets", %{vault: v} do
    {:ok, a} = TOTPVault.register(v, "alice")
    {:ok, b} = TOTPVault.register(v, "bob")
    refute a == b
  end

  # -------------------------------------------------------------------
  # current_code
  # -------------------------------------------------------------------

  test "current_code is read-only and stable within a step", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, c1} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, c2} = TOTPVault.current_code(v, "alice", time: 90_029)
    assert c1 == c2
    assert byte_size(c1) == 6
    # Still consumable afterward — reading did not spend it.
    assert TOTPVault.consume(v, "alice", c1, time: 90_000) == :ok
  end

  test "current_code returns :not_found for unknown account", %{vault: v} do
    # TODO
  end

  # -------------------------------------------------------------------
  # consume — basic acceptance / rejection
  # -------------------------------------------------------------------

  test "consume accepts the current code once", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)
    assert TOTPVault.consume(v, "alice", code, time: 90_000) == :ok
  end

  test "consume rejects a wrong code as :invalid", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)

    wrong =
      code
      |> String.to_integer()
      |> then(&rem(&1 + 1, 1_000_000))
      |> Integer.to_string()
      |> String.pad_leading(6, "0")

    assert TOTPVault.consume(v, "alice", wrong, time: 90_000) == {:error, :invalid}
  end

  test "consume accepts an integer code", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)
    assert TOTPVault.consume(v, "alice", String.to_integer(code), time: 90_000) == :ok
  end

  test "consume returns :not_found for an unknown account", %{vault: v} do
    assert TOTPVault.consume(v, "ghost", "123456", time: 90_000) == {:error, :not_found}
  end

  # -------------------------------------------------------------------
  # consume — replay protection
  # -------------------------------------------------------------------

  test "re-consuming the same code returns :replayed", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)

    assert TOTPVault.consume(v, "alice", code, time: 90_000) == :ok
    assert TOTPVault.consume(v, "alice", code, time: 90_000) == {:error, :replayed}
  end

  test "after consuming the current step, an earlier step's code is :replayed", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, current} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, prev} = TOTPVault.current_code(v, "alice", time: 90_000 - 30)

    assert TOTPVault.consume(v, "alice", current, time: 90_000) == :ok
    # prev belongs to step base-1 <= last consumed step base.
    assert TOTPVault.consume(v, "alice", prev, time: 90_000) == {:error, :replayed}
  end

  test "a drifted (previous-step) code is accepted when not yet consumed", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, prev} = TOTPVault.current_code(v, "alice", time: 90_000 - 30)
    # window default 1 covers base-1
    assert TOTPVault.consume(v, "alice", prev, time: 90_000) == :ok
  end

  test "a later step's code still works after an earlier consumption", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, c1} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, c2} = TOTPVault.current_code(v, "alice", time: 90_030)

    assert TOTPVault.consume(v, "alice", c1, time: 90_000) == :ok
    assert TOTPVault.consume(v, "alice", c2, time: 90_030) == :ok
  end

  # -------------------------------------------------------------------
  # concurrency — exactly one winner
  # -------------------------------------------------------------------

  test "concurrent consumption of the same code yields exactly one :ok", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    t = 90_000
    {:ok, code} = TOTPVault.current_code(v, "alice", time: t)

    results =
      1..25
      |> Task.async_stream(fn _ -> TOTPVault.consume(v, "alice", code, time: t) end,
        max_concurrency: 25
      )
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :replayed})) == 24
  end

  # -------------------------------------------------------------------
  # RFC 6238 conformance — codes recomputed independently from the secret
  # -------------------------------------------------------------------

  test "current_code matches an independent RFC 6238 computation over 300 steps", %{vault: v} do
    {:ok, secret} = TOTPVault.register(v, "alice")

    for step <- 0..299 do
      time = step * 30
      assert {:ok, code} = TOTPVault.current_code(v, "alice", time: time)
      assert code == rfc6238_code(secret, time)
    end
  end

  test "a fresh secret encodes 160 bits: exactly 32 unpadded base32 characters", %{vault: v} do
    {:ok, secret} = TOTPVault.register(v, "alice")
    assert String.match?(secret, ~r/\A[A-Z2-7]{32}\z/)
  end

  test "consume without a :window option accepts only steps base-1..base+1", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")

    # The base±2 codes must be rejected purely for sitting OUTSIDE the default
    # window, so pick a base where neither collides with any in-window code
    # (distinct steps can produce the same 6-digit code by chance).
    t =
      Enum.find(1..5, fn candidate ->
        [far_past, prev, current, next, far_future] =
          codes_around(v, "alice", candidate * 90_000)

        far_past not in [prev, current, next] and far_future not in [prev, current, next]
      end) * 90_000

    [far_past, _prev, _current, _next, far_future] = codes_around(v, "alice", t)

    assert TOTPVault.consume(v, "alice", far_future, time: t) == {:error, :invalid}
    assert TOTPVault.consume(v, "alice", far_past, time: t) == {:error, :invalid}
  end

  # -------------------------------------------------------------------
  # consume — the :window option itself
  # -------------------------------------------------------------------

  test "window: 0 narrows acceptance to the base step alone", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")

    # The neighbouring codes must be rejected purely for sitting outside a
    # zero-width window, so pick a base where neither equals the base code.
    t =
      Enum.find(1..5, fn candidate ->
        [_, prev, current, next, _] = codes_around(v, "alice", candidate * 90_000)
        current not in [prev, next]
      end) * 90_000

    [_, prev, current, next, _] = codes_around(v, "alice", t)

    assert TOTPVault.consume(v, "alice", next, time: t, window: 0) == {:error, :invalid}
    assert TOTPVault.consume(v, "alice", prev, time: t, window: 0) == {:error, :invalid}
    assert TOTPVault.consume(v, "alice", current, time: t, window: 0) == :ok
  end

  test "window: 2 widens acceptance to steps base-2 and base+2", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "ahead")
    {:ok, _} = TOTPVault.register(v, "behind")
    t = 90_000

    {:ok, ahead} = TOTPVault.current_code(v, "ahead", time: t + 60)
    {:ok, behind} = TOTPVault.current_code(v, "behind", time: t - 60)

    # Separate accounts: consuming one step must not replay-block the other.
    assert TOTPVault.consume(v, "ahead", ahead, time: t, window: 2) == :ok
    assert TOTPVault.consume(v, "behind", behind, time: t, window: 2) == :ok
  end

  test "window: 3 near the epoch still refuses a code from a step below zero", %{vault: v} do
    # At time 0 the base step is 0, so a window of 3 spans steps 0..3 only:
    # negative steps are never considered, however far the window reaches back.
    n =
      Enum.find(1..5, fn n ->
        {:ok, secret} = TOTPVault.register(v, "clamp#{n}")
        in_window = for step <- 0..3, do: rfc6238_code(secret, step * 30)
        rfc6238_code(secret, -30) not in in_window
      end)

    account = "clamp#{n}"
    {:ok, secret} = TOTPVault.secret(v, account)
    below_epoch = rfc6238_code(secret, -30)

    result = TOTPVault.consume(v, account, below_epoch, time: 0, window: 3)
    assert result == {:error, :invalid}
  end

  # -------------------------------------------------------------------
  # start_link — :name registration
  # -------------------------------------------------------------------

  test "start_link/1 registers the process under :name and serves calls through it" do
    name = :"totp_vault_#{System.pid()}_#{System.unique_integer([:positive])}"

    assert {:ok, pid} = TOTPVault.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.whereis(name) == pid

    # The registered name is a usable server reference for the whole API.
    assert {:ok, secret} = TOTPVault.register(name, "alice")
    assert {:ok, ^secret} = TOTPVault.secret(name, "alice")
    assert {:ok, code} = TOTPVault.current_code(name, "alice", time: 90_000)
    assert TOTPVault.consume(name, "alice", code, time: 90_000) == :ok
    assert TOTPVault.consume(name, "alice", code, time: 90_000) == {:error, :replayed}
  end

  # Codes for steps base-2..base+2 at `time`, via the read-only public API.
  defp codes_around(vault, account, time) do
    for offset <- -2..2 do
      {:ok, code} = TOTPVault.current_code(vault, account, time: time + offset * 30)
      code
    end
  end

  # Independent RFC 6238 reference: RFC 4648 base32 decode (A-Z, 2-7,
  # unpadded), HMAC-SHA1 over the big-endian 8-byte step, RFC 4226 dynamic
  # truncation (offset = last byte masked with 0x0F, 4 bytes read from that
  # offset, top bit masked), modulo 1_000_000, zero-padded to 6 characters.
  defp rfc6238_code(secret, time) do
    bits =
      for <<char <- secret>>, into: <<>> do
        value = if char in ?A..?Z, do: char - ?A, else: char - ?2 + 26
        <<value::5>>
      end

    whole_bytes = div(bit_size(bits), 8)
    <<key::binary-size(^whole_bytes), _::bitstring>> = bits

    hash = :crypto.mac(:hmac, :sha, key, <<div(time, 30)::64>>)
    offset = hash |> :binary.last() |> Bitwise.band(0x0F)
    <<_::binary-size(^offset), word::32, _::binary>> = hash

    word
    |> Bitwise.band(0x7FFFFFFF)
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  test "a rejected replay leaves the highest consumed step intact", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, current} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, prev} = TOTPVault.current_code(v, "alice", time: 90_000 - 30)

    assert TOTPVault.consume(v, "alice", current, time: 90_000) == :ok
    assert TOTPVault.consume(v, "alice", prev, time: 90_000) == {:error, :replayed}

    # The rejected attempt must not have lowered or cleared the stored step:
    # the base-step code stays spent, and a later step is still spendable.
    assert TOTPVault.consume(v, "alice", current, time: 90_000) == {:error, :replayed}
    {:ok, next} = TOTPVault.current_code(v, "alice", time: 90_030)
    assert TOTPVault.consume(v, "alice", next, time: 90_030) == :ok
  end

  test "a spent step stays rejected later even under a much wider window", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)

    assert TOTPVault.consume(v, "alice", code, time: 90_000) == :ok

    # At time 90_120 the base step is 3004, so window 5 spans steps 2999..3009
    # and therefore re-offers the already-spent step 3000.
    assert TOTPVault.consume(v, "alice", code, time: 90_120, window: 5) == {:error, :replayed}
  end

  test "an integer code whose string form has a leading zero is accepted", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")

    # A code below 100_000 loses its leading zero when handed over as an
    # integer; the integer form must still match the padded code.
    found =
      Enum.find_value(0..999, fn step ->
        {:ok, code} = TOTPVault.current_code(v, "alice", time: step * 30)
        if String.starts_with?(code, "0"), do: {step, code}
      end)

    assert {step, code} = found
    assert TOTPVault.consume(v, "alice", String.to_integer(code), time: step * 30) == :ok
  end

  test "a code numerically below 100000 is still six characters wide", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")

    short =
      Enum.find_value(0..999, fn step ->
        {:ok, code} = TOTPVault.current_code(v, "alice", time: step * 30)
        if String.to_integer(code) < 100_000, do: code
      end)

    assert is_binary(short)
    assert byte_size(short) == 6
    assert String.match?(short, ~r/\A0\d{5}\z/)
  end

  # -------------------------------------------------------------------
  # default :time — UNIX seconds when the option is omitted
  # -------------------------------------------------------------------

  test "current_code without :time uses the current UNIX second", %{vault: v} do
    {:ok, secret} = TOTPVault.register(v, "alice")

    # Bracket the call: the only codes it may return are those of the UNIX
    # second-derived steps the call could have straddled. A millisecond,
    # monotonic or otherwise-scaled clock lands on an unrelated step.
    started_at = System.system_time(:second)
    assert {:ok, code} = TOTPVault.current_code(v, "alice")
    finished_at = System.system_time(:second)

    acceptable =
      for step <- div(started_at, 30)..div(finished_at, 30),
          do: rfc6238_code(secret, step * 30)

    assert code in acceptable
  end

  test "consume without :time validates against the current UNIX second", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")

    now = System.system_time(:second)
    {:ok, code} = TOTPVault.current_code(v, "alice", time: now)

    # The default window of 1 step absorbs a second boundary crossed between
    # the two calls, so a seconds-based default must accept this code and
    # then treat the very same code as spent.
    assert TOTPVault.consume(v, "alice", code) == :ok
    assert TOTPVault.consume(v, "alice", code) == {:error, :replayed}
  end
end
```
