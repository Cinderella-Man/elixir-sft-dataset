# Tiered Promo Code System — implement `select_tier/2`

Implement the private `select_tier/2` function. It takes a list of tier maps
(each shaped `%{threshold: cents, type: ..., value: ...}`) and a non-negative
integer `order_total` (cents). It must find the **applicable** tier: the one
with the **highest `threshold` that is `<= order_total`**.

Pair each tier with its 0-based index (the position in the original list), keep
only the tiers whose `threshold` is `<= order_total`, and:

- if none qualify (the order is below every threshold), return the atom
  `:below_min_order`;
- otherwise return `{tier, index}` — the qualifying `{tier, index}` pair whose
  `tier.threshold` is greatest.

Thresholds are guaranteed strictly ascending by validation, but do not rely on
list order for the result — select by maximum threshold.

```elixir
defmodule TieredPromoCodes do
  @moduledoc """
  In-memory context module for tiered promotional codes: each code carries a
  list of tiers `%{threshold, type, value}` and the discount scales with the
  order total (the highest tier whose threshold is `<= order_total` applies).

  All monetary values are non-negative integer cents. Data lives in a single
  supervised `GenServer` registered (by default) under `#{inspect(__MODULE__)}`.
  """

  use GenServer

  @tier_types [:percentage, :fixed_amount]

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

  @doc "Creates a tiered promo code from `attrs`. Returns `{:ok, code}` or `{:error, reason}`."
  @spec create(map()) :: {:ok, map()} | {:error, atom()}
  def create(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:create, attrs})

  @doc "Previews the discount for `code_string` on `order_total` (cents) without recording a use."
  @spec preview(String.t(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def preview(code_string, order_total)
      when is_binary(code_string) and is_integer(order_total) and order_total >= 0 do
    GenServer.call(__MODULE__, {:preview, code_string, order_total})
  end

  def apply_code(code_string, order_total, opts \\ [])
      when is_binary(code_string) and is_integer(order_total) and order_total >= 0 do
    GenServer.call(__MODULE__, {:apply, code_string, order_total, opts})
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
  def handle_call({:preview, cs, order_total}, _from, state) do
    reply =
      case Map.fetch(state.codes, cs) do
        :error ->
          {:error, :not_found}

        {:ok, code} ->
          case select_tier(code.tiers, order_total) do
            :below_min_order -> {:error, :below_min_order}
            {tier, index} -> {:ok, tier_discount(tier, order_total), index}
          end
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:apply, cs, order_total, opts}, _from, state) do
    user_id = Keyword.get(opts, :user_id)
    now = state.clock.()

    case check(cs, order_total, user_id, now, state) do
      {:ok, _code, discount} ->
        {:reply, {:ok, discount}, record_use(state, cs, user_id)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # --- build & validate codes ---

  defp build_code(attrs) do
    code = Map.get(attrs, :code)
    tiers = Map.get(attrs, :tiers)

    cond do
      not is_binary(code) ->
        {:error, :invalid_code}

      not valid_tiers?(tiers) ->
        {:error, :invalid_tiers}

      true ->
        {:ok,
         %{
           code: code,
           tiers: tiers,
           max_uses: Map.get(attrs, :max_uses, nil),
           max_uses_per_user: Map.get(attrs, :max_uses_per_user, nil),
           valid_from: Map.get(attrs, :valid_from, nil),
           valid_until: Map.get(attrs, :valid_until, nil)
         }}
    end
  end

  defp valid_tiers?(tiers) when is_list(tiers) and tiers != [] do
    Enum.all?(tiers, &valid_tier?/1) and ascending?(Enum.map(tiers, & &1.threshold))
  end

  defp valid_tiers?(_), do: false

  defp valid_tier?(%{threshold: t, type: type, value: v})
       when is_integer(t) and t >= 0 and is_number(v) and type in @tier_types do
    case type do
      :percentage -> v >= 0 and v <= 100
      :fixed_amount -> v >= 0
    end
  end

  defp valid_tier?(_), do: false

  defp ascending?([]), do: true
  defp ascending?([_]), do: true
  defp ascending?([a, b | rest]), do: a < b and ascending?([b | rest])

  defp ensure_unique(cs, state) do
    if Map.has_key?(state.codes, cs), do: {:error, :already_exists}, else: :ok
  end

  # --- tier selection & discount ---

  defp select_tier(tiers, order_total) do
    # TODO
  end

  defp tier_discount(%{type: :percentage, value: v}, order_total),
    do: round(order_total * v / 100)

  defp tier_discount(%{type: :fixed_amount, value: v}, order_total), do: min(v, order_total)

  # --- checks (base precedence) ---

  defp check(cs, order_total, user_id, now, state) do
    with {:ok, code} <- fetch_code(cs, state),
         :ok <- check_not_yet_valid(code, now),
         :ok <- check_expired(code, now),
         {:ok, tier, _index} <- fetch_tier(code, order_total),
         :ok <- check_max_uses(code, cs, state),
         :ok <- check_max_uses_per_user(code, cs, user_id, state) do
      {:ok, code, tier_discount(tier, order_total)}
    end
  end

  defp fetch_code(cs, state) do
    case Map.fetch(state.codes, cs) do
      {:ok, code} -> {:ok, code}
      :error -> {:error, :not_found}
    end
  end

  defp fetch_tier(code, order_total) do
    case select_tier(code.tiers, order_total) do
      :below_min_order -> {:error, :below_min_order}
      {tier, index} -> {:ok, tier, index}
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