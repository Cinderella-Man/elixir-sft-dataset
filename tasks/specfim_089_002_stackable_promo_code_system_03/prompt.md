# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`apply_codes/3` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `apply_codes/3`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `apply_codes/3` missing

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

  @doc "Creates a promo code from `attrs`. Returns `{:ok, code}` or `{:error, reason}`."
  @spec create(map()) :: {:ok, map()} | {:error, atom()}
  def create(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:create, attrs})

  @doc """
  Applies a list of stackable promo `codes` to `order_total` (in cents), returning
  `{:ok, result}` with the applied/rejected breakdown, or `{:error, :no_codes}`.
  """
  # TODO: @spec
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

  defp ensure_unique(cs, state) do
    if Map.has_key?(state.codes, cs), do: {:error, :already_exists}, else: :ok
  end

  # --- processing an order ---

  defp process(codes, order_total, user_id, now, state) do
    {valids, rejected, _seen} =
      Enum.reduce(codes, {[], [], MapSet.new()}, fn cs, {v, r, seen} ->
        if MapSet.member?(seen, cs) do
          {v, [%{code: cs, reason: :duplicate_in_order} | r], seen}
        else
          seen = MapSet.put(seen, cs)

          case check(cs, order_total, user_id, now, state) do
            {:ok, code} -> {[{cs, code} | v], r, seen}
            {:error, reason} -> {v, [%{code: cs, reason: reason} | r], seen}
          end
        end
      end)

    valids = Enum.reverse(valids)
    rejected = Enum.reverse(rejected)

    percentages = Enum.filter(valids, fn {_cs, c} -> c.type == :percentage end)
    shippings = Enum.filter(valids, fn {_cs, c} -> c.type == :free_shipping end)
    fixeds = Enum.filter(valids, fn {_cs, c} -> c.type == :fixed_amount end)

    {chosen_pct, extra_pcts} =
      case percentages do
        [] ->
          {nil, []}

        _ ->
          best = Enum.max_by(percentages, fn {_cs, c} -> c.value end)
          {best, List.delete(percentages, best)}
      end

    {chosen_ship, extra_ships} =
      case shippings do
        [] -> {nil, []}
        [h | t] -> {h, t}
      end

    {remaining, applied} = {order_total, []}

    {remaining, applied} =
      case chosen_pct do
        nil ->
          {remaining, applied}

        {cs, c} ->
          d = min(round(order_total * c.value / 100), remaining)
          {remaining - d, applied ++ [%{code: cs, type: :percentage, discount: d}]}
      end

    {remaining, applied} =
      case chosen_ship do
        nil ->
          {remaining, applied}

        {cs, c} ->
          d = min(c.value, remaining)
          {remaining - d, applied ++ [%{code: cs, type: :free_shipping, discount: d}]}
      end

    {remaining, applied} =
      Enum.reduce(fixeds, {remaining, applied}, fn {cs, c}, {rem, acc} ->
        d = min(c.value, rem)
        {rem - d, acc ++ [%{code: cs, type: :fixed_amount, discount: d}]}
      end)

    new_state =
      Enum.reduce(applied, state, fn %{code: cs}, st -> record_use(st, cs, user_id) end)

    rejected_all =
      rejected ++
        Enum.map(extra_pcts, fn {cs, _c} ->
          %{code: cs, reason: :percentage_already_applied}
        end) ++
        Enum.map(extra_ships, fn {cs, _c} ->
          %{code: cs, reason: :free_shipping_already_applied}
        end)

    result = %{
      total_discount: order_total - remaining,
      final_total: remaining,
      applied: applied,
      rejected: rejected_all
    }

    {result, new_state}
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
