# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule BudgetPromoCodes do
  @moduledoc """
  In-memory context module for budget-capped promotional codes: each code may
  carry a total discount `:budget` (in cents). Successful applications draw from
  the budget, and an application that would exceed the remaining budget is
  clipped to what is left; once the budget is drained the code reports
  `:budget_exhausted`.

  All monetary values are non-negative integer cents. Data lives in a single
  supervised `GenServer` registered (by default) under `#{inspect(__MODULE__)}`.
  """

  use GenServer

  @valid_types [:percentage, :fixed_amount, :free_shipping]

  # --- lifecycle ---

  def start_link(opts \\ []) do
    clock = Keyword.get(opts, :clock, fn -> DateTime.utc_now() end)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{clock: clock}, name: name)
  end

  @impl true
  def init(%{clock: clock}) do
    {:ok, %{clock: clock, codes: %{}, total_uses: %{}, user_uses: %{}, dispensed: %{}}}
  end

  # --- public API ---

  def create(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:create, attrs})

  def apply_code(code_string, order_total, opts \\ [])
      when is_binary(code_string) and is_integer(order_total) and order_total >= 0 do
    GenServer.call(__MODULE__, {:apply, code_string, order_total, opts})
  end

  def remaining_budget(code_string) when is_binary(code_string) do
    GenServer.call(__MODULE__, {:remaining_budget, code_string})
  end

  def dispensed(code_string) when is_binary(code_string) do
    GenServer.call(__MODULE__, {:dispensed, code_string})
  end

  # --- server ---

  @impl true
  def handle_call({:create, attrs}, _from, state) do
    with {:ok, code} <- build_code(attrs),
         :ok <- ensure_unique(code.code, state) do
      {:reply, {:ok, code}, put_in(state.codes[code.code], code)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:apply, cs, order_total, opts}, _from, state) do
    user_id = Keyword.get(opts, :user_id)
    now = state.clock.()

    case check(cs, order_total, now, state) do
      {:ok, code} ->
        raw = raw_discount(code, order_total)
        {actual, state2} = draw(state, cs, code, raw)
        state3 = record_use(state2, cs, user_id)
        {:reply, {:ok, actual}, state3}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:remaining_budget, cs}, _from, state) do
    reply =
      case Map.fetch(state.codes, cs) do
        :error -> {:error, :not_found}
        {:ok, %{budget: nil}} -> {:ok, :unlimited}
        {:ok, %{budget: b}} -> {:ok, b - dispensed_of(state, cs)}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:dispensed, cs}, _from, state) do
    reply =
      case Map.has_key?(state.codes, cs) do
        false -> {:error, :not_found}
        true -> {:ok, dispensed_of(state, cs)}
      end

    {:reply, reply, state}
  end

  # --- build & validate codes ---

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
           budget: Map.get(attrs, :budget, nil),
           min_order_total: Map.get(attrs, :min_order_total, 0),
           max_uses: Map.get(attrs, :max_uses, nil),
           valid_from: Map.get(attrs, :valid_from, nil),
           valid_until: Map.get(attrs, :valid_until, nil)
         }}
    end
  end

  defp ensure_unique(cs, state) do
    if Map.has_key?(state.codes, cs), do: {:error, :already_exists}, else: :ok
  end

  # --- checks (precedence) ---

  defp check(cs, order_total, now, state) do
    with {:ok, code} <- fetch_code(cs, state),
         :ok <- check_not_yet_valid(code, now),
         :ok <- check_expired(code, now),
         :ok <- check_min_order(code, order_total),
         :ok <- check_max_uses(code, cs, state),
         :ok <- check_budget(code, cs, state) do
      {:ok, code}
    end
  end

  defp fetch_code(cs, state) do
    case Map.fetch(state.codes, cs) do
      {:ok, code} -> {:ok, code}
      :error -> {:error, :not_found}
    end
  end

  defp check_not_yet_valid(%{valid_from: nil}, _now), do: :ok

  defp check_not_yet_valid(%{valid_from: vf}, now) do
    if DateTime.compare(now, vf) == :lt, do: {:error, :not_yet_valid}, else: :ok
  end

  defp check_expired(%{valid_until: nil}, _now), do: :ok

  defp check_expired(%{valid_until: vu}, now) do
    if DateTime.compare(now, vu) == :gt, do: {:error, :expired}, else: :ok
  end

  defp check_min_order(%{min_order_total: min}, order_total) do
    if order_total >= min, do: :ok, else: {:error, :below_min_order}
  end

  defp check_max_uses(%{max_uses: nil}, _cs, _state), do: :ok

  defp check_max_uses(%{max_uses: max}, cs, state) do
    if total_uses(state, cs) >= max, do: {:error, :max_uses_exceeded}, else: :ok
  end

  defp check_budget(%{budget: nil}, _cs, _state), do: :ok

  defp check_budget(%{budget: budget}, cs, state) do
    if budget - dispensed_of(state, cs) <= 0, do: {:error, :budget_exhausted}, else: :ok
  end

  # --- discount & budget drawing ---

  defp raw_discount(%{type: :percentage, value: v}, order_total),
    do: round(order_total * v / 100)

  defp raw_discount(%{type: :fixed_amount, value: v}, order_total), do: min(v, order_total)
  defp raw_discount(%{type: :free_shipping, value: v}, _order_total), do: v

  defp draw(state, cs, %{budget: nil}, raw), do: {raw, add_dispensed(state, cs, raw)}

  defp draw(state, cs, %{budget: budget}, raw) do
    remaining = budget - dispensed_of(state, cs)
    actual = min(raw, remaining)
    {actual, add_dispensed(state, cs, actual)}
  end

  # --- accounting ---

  defp total_uses(state, cs), do: Map.get(state.total_uses, cs, 0)
  defp dispensed_of(state, cs), do: Map.get(state.dispensed, cs, 0)

  defp add_dispensed(state, cs, amount) do
    update_in(state.dispensed[cs], &((&1 || 0) + amount))
  end

  defp record_use(state, cs, user_id) do
    state = update_in(state.total_uses[cs], &((&1 || 0) + 1))

    case user_id do
      nil -> state
      _ -> update_in(state.user_uses[{cs, user_id}], &((&1 || 0) + 1))
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule BudgetPromoCodesTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    @base ~U[2026-06-01 00:00:00Z]
    def start_link(_ \\ nil), do: Agent.start_link(fn -> @base end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def set(%DateTime{} = dt), do: Agent.update(__MODULE__, fn _ -> dt end)
    def base, do: @base
  end

  @past ~U[2020-01-01 00:00:00Z]
  @future ~U[2030-01-01 00:00:00Z]

  setup do
    start_supervised!(Clock)
    start_supervised!({BudgetPromoCodes, clock: &Clock.now/0})
    :ok
  end

  # --- create ---

  test "create accepts a valid code" do
    assert {:ok, _} =
             BudgetPromoCodes.create(%{code: "B", type: :fixed_amount, value: 500, budget: 1_000})
  end

  test "create rejects duplicates and invalid type" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "DUP", type: :percentage, value: 10})

    assert {:error, :already_exists} =
             BudgetPromoCodes.create(%{code: "DUP", type: :fixed_amount, value: 500})

    assert {:error, :invalid_type} =
             BudgetPromoCodes.create(%{code: "BAD", type: :bogus, value: 1})
  end

  # --- basic discounts (no budget) ---

  test "unbudgeted percentage discount" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "HALF", type: :percentage, value: 50})
    assert {:ok, 5_000} = BudgetPromoCodes.apply_code("HALF", 10_000)
    assert {:ok, :unlimited} = BudgetPromoCodes.remaining_budget("HALF")
  end

  test "unbudgeted code dispenses the full discount every time" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "F5", type: :fixed_amount, value: 500})
    assert {:ok, 500} = BudgetPromoCodes.apply_code("F5", 10_000)
    assert {:ok, 500} = BudgetPromoCodes.apply_code("F5", 10_000)
    assert {:ok, 1_000} = BudgetPromoCodes.dispensed("F5")
  end

  # --- budget clipping (fixed) ---

  test "fixed-amount budget clips the final application and then exhausts" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "FB", type: :fixed_amount, value: 5_000, budget: 8_000})

    assert {:ok, 5_000} = BudgetPromoCodes.apply_code("FB", 10_000)
    assert {:ok, 3_000} = BudgetPromoCodes.remaining_budget("FB")
    # clipped to remaining 3_000
    assert {:ok, 3_000} = BudgetPromoCodes.apply_code("FB", 10_000)
    assert {:ok, 0} = BudgetPromoCodes.remaining_budget("FB")
    assert {:error, :budget_exhausted} = BudgetPromoCodes.apply_code("FB", 10_000)
    assert {:ok, 8_000} = BudgetPromoCodes.dispensed("FB")
  end

  # --- budget clipping (percentage) ---

  test "percentage budget clips a large discount" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "PB", type: :percentage, value: 50, budget: 6_000})

    assert {:ok, 5_000} = BudgetPromoCodes.apply_code("PB", 10_000)
    assert {:ok, 1_000} = BudgetPromoCodes.apply_code("PB", 10_000)
    assert {:error, :budget_exhausted} = BudgetPromoCodes.apply_code("PB", 10_000)
  end

  # --- free shipping honors budget ---

  test "free shipping draws from budget" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "SB", type: :free_shipping, value: 999, budget: 1_500})

    assert {:ok, 999} = BudgetPromoCodes.apply_code("SB", 10_000)
    assert {:ok, 501} = BudgetPromoCodes.apply_code("SB", 10_000)
    assert {:error, :budget_exhausted} = BudgetPromoCodes.apply_code("SB", 10_000)
  end

  # --- precedence & failed applications ---

  test "unknown code returns :not_found" do
    # TODO
  end

  test "below minimum order does not touch budget" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "MIN",
        type: :fixed_amount,
        value: 500,
        budget: 1_000,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = BudgetPromoCodes.apply_code("MIN", 3_000)
    assert {:ok, 1_000} = BudgetPromoCodes.remaining_budget("MIN")
    assert {:ok, 0} = BudgetPromoCodes.dispensed("MIN")
  end

  test "max_uses is enforced ahead of budget exhaustion" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "MU",
        type: :fixed_amount,
        value: 100,
        budget: 10_000,
        max_uses: 2
      })

    assert {:ok, 100} = BudgetPromoCodes.apply_code("MU", 10_000)
    assert {:ok, 100} = BudgetPromoCodes.apply_code("MU", 10_000)
    assert {:error, :max_uses_exceeded} = BudgetPromoCodes.apply_code("MU", 10_000)
  end

  test "time window is enforced with inclusive boundaries" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "SOON", type: :percentage, value: 10, valid_from: @future})

    assert {:error, :not_yet_valid} = BudgetPromoCodes.apply_code("SOON", 10_000)

    {:ok, _} =
      BudgetPromoCodes.create(%{code: "OLD", type: :percentage, value: 10, valid_until: @past})

    assert {:error, :expired} = BudgetPromoCodes.apply_code("OLD", 10_000)

    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "EDGE",
        type: :percentage,
        value: 10,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    assert {:ok, 1_000} = BudgetPromoCodes.apply_code("EDGE", 10_000)
  end

  test "clock advancing past valid_until exhausts nothing but expires the code" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "WIN",
        type: :fixed_amount,
        value: 500,
        budget: 5_000,
        valid_until: ~U[2026-06-10 00:00:00Z]
      })

    assert {:ok, 500} = BudgetPromoCodes.apply_code("WIN", 10_000)
    Clock.set(~U[2026-06-11 00:00:00Z])
    assert {:error, :expired} = BudgetPromoCodes.apply_code("WIN", 10_000)
    assert {:ok, 4_500} = BudgetPromoCodes.remaining_budget("WIN")
  end
end
```
