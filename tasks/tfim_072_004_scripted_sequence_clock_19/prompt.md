# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule Clock do
  @moduledoc """
  Behaviour and dispatcher for clock implementations.

  In this variation the fake clock is *scripted*: it hands out a predetermined
  sequence of timestamps, one per read. Application code accepts a `:clock`
  option and calls `Clock.now/1` uniformly, unaware of what backs it.

  ## Usage

      {:ok, c} = Clock.Fake.start_link(script: [
        ~U[2024-06-01 12:00:00Z],
        ~U[2024-06-01 12:00:42Z]
      ])
      Clock.now(c)   #=> ~U[2024-06-01 12:00:00Z]
      Clock.now(c)   #=> ~U[2024-06-01 12:00:42Z]
  """

  @doc "Returns the current datetime."
  @callback now() :: DateTime.t()

  @doc "Dispatches `now/0` to the correct implementation."
  @spec now(module() | GenServer.server()) :: DateTime.t()
  def now(clock) when is_atom(clock) do
    if function_exported?(clock, :now, 0) do
      clock.now()
    else
      Clock.Fake.now(clock)
    end
  end

  def now(clock), do: Clock.Fake.now(clock)
end

# ---------------------------------------------------------------------------

defmodule Clock.Real do
  @moduledoc "Production clock — delegates straight to the OS."

  @behaviour Clock

  @impl Clock
  @spec now() :: DateTime.t()
  def now, do: DateTime.utc_now()
end

# ---------------------------------------------------------------------------

