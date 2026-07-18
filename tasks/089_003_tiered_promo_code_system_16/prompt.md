# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `check_not_yet_valid` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Tiered Promo Code System

Write me an Elixir context module called `TieredPromoCodes` that manages
promotional codes whose discount **scales with the order total** via configured
tiers. It keeps its data in-memory in a single supervised process (use a
`GenServer` or `Agent`).

## Money & units

All monetary values are **non-negative integers representing cents** (so
`$100.00` is `10_000`). Percentages are plain numbers in the range `0..100`.

## Starting the process

- `TieredPromoCodes.start_link(opts)` returns `{:ok, pid}`.
  - `:clock` — a zero-arity function returning the current UTC `DateTime`.
    Default `fn -> DateTime.utc_now() end`.
  - `:name` — registration name. Default `__MODULE__` (named singleton).
  - Must be startable under a supervisor.

All API functions operate on the default (`__MODULE__`) instance.

## Creating codes: `create/1`

`TieredPromoCodes.create(attrs)` returns `{:ok, code}` or `{:error, reason}`.

`attrs` fields:

- `:code` — required string, unique.
- `:tiers` — required non-empty list of tier maps, each
  `%{threshold: cents, type: :percentage | :fixed_amount, value: number}`.
  A tier applies when `order_total >= threshold`.
- `:max_uses` — optional integer, default `nil` (unlimited).
- `:max_uses_per_user` — optional integer, default `nil`.
- `:valid_from` / `:valid_until` — optional `DateTime`, default `nil`.

Validation:

- Not a binary `:code` → `{:error, :invalid_code}`.
- `:tiers` not a non-empty list, or any tier malformed, or thresholds not
  **strictly ascending** → `{:error, :invalid_tiers}`. A tier is malformed if
  `threshold` is not a non-negative integer, `type` is not one of the two
  allowed atoms, `value` is not a number, or (for `:percentage`) `value` is
  outside `0..100`, or (for either) `value` is negative.
- Duplicate `:code` → `{:error, :already_exists}`.

## Selecting a tier

For a given `order_total`, the applicable tier is the one with the **highest
`threshold` that is `<= order_total`**. If no tier qualifies (the order is below
the smallest threshold), that condition is reported as `:below_min_order`.

Discount for the chosen tier:

- `:percentage` → `round(order_total * value / 100)`.
- `:fixed_amount` → `min(value, order_total)`.

## Previewing: `preview/2`

`TieredPromoCodes.preview(code_string, order_total)` returns
`{:ok, discount, tier_index}` (0-based index into the tier list) **without
consuming a use** and without checking the time window or usage limits, or
`{:error, :not_found}` / `{:error, :below_min_order}`.

## Applying: `apply_code/2` and `apply_code/3`

`TieredPromoCodes.apply_code(code_string, order_total, opts \\ [])` returns
`{:ok, discount}` or `{:error, reason}`. `opts` may contain `:user_id`.

Evaluate in this precedence order and return the **first** failure:

1. Unknown code → `:not_found`.
2. Now before `:valid_from` → `:not_yet_valid`.
3. Now after `:valid_until` → `:expired`.
4. No tier qualifies for `order_total` → `:below_min_order`.
5. Total uses `>= :max_uses` → `:max_uses_exceeded`.
6. This user's uses `>= :max_uses_per_user` → `:max_uses_per_user_exceeded`.

Boundaries are inclusive. Only a successful application consumes a use
(increment total, and per-user when `:user_id` is given).

## Constraints

Give me the complete module in a single file (`solution.ex`). Use only the OTP
standard library — no external dependencies.

## The module with `check_not_yet_valid` missing

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
    tiers
    |> Enum.with_index()
    |> Enum.filter(fn {tier, _i} -> tier.threshold <= order_total end)
    |> case do
      [] -> :below_min_order
      qualifying -> Enum.max_by(qualifying, fn {tier, _i} -> tier.threshold end)
    end
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

  defp check_not_yet_valid(%{valid_from: nil}, _now) do
    # TODO
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

Give me only the complete implementation of `check_not_yet_valid` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
