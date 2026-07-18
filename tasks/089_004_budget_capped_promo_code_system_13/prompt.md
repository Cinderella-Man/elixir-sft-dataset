# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `fetch_code` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Budget-Capped Promo Code System

Write me an Elixir context module called `BudgetPromoCodes` that manages
promotional discount codes with a total **discount budget** — a fixed pool of
cents a code may dispense across all applications. When an application would draw
more than the remaining budget, the discount is **clipped** to what is left. It
keeps its data in-memory in a single supervised process (use a `GenServer` or
`Agent`).

## Money & units

All monetary values are **non-negative integers representing cents** (so
`$100.00` is `10_000`). Percentages are plain numbers in the range `0..100`.

## Starting the process

- `BudgetPromoCodes.start_link(opts)` returns `{:ok, pid}`.
  - `:clock` — a zero-arity function returning the current UTC `DateTime`.
    Default `fn -> DateTime.utc_now() end`.
  - `:name` — registration name. Default `__MODULE__` (named singleton).
  - Must be startable under a supervisor.

All API functions operate on the default (`__MODULE__`) instance.

## Creating codes: `create/1`

`BudgetPromoCodes.create(attrs)` returns `{:ok, code}` or `{:error, reason}`.

`attrs` fields:

- `:code` — required string, unique.
- `:type` — required, one of `:percentage`, `:fixed_amount`, `:free_shipping`.
- `:value` — required number, interpreted per type (percent off / cents off /
  shipping cents waived).
- `:budget` — optional integer cents, default `nil` (unlimited). The total
  discount the code may ever dispense, summed across all successful
  applications.
- `:min_order_total` — optional integer cents, default `0`.
- `:max_uses` — optional integer, default `nil` (unlimited).
- `:valid_from` / `:valid_until` — optional `DateTime`, default `nil`.

Validation:

- `:type` not one of the three atoms → `{:error, :invalid_type}`.
- Duplicate `:code` → `{:error, :already_exists}`.

## Applying: `apply_code/2` and `apply_code/3`

`BudgetPromoCodes.apply_code(code_string, order_total, opts \\ [])` returns
`{:ok, discount}` or `{:error, reason}`. `opts` may contain `:user_id` (used only
for usage counting, not budget).

### Raw discount (before budget clipping)

- `:percentage` → `round(order_total * value / 100)`.
- `:fixed_amount` → `min(value, order_total)`.
- `:free_shipping` → `value`.

### Checks and precedence

Evaluate in this order and return the **first** failure:

1. Unknown code → `:not_found`.
2. Now before `:valid_from` → `:not_yet_valid`.
3. Now after `:valid_until` → `:expired`.
4. `order_total` below `:min_order_total` → `:below_min_order`.
5. Total uses `>= :max_uses` → `:max_uses_exceeded`.
6. Budget is set and the remaining budget is `<= 0` → `:budget_exhausted`.

Boundaries are inclusive. On success, the returned `discount` is
`min(raw_discount, remaining_budget)` when a budget is set (otherwise
`raw_discount`). The dispensed amount is added to the code's running total and
the use counters are incremented. A failed application changes nothing.

## Inspection

- `BudgetPromoCodes.remaining_budget(code_string)` → `{:ok, :unlimited}` (no
  budget), `{:ok, cents}`, or `{:error, :not_found}`.
- `BudgetPromoCodes.dispensed(code_string)` → `{:ok, cents}` (total discount
  dispensed so far) or `{:error, :not_found}`.

## Constraints

Give me the complete module in a single file (`solution.ex`). Use only the OTP
standard library — no external dependencies.

## The module with `fetch_code` missing

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

  @spec start_link(keyword()) :: GenServer.on_start()
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

  @doc "Creates a budget-capped promo code from `attrs`. Returns `{:ok, code}` or error."
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
    # TODO
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

Give me only the complete implementation of `fetch_code` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