defmodule Clock.Fake do
  @moduledoc """
  A scripted, process-based clock for tests.

  Each call to `now/1` returns the next `DateTime` in the script and advances an
  internal cursor. Once the script is consumed, the `:on_exhaust` policy decides
  what happens next: `:repeat_last`, `:cycle`, or `:raise`.

  ## Starting

      {:ok, c} = Clock.Fake.start_link(
        script: [~U[2024-01-01 00:00:00Z], ~U[2024-01-01 00:00:05Z]],
        on_exhaust: :cycle
      )
  """

  use GenServer

  @default_initial ~U[2024-01-01 00:00:00Z]
  @policies [:repeat_last, :cycle, :raise]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {script, opts} = Keyword.pop(opts, :script, [@default_initial])
    {policy, opts} = Keyword.pop(opts, :on_exhaust, :repeat_last)
    {name_opt, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    GenServer.start_link(__MODULE__, {script, policy}, gen_opts)
  end

  @doc "Returns the next scripted `DateTime`, advancing the cursor."
  @spec now(GenServer.server()) :: DateTime.t()
  def now(server) do
    case GenServer.call(server, :now) do
      {:ok, dt} -> dt
      {:error, :exhausted} -> raise "Clock.Fake: scripted time sequence exhausted"
    end
  end

  @doc "Returns how many scripted values have not yet been consumed."
  @spec remaining(GenServer.server()) :: non_neg_integer()
  def remaining(server), do: GenServer.call(server, :remaining)

  @doc "Rewinds the cursor to the beginning of the script."
  @spec reset(GenServer.server()) :: :ok
  def reset(server), do: GenServer.call(server, :reset)

  @doc "Appends more `DateTime`s to the end of the script."
  @spec push(GenServer.server(), [DateTime.t()]) :: :ok
  def push(server, datetimes) when is_list(datetimes),
    do: GenServer.call(server, {:push, datetimes})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init({script, policy}) do
    cond do
      script == [] -> {:stop, :empty_script}
      not Enum.all?(script, &match?(%DateTime{}, &1)) -> {:stop, :invalid_script}
      policy not in @policies -> {:stop, :invalid_policy}
      true -> {:ok, %{script: script, index: 0, policy: policy}}
    end
  end

  @impl GenServer
  def handle_call(:now, _from, %{script: script, index: index, policy: policy} = state) do
    len = length(script)

    cond do
      index < len ->
        {:reply, {:ok, Enum.at(script, index)}, %{state | index: index + 1}}

      policy == :repeat_last ->
        {:reply, {:ok, List.last(script)}, state}

      policy == :cycle ->
        {:reply, {:ok, Enum.at(script, rem(index, len))}, %{state | index: index + 1}}

      policy == :raise ->
        {:reply, {:error, :exhausted}, state}
    end
  end

  def handle_call(:remaining, _from, %{script: script, index: index} = state) do
    {:reply, max(0, length(script) - index), state}
  end

  def handle_call(:reset, _from, state), do: {:reply, :ok, %{state | index: 0}}

  def handle_call({:push, datetimes}, _from, state) do
    {:reply, :ok, %{state | script: state.script ++ datetimes}}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ClockV3Test do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Clock.Real
  # -------------------------------------------------------

  describe "Clock.Real" do
    test "now/0 returns a DateTime close to the actual current UTC time" do
      before = DateTime.utc_now()
      result = Clock.Real.now()
      after_ = DateTime.utc_now()

      assert %DateTime{} = result
      assert DateTime.compare(result, before) in [:gt, :eq]
      assert DateTime.compare(result, after_) in [:lt, :eq]
    end
  end

  # -------------------------------------------------------
  # Scripted sequence
  # -------------------------------------------------------

  describe "Clock.Fake scripted sequence" do
    setup do
      script = [
        ~U[2024-01-01 00:00:00Z],
        ~U[2024-01-01 00:00:05Z],
        ~U[2024-01-01 00:00:20Z]
      ]

      {:ok, pid} = Clock.Fake.start_link(script: script)
      %{clock: pid, script: script}
    end

    test "hands out scripted values in order, one per call", %{clock: clock, script: script} do
      assert Enum.map(script, fn _ -> Clock.Fake.now(clock) end) == script
    end

    test "remaining/1 counts unconsumed values", %{clock: clock} do
      assert Clock.Fake.remaining(clock) == 3
      Clock.Fake.now(clock)
      assert Clock.Fake.remaining(clock) == 2
      Clock.Fake.now(clock)
      Clock.Fake.now(clock)
      assert Clock.Fake.remaining(clock) == 0
    end

    test "reset/1 rewinds the cursor", %{clock: clock, script: script} do
      Enum.each(script, fn _ -> Clock.Fake.now(clock) end)
      assert Clock.Fake.remaining(clock) == 0

      Clock.Fake.reset(clock)
      assert Clock.Fake.remaining(clock) == 3
      assert Clock.Fake.now(clock) == hd(script)
    end

    test "push/2 appends more values", %{clock: clock} do
      extra = ~U[2024-01-01 01:00:00Z]
      Clock.Fake.push(clock, [extra])
      assert Clock.Fake.remaining(clock) == 4

      # Drain the original three, then the pushed one.
      Enum.each(1..3, fn _ -> Clock.Fake.now(clock) end)
      assert Clock.Fake.now(clock) == extra
    end
  end

  # -------------------------------------------------------
  # Exhaustion policies
  # -------------------------------------------------------

  describe ":on_exhaust policies" do
    test ":repeat_last returns the final value forever (default)" do
      last = ~U[2024-05-05 05:05:05Z]
      {:ok, c} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z], last])

      assert Clock.Fake.now(c) == ~U[2024-01-01 00:00:00Z]
      assert Clock.Fake.now(c) == last
      assert Clock.Fake.now(c) == last
      assert Clock.Fake.now(c) == last
      assert Clock.Fake.remaining(c) == 0
    end

    test ":cycle wraps back to the start" do
      a = ~U[2024-01-01 00:00:00Z]
      b = ~U[2024-01-01 00:00:10Z]
      {:ok, c} = Clock.Fake.start_link(script: [a, b], on_exhaust: :cycle)

      assert Clock.Fake.now(c) == a
      assert Clock.Fake.now(c) == b
      assert Clock.Fake.now(c) == a
      assert Clock.Fake.now(c) == b
    end

    test ":raise blows up once the script is exhausted" do
      {:ok, c} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]], on_exhaust: :raise)

      assert Clock.Fake.now(c) == ~U[2024-01-01 00:00:00Z]
      assert_raise RuntimeError, fn -> Clock.Fake.now(c) end
    end
  end

  # -------------------------------------------------------
  # Startup validation
  # -------------------------------------------------------

  describe "startup validation" do
    test "an empty script fails to start" do
      Process.flag(:trap_exit, true)
      assert {:error, :empty_script} = Clock.Fake.start_link(script: [])
    end

    test "a non-DateTime element fails to start" do
      Process.flag(:trap_exit, true)
      assert {:error, :invalid_script} = Clock.Fake.start_link(script: [:not_a_datetime])
    end

    test "an unknown policy fails to start" do
      Process.flag(:trap_exit, true)

      assert {:error, :invalid_policy} =
               Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]], on_exhaust: :bogus)
    end

    test "defaults to a single-value script when none given" do
      {:ok, c} = Clock.Fake.start_link([])
      assert %DateTime{} = Clock.Fake.now(c)
    end

    test "the default script is exactly [~U[2024-01-01 00:00:00Z]]" do
      # TODO
    end

    test "the default script holds under the default :repeat_last policy" do
      # With the one documented default value consumed, further reads repeat it.
      {:ok, c} = Clock.Fake.start_link([])

      assert Clock.Fake.now(c) == ~U[2024-01-01 00:00:00Z]
      assert Clock.Fake.now(c) == ~U[2024-01-01 00:00:00Z]
    end
  end

  # -------------------------------------------------------
  # Clock.now/1 dispatch
  # -------------------------------------------------------

  describe "Clock.now/1 unified dispatch" do
    test "dispatches to Clock.Real when given the module atom" do
      assert %DateTime{} = Clock.now(Clock.Real)
    end

    test "dispatches to Clock.Fake when given a pid, consuming the script" do
      script = [~U[2025-03-20 09:30:00Z], ~U[2025-03-20 09:31:00Z]]
      {:ok, pid} = Clock.Fake.start_link(script: script)
      assert Clock.now(pid) == Enum.at(script, 0)
      assert Clock.now(pid) == Enum.at(script, 1)
    end

    test "dispatches to Clock.Fake when given a registered name" do
      target = ~U[2025-03-20 09:30:00Z]
      {:ok, _} = Clock.Fake.start_link(script: [target], name: :v3_named_clock)
      assert Clock.now(:v3_named_clock) == target
    end
  end

  # -------------------------------------------------------
  # Isolation
  # -------------------------------------------------------

  describe "isolation" do
    test "two scripted clocks advance independently" do
      {:ok, a} =
        Clock.Fake.start_link(script: [~U[2020-01-01 00:00:00Z], ~U[2020-01-01 00:00:01Z]])

      {:ok, b} =
        Clock.Fake.start_link(script: [~U[2099-01-01 00:00:00Z], ~U[2099-01-01 00:00:01Z]])

      assert Clock.Fake.now(a) == ~U[2020-01-01 00:00:00Z]
      # b's cursor is untouched.
      assert Clock.Fake.remaining(b) == 2
      assert Clock.Fake.now(b) == ~U[2099-01-01 00:00:00Z]
    end
  end

  # -------------------------------------------------------
  # Injection pattern
  # -------------------------------------------------------

  describe "dependency injection pattern" do
    defmodule Stopwatch do
      @doc "Reads the injected clock twice and returns the elapsed seconds between reads."
      def elapsed_seconds(clock) do
        t0 = Clock.now(clock)
        t1 = Clock.now(clock)
        DateTime.diff(t1, t0)
      end
    end

    test "scripted reads drive a deterministic elapsed measurement" do
      script = [~U[2024-06-01 12:00:00Z], ~U[2024-06-01 12:00:42Z]]
      {:ok, clock} = Clock.Fake.start_link(script: script)
      assert Stopwatch.elapsed_seconds(clock) == 42
    end
  end
end
```
