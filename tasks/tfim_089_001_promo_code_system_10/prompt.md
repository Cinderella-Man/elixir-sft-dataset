# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule PromoCodes do
  @moduledoc """
  An in-memory context module for managing promotional discount codes and
  applying them to orders.

  All monetary values are non-negative integers representing cents. Percentages
  are plain numbers in the range `0..100`.

  Data is kept in a single supervised `GenServer` process. By default the
  process registers itself under `#{inspect(__MODULE__)}` and acts as a named
  singleton, so the public API functions take no explicit server argument.
  """

  use GenServer

  @valid_types [:percentage, :fixed_amount, :free_shipping]

  # ---------------------------------------------------------------------------
  # Process lifecycle
  # ---------------------------------------------------------------------------

  @doc """
  Starts the promo-code process.

  Options:

    * `:clock` — a zero-arity function returning the current UTC `DateTime`.
      Defaults to `fn -> DateTime.utc_now() end`.
    * `:name` — the name to register the process under. Defaults to
      `#{inspect(__MODULE__)}`.
  """
  def start_link(opts \\ []) do
    clock = Keyword.get(opts, :clock, fn -> DateTime.utc_now() end)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{clock: clock}, name: name)
  end

  @impl true
  def init(%{clock: clock}) do
    state = %{
      clock: clock,
      # code_string => code map
      codes: %{},
      # code_string => integer (total successful uses)
      total_uses: %{},
      # {code_string, user_id} => integer (per-user successful uses)
      user_uses: %{}
    }

    {:ok, state}
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new promo code.

  Returns `{:ok, code}` on success or `{:error, reason}` where `reason` is one
  of `:invalid_type` or `:already_exists`.
  """
  def create(attrs) when is_map(attrs) do
    GenServer.call(server(), {:create, attrs})
  end

  @doc """
  Applies a code to an order total (in cents).

  Returns `{:ok, discount_amount}` (a non-negative integer in cents) or
  `{:error, reason}`.

  `opts` may contain `:user_id` for per-user usage limits.
  """
  def apply(code_string, order_total, opts \\ [])
      when is_binary(code_string) and is_integer(order_total) and order_total >= 0 do
    GenServer.call(server(), {:apply, code_string, order_total, opts})
  end

  defp server, do: __MODULE__

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_call({:create, attrs}, _from, state) do
    with {:ok, code} <- build_code(attrs),
         :ok <- ensure_unique(code.code, state) do
      new_state = put_in(state.codes[code.code], code)
      {:reply, {:ok, code}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:apply, code_string, order_total, opts}, _from, state) do
    user_id = Keyword.get(opts, :user_id)
    now = state.clock.()

    case check(code_string, order_total, user_id, now, state) do
      {:ok, code, discount} ->
        new_state = record_use(state, code_string, user_id)
        {:reply, {:ok, discount}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Code construction & validation
  # ---------------------------------------------------------------------------

  defp build_code(attrs) do
    code = Map.get(attrs, :code)
    type = Map.get(attrs, :type)
    value = Map.get(attrs, :value)

    cond do
      not is_binary(code) ->
        {:error, :invalid_code}

      type not in @valid_types ->
        {:error, :invalid_type}

      not is_number(value) ->
        {:error, :invalid_value}

      true ->
        {:ok,
         %{
           code: code,
           type: type,
           value: value,
           min_order_total: Map.get(attrs, :min_order_total, 0),
           max_uses: Map.get(attrs, :max_uses, nil),
           max_uses_per_user: Map.get(attrs, :max_uses_per_user, nil),
           valid_from: Map.get(attrs, :valid_from, nil),
           valid_until: Map.get(attrs, :valid_until, nil)
         }}
    end
  end

  defp ensure_unique(code_string, state) do
    if Map.has_key?(state.codes, code_string) do
      {:error, :already_exists}
    else
      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Application checks (evaluated in strict precedence order)
  # ---------------------------------------------------------------------------

  defp check(code_string, order_total, user_id, now, state) do
    with {:ok, code} <- fetch_code(code_string, state),
         :ok <- check_not_yet_valid(code, now),
         :ok <- check_expired(code, now),
         :ok <- check_min_order(code, order_total),
         :ok <- check_max_uses(code, code_string, state),
         :ok <- check_max_uses_per_user(code, code_string, user_id, state) do
      {:ok, code, discount(code, order_total)}
    end
  end

  defp fetch_code(code_string, state) do
    case Map.fetch(state.codes, code_string) do
      {:ok, code} -> {:ok, code}
      :error -> {:error, :not_found}
    end
  end

  defp check_not_yet_valid(%{valid_from: nil}, _now), do: :ok

  defp check_not_yet_valid(%{valid_from: valid_from}, now) do
    if DateTime.compare(now, valid_from) == :lt do
      {:error, :not_yet_valid}
    else
      :ok
    end
  end

  defp check_expired(%{valid_until: nil}, _now), do: :ok

  defp check_expired(%{valid_until: valid_until}, now) do
    if DateTime.compare(now, valid_until) == :gt do
      {:error, :expired}
    else
      :ok
    end
  end

  defp check_min_order(%{min_order_total: min}, order_total) do
    if order_total >= min do
      :ok
    else
      {:error, :below_min_order}
    end
  end

  defp check_max_uses(%{max_uses: nil}, _code_string, _state), do: :ok

  defp check_max_uses(%{max_uses: max}, code_string, state) do
    if total_uses(state, code_string) >= max do
      {:error, :max_uses_exceeded}
    else
      :ok
    end
  end

  # Per-user limits only apply when a user_id is provided.
  defp check_max_uses_per_user(%{max_uses_per_user: nil}, _code_string, _user_id, _state), do: :ok
  defp check_max_uses_per_user(_code, _code_string, nil, _state), do: :ok

  defp check_max_uses_per_user(%{max_uses_per_user: max}, code_string, user_id, state) do
    if user_uses(state, code_string, user_id) >= max do
      {:error, :max_uses_per_user_exceeded}
    else
      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Discount calculation
  # ---------------------------------------------------------------------------

  defp discount(%{type: :percentage, value: value}, order_total) do
    round(order_total * value / 100)
  end

  defp discount(%{type: :fixed_amount, value: value}, order_total) do
    min(value, order_total)
  end

  defp discount(%{type: :free_shipping, value: value}, _order_total) do
    value
  end

  # ---------------------------------------------------------------------------
  # Usage accounting
  # ---------------------------------------------------------------------------

  defp total_uses(state, code_string), do: Map.get(state.total_uses, code_string, 0)

  defp user_uses(_state, _code_string, nil), do: 0
  defp user_uses(state, code_string, user_id), do: Map.get(state.user_uses, {code_string, user_id}, 0)

  defp record_use(state, code_string, user_id) do
    state = update_in(state.total_uses[code_string], &((&1 || 0) + 1))

    case user_id do
      nil -> state
      _ -> update_in(state.user_uses[{code_string, user_id}], &((&1 || 0) + 1))
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PromoCodesTest do
  use ExUnit.Case, async: false

  # --- Deterministic clock returning a DateTime ---

  defmodule Clock do
    use Agent

    @base ~U[2026-06-01 00:00:00Z]

    def start_link(_ \\ nil) do
      Agent.start_link(fn -> @base end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def set(%DateTime{} = dt), do: Agent.update(__MODULE__, fn _ -> dt end)
    def base, do: @base
  end

  @past ~U[2020-01-01 00:00:00Z]
  @future ~U[2030-01-01 00:00:00Z]

  setup do
    start_supervised!(Clock)
    start_supervised!({PromoCodes, clock: &Clock.now/0})
    :ok
  end

  # -------------------------------------------------------
  # create/1
  # -------------------------------------------------------

  test "create returns {:ok, code} for a valid percentage code" do
    assert {:ok, _code} =
             PromoCodes.create(%{code: "SAVE20", type: :percentage, value: 20})
  end

  test "create rejects duplicate codes" do
    assert {:ok, _} = PromoCodes.create(%{code: "DUP", type: :percentage, value: 10})
    assert {:error, :already_exists} =
             PromoCodes.create(%{code: "DUP", type: :fixed_amount, value: 500})
  end

  test "create rejects an invalid discount type" do
    assert {:error, :invalid_type} =
             PromoCodes.create(%{code: "BAD", type: :bogus, value: 1})
  end

  # -------------------------------------------------------
  # Discount type calculations
  # -------------------------------------------------------

  test "percentage: 50% off a $100 order returns $50" do
    {:ok, _} = PromoCodes.create(%{code: "HALF", type: :percentage, value: 50})
    assert {:ok, 5_000} = PromoCodes.apply("HALF", 10_000)
  end

  test "percentage: 20% off a $100 order returns $20" do
    {:ok, _} = PromoCodes.create(%{code: "TWENTY", type: :percentage, value: 20})
    assert {:ok, 2_000} = PromoCodes.apply("TWENTY", 10_000)
  end

  test "percentage discount is an integer (rounded)" do
    {:ok, _} = PromoCodes.create(%{code: "THIRD", type: :percentage, value: 33})
    assert {:ok, discount} = PromoCodes.apply("THIRD", 10_000)
    assert discount == 3_300
    assert is_integer(discount)
  end

  test "fixed_amount: $15 off returns 1500" do
    {:ok, _} = PromoCodes.create(%{code: "FIX15", type: :fixed_amount, value: 1_500})
    assert {:ok, 1_500} = PromoCodes.apply("FIX15", 10_000)
  end

  test "fixed_amount never exceeds the order total" do
    {:ok, _} = PromoCodes.create(%{code: "BIG", type: :fixed_amount, value: 5_000})
    assert {:ok, 3_000} = PromoCodes.apply("BIG", 3_000)
  end

  test "free_shipping returns the configured waived shipping amount" do
    # TODO
  end

  # -------------------------------------------------------
  # not_found
  # -------------------------------------------------------

  test "applying an unknown code returns :not_found" do
    assert {:error, :not_found} = PromoCodes.apply("NOPE", 10_000)
  end

  # -------------------------------------------------------
  # Time window constraints
  # -------------------------------------------------------

  test "not-yet-valid code returns :not_yet_valid" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "SOON",
        type: :percentage,
        value: 10,
        valid_from: @future
      })

    assert {:error, :not_yet_valid} = PromoCodes.apply("SOON", 10_000)
  end

  test "expired code returns :expired" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "OLD",
        type: :percentage,
        value: 10,
        valid_until: @past
      })

    assert {:error, :expired} = PromoCodes.apply("OLD", 10_000)
  end

  test "code inside its validity window applies successfully" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "NOW",
        type: :percentage,
        value: 10,
        valid_from: @past,
        valid_until: @future
      })

    assert {:ok, 1_000} = PromoCodes.apply("NOW", 10_000)
  end

  test "validity boundaries are inclusive" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "EDGE",
        type: :percentage,
        value: 10,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    # now == valid_from == valid_until
    assert {:ok, 1_000} = PromoCodes.apply("EDGE", 10_000)
  end

  test "code becomes expired once the clock advances past valid_until" do
    valid_until = ~U[2026-06-10 00:00:00Z]

    {:ok, _} =
      PromoCodes.create(%{
        code: "WINDOW",
        type: :percentage,
        value: 10,
        valid_until: valid_until
      })

    assert {:ok, 1_000} = PromoCodes.apply("WINDOW", 10_000)

    Clock.set(~U[2026-06-11 00:00:00Z])
    assert {:error, :expired} = PromoCodes.apply("WINDOW", 10_000)
  end

  # -------------------------------------------------------
  # Minimum order total
  # -------------------------------------------------------

  test "order below minimum returns :below_min_order" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "MIN50",
        type: :percentage,
        value: 10,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = PromoCodes.apply("MIN50", 3_000)
  end

  test "order exactly at the minimum passes" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "MIN50EQ",
        type: :percentage,
        value: 10,
        min_order_total: 5_000
      })

    assert {:ok, 500} = PromoCodes.apply("MIN50EQ", 5_000)
  end

  test "percentage discount combined with a minimum order total" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "COMBO",
        type: :percentage,
        value: 50,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = PromoCodes.apply("COMBO", 3_000)
    assert {:ok, 5_000} = PromoCodes.apply("COMBO", 10_000)
    assert {:ok, 2_500} = PromoCodes.apply("COMBO", 5_000)
  end

  test "free_shipping still respects the minimum order total" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "FREESHIPMIN",
        type: :free_shipping,
        value: 999,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = PromoCodes.apply("FREESHIPMIN", 3_000)
    assert {:ok, 999} = PromoCodes.apply("FREESHIPMIN", 5_000)
  end

  # -------------------------------------------------------
  # max_uses (total)
  # -------------------------------------------------------

  test "total max_uses is enforced" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "TWICE",
        type: :fixed_amount,
        value: 500,
        max_uses: 2
      })

    assert {:ok, 500} = PromoCodes.apply("TWICE", 10_000)
    assert {:ok, 500} = PromoCodes.apply("TWICE", 10_000)
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("TWICE", 10_000)
  end

  test "failed applications do not consume uses" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "NOCONSUME",
        type: :fixed_amount,
        value: 500,
        max_uses: 1,
        min_order_total: 5_000
      })

    # Below minimum -> error, must NOT consume the single available use
    assert {:error, :below_min_order} = PromoCodes.apply("NOCONSUME", 1_000)

    # The one real use is still available
    assert {:ok, 500} = PromoCodes.apply("NOCONSUME", 5_000)
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("NOCONSUME", 5_000)
  end

  # -------------------------------------------------------
  # max_uses_per_user
  # -------------------------------------------------------

  test "per-user max_uses is enforced independently per user" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "ONEEACH",
        type: :fixed_amount,
        value: 500,
        max_uses_per_user: 1
      })

    assert {:ok, 500} = PromoCodes.apply("ONEEACH", 10_000, user_id: "u1")
    assert {:error, :max_uses_per_user_exceeded} =
             PromoCodes.apply("ONEEACH", 10_000, user_id: "u1")

    # Different user is unaffected
    assert {:ok, 500} = PromoCodes.apply("ONEEACH", 10_000, user_id: "u2")
  end

  # -------------------------------------------------------
  # Multiple codes independence
  # -------------------------------------------------------

  test "different codes are tracked independently" do
    {:ok, _} = PromoCodes.create(%{code: "A", type: :percentage, value: 10, max_uses: 1})
    {:ok, _} = PromoCodes.create(%{code: "B", type: :fixed_amount, value: 250})

    assert {:ok, 1_000} = PromoCodes.apply("A", 10_000)
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("A", 10_000)

    # B is completely unaffected by A being exhausted
    assert {:ok, 250} = PromoCodes.apply("B", 10_000)
    assert {:ok, 250} = PromoCodes.apply("B", 10_000)
  end
end
```
