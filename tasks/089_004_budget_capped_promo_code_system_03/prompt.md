Implement the private `check/4` function. It takes the code string `cs`, the
`order_total` (integer cents), the current time `now` (a `DateTime`), and the
server `state`, and decides whether an application is allowed to proceed.

It must run the eligibility checks **in precedence order**, returning the first
failure it encounters and short-circuiting the rest. Use a `with` chain over the
existing helper functions:

1. Look the code up with `fetch_code/2` — an unknown code yields
   `{:error, :not_found}`.
2. `check_not_yet_valid/2` — `now` before `:valid_from` yields
   `{:error, :not_yet_valid}`.
3. `check_expired/2` — `now` after `:valid_until` yields `{:error, :expired}`.
4. `check_min_order/2` — `order_total` below `:min_order_total` yields
   `{:error, :below_min_order}`.
5. `check_max_uses/3` — total uses at or above `:max_uses` yields
   `{:error, :max_uses_exceeded}`.
6. `check_budget/3` — a set budget with `<= 0` remaining yields
   `{:error, :budget_exhausted}`.

When every check passes, return `{:ok, code}` with the fetched code map so the
caller can compute the discount. Because `with` propagates any non-matching
`{:error, reason}` unchanged, no explicit `else` clause is needed.

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
    # TODO
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