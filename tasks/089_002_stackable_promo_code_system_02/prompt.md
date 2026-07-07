# Fill in the middle: `process/5`

Below is the complete `StackablePromoCodes` module, except that the body of the
private `process/5` function has been replaced with `# TODO`. Implement
`process/5` so the module behaves as described.

## What `process/5` must do

`process(codes, order_total, user_id, now, state)` is the workhorse behind a
non-empty `apply_codes/3` call. It takes the raw list of code strings, the order
total in cents, the (possibly `nil`) `user_id`, the current time `now`, and the
current server `state`. It must return a `{result, new_state}` tuple, where
`result` is the public result map and `new_state` reflects the usage that the
applied codes consumed.

Implement it in these steps:

1. **Validate each code, tracking duplicates.** Fold over `codes` left-to-right,
   carrying an accumulator of `{valids, rejected, seen}` where `seen` is a
   `MapSet` of code strings already encountered. For each code string `cs`:
   - If `cs` is already in `seen`, reject it with reason `:duplicate_in_order`
     (leaving `valids`/`seen` unchanged).
   - Otherwise add `cs` to `seen` and call `check(cs, order_total, user_id, now,
     state)`. On `{:ok, code}` keep `{cs, code}` in `valids`; on
     `{:error, reason}` add `%{code: cs, reason: reason}` to `rejected`.

   Since the fold prepends, reverse both `valids` and `rejected` afterward so
   they preserve the original list order.

2. **Split the valid codes by type** into percentage, free_shipping, and
   fixed_amount lists (each element is a `{cs, code}` tuple).

3. **Apply the stacking rules.**
   - Percentages: if any, the one with the highest `value` is chosen; the others
     become "extras". If none, the chosen percentage is `nil`.
   - Free shipping: the first in list order is chosen; the rest are "extras". If
     none, `nil`.
   - Fixed amounts: all apply.

4. **Compute discounts.** Start with `remaining = order_total` and an empty
   `applied` list. In this exact order, each discount is capped at the current
   `remaining`, subtracted from it, and appended to `applied` as
   `%{code: cs, type: type, discount: d}`:
   1. the chosen percentage → `round(order_total * value / 100)`,
   2. the chosen free_shipping → its `value`,
   3. each fixed_amount code, in list order → its `value`.

5. **Record usage.** Fold the `applied` entries over `state`, calling
   `record_use(state, cs, user_id)` for each so that every applied code consumes
   one total use (and one per-user use when `user_id` is given).

6. **Build the rejected list.** Concatenate the validity-based `rejected` with
   `%{code: cs, reason: :percentage_already_applied}` for each extra percentage
   and `%{code: cs, reason: :free_shipping_already_applied}` for each extra
   free_shipping.

7. **Return** `{result, new_state}` where `result` is:
   ```
   %{
     total_discount: order_total - remaining,
     final_total:    remaining,
     applied:        applied,
     rejected:       rejected_all
   }
   ```

```elixir
defmodule StackablePromoCodes do
  @moduledoc """
  In-memory context module for stackable promotional codes.

  Applies a *list* of codes to a single order, enforcing per-code validity and
  stacking rules (one percentage, one free_shipping, unlimited fixed_amount),
  and reports which codes were applied and which were rejected.

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
    {:ok, %{clock: clock, codes: %{}, total_uses: %{}, user_uses: %{}}}
  end

  # --- public API ---

  def create(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:create, attrs})

  def apply_codes(codes, order_total, opts \\ [])
      when is_list(codes) and is_integer(order_total) and order_total >= 0 do
    GenServer.call(__MODULE__, {:apply, codes, order_total, opts})
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
  def handle_call({:apply, [], _order_total, _opts}, _from, state) do
    {:reply, {:error, :no_codes}, state}
  end

  def handle_call({:apply, codes, order_total, opts}, _from, state) do
    user_id = Keyword.get(opts, :user_id)
    now = state.clock.()
    {result, new_state} = process(codes, order_total, user_id, now, state)
    {:reply, {:ok, result}, new_state}
  end

  # --- build & validate codes ---

  defp build_code(attrs) do
    code = Map.get(attrs, :code)
    type = Map.get(attrs, :type)
    value = Map.get(attrs, :value)

    cond do
      not is_binary(code) -> {:error, :invalid_code}
      type not in @valid_types -> {:error, :invalid_type}
      not is_number(value) -> {:error, :invalid_value}
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

  defp ensure_unique(cs, state) do
    if Map.has_key?(state.codes, cs), do: {:error, :already_exists}, else: :ok
  end

  # --- processing an order ---

  defp process(codes, order_total, user_id, now, state) do
    # TODO
  end

  # --- per-code validity (base precedence) ---

  defp check(cs, order_total, user_id, now, state) do
    with {:ok, code} <- fetch_code(cs, state),
         :ok <- check_not_yet_valid(code, now),
         :ok <- check_expired(code, now),
         :ok <- check_min_order(code, order_total),
         :ok <- check_max_uses(code, cs, state),
         :ok <- check_max_uses_per_user(code, cs, user_id, state) do
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

  defp check_max_uses_per_user(%{max_uses_per_user: nil}, _cs, _uid, _state), do: :ok
  defp check_max_uses_per_user(_code, _cs, nil, _state), do: :ok

  defp check_max_uses_per_user(%{max_uses_per_user: max}, cs, uid, state) do
    if user_uses(state, cs, uid) >= max, do: {:error, :max_uses_per_user_exceeded}, else: :ok
  end

  # --- usage accounting ---

  defp total_uses(state, cs), do: Map.get(state.total_uses, cs, 0)
  defp user_uses(state, cs, uid), do: Map.get(state.user_uses, {cs, uid}, 0)

  defp record_use(state, cs, user_id) do
    state = update_in(state.total_uses[cs], &((&1 || 0) + 1))

    case user_id do
      nil -> state
      _ -> update_in(state.user_uses[{cs, user_id}], &((&1 || 0) + 1))
    end
  end
end
```