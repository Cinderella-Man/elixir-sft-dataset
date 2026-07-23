# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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
  @spec preview(String.t(), non_neg_integer()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | {:error, atom()}
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

## Test harness — implement the `# TODO` test

```elixir
defmodule TieredPromoCodesTest do
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

  @pct_tiers [
    %{threshold: 0, type: :percentage, value: 5},
    %{threshold: 5_000, type: :percentage, value: 10},
    %{threshold: 10_000, type: :percentage, value: 20}
  ]

  setup do
    start_supervised!(Clock)
    start_supervised!({TieredPromoCodes, clock: &Clock.now/0})
    :ok
  end

  # --- create validation ---

  test "create accepts a valid tiered code" do
    assert {:ok, _} = TieredPromoCodes.create(%{code: "SPEND", tiers: @pct_tiers})
  end

  test "create rejects duplicates" do
    assert {:ok, _} = TieredPromoCodes.create(%{code: "DUP", tiers: @pct_tiers})
    assert {:error, :already_exists} = TieredPromoCodes.create(%{code: "DUP", tiers: @pct_tiers})
  end

  test "create rejects an empty tier list" do
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "E", tiers: []})
  end

  test "create rejects non-ascending thresholds" do
    tiers = [
      %{threshold: 5_000, type: :percentage, value: 10},
      %{threshold: 5_000, type: :percentage, value: 20}
    ]

    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NA", tiers: tiers})
  end

  test "create rejects an out-of-range percentage" do
    tiers = [%{threshold: 0, type: :percentage, value: 150}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "BADP", tiers: tiers})
  end

  test "create rejects an unknown tier type" do
    tiers = [%{threshold: 0, type: :bogus, value: 10}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "BADT", tiers: tiers})
  end

  # --- tier selection ---

  test "selects the correct tier by order total" do
    {:ok, _} = TieredPromoCodes.create(%{code: "SPEND", tiers: @pct_tiers})
    assert {:ok, 150} = TieredPromoCodes.apply_code("SPEND", 3_000)
    assert {:ok, 500} = TieredPromoCodes.apply_code("SPEND", 5_000)
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("SPEND", 10_000)
    assert {:ok, 2_400} = TieredPromoCodes.apply_code("SPEND", 12_000)
  end

  test "order below the smallest threshold returns :below_min_order" do
    tiers = [
      %{threshold: 5_000, type: :percentage, value: 10},
      %{threshold: 10_000, type: :percentage, value: 20}
    ]

    {:ok, _} = TieredPromoCodes.create(%{code: "HIGH", tiers: tiers})
    assert {:error, :below_min_order} = TieredPromoCodes.apply_code("HIGH", 3_000)
    assert {:ok, 500} = TieredPromoCodes.apply_code("HIGH", 5_000)
  end

  test "fixed-amount tiers cap at the order total" do
    tiers = [%{threshold: 0, type: :fixed_amount, value: 1_500}]
    {:ok, _} = TieredPromoCodes.create(%{code: "F15", tiers: tiers})
    assert {:ok, 1_000} = TieredPromoCodes.apply_code("F15", 1_000)
    assert {:ok, 1_500} = TieredPromoCodes.apply_code("F15", 10_000)
  end

  # --- preview ---

  test "preview returns discount and tier index without consuming a use" do
    {:ok, _} = TieredPromoCodes.create(%{code: "PV", tiers: @pct_tiers, max_uses: 1})
    assert {:ok, 500, 1} = TieredPromoCodes.preview("PV", 5_000)
    assert {:ok, 2_000, 2} = TieredPromoCodes.preview("PV", 10_000)
    # the single use is still available
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("PV", 10_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("PV", 10_000)
  end

  test "preview reports :not_found and :below_min_order" do
    tiers = [%{threshold: 5_000, type: :percentage, value: 10}]
    {:ok, _} = TieredPromoCodes.create(%{code: "PVE", tiers: tiers})
    assert {:error, :not_found} = TieredPromoCodes.preview("NOPE", 5_000)
    assert {:error, :below_min_order} = TieredPromoCodes.preview("PVE", 1_000)
  end

  # --- errors and constraints ---

  test "unknown code returns :not_found" do
    assert {:error, :not_found} = TieredPromoCodes.apply_code("NOPE", 10_000)
  end

  test "max_uses is enforced" do
    {:ok, _} = TieredPromoCodes.create(%{code: "TWICE", tiers: @pct_tiers, max_uses: 2})
    assert {:ok, _} = TieredPromoCodes.apply_code("TWICE", 10_000)
    assert {:ok, _} = TieredPromoCodes.apply_code("TWICE", 10_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("TWICE", 10_000)
  end

  test "failed application (below min) does not consume a use" do
    tiers = [%{threshold: 5_000, type: :percentage, value: 10}]
    {:ok, _} = TieredPromoCodes.create(%{code: "NC", tiers: tiers, max_uses: 1})
    assert {:error, :below_min_order} = TieredPromoCodes.apply_code("NC", 1_000)
    assert {:ok, 500} = TieredPromoCodes.apply_code("NC", 5_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("NC", 5_000)
  end

  test "per-user limit is enforced independently" do
    {:ok, _} = TieredPromoCodes.create(%{code: "PU", tiers: @pct_tiers, max_uses_per_user: 1})
    assert {:ok, _} = TieredPromoCodes.apply_code("PU", 10_000, user_id: "u1")

    assert {:error, :max_uses_per_user_exceeded} =
             TieredPromoCodes.apply_code("PU", 10_000, user_id: "u1")

    assert {:ok, _} = TieredPromoCodes.apply_code("PU", 10_000, user_id: "u2")
  end

  test "time window is enforced with inclusive boundaries" do
    {:ok, _} = TieredPromoCodes.create(%{code: "SOON", tiers: @pct_tiers, valid_from: @future})
    assert {:error, :not_yet_valid} = TieredPromoCodes.apply_code("SOON", 10_000)

    {:ok, _} = TieredPromoCodes.create(%{code: "OLD", tiers: @pct_tiers, valid_until: @past})
    assert {:error, :expired} = TieredPromoCodes.apply_code("OLD", 10_000)

    {:ok, _} =
      TieredPromoCodes.create(%{
        code: "EDGE",
        tiers: @pct_tiers,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    assert {:ok, 2_000} = TieredPromoCodes.apply_code("EDGE", 10_000)
  end

  test "create rejects a non-binary code with :invalid_code" do
    assert {:error, :invalid_code} = TieredPromoCodes.create(%{code: :atom, tiers: @pct_tiers})
    assert {:error, :invalid_code} = TieredPromoCodes.create(%{tiers: @pct_tiers})
  end

  test "preview ignores the time window and exhausted usage limits" do
    {:ok, _} =
      TieredPromoCodes.create(%{code: "PVW", tiers: @pct_tiers, valid_until: @past, max_uses: 1})

    assert {:error, :expired} = TieredPromoCodes.apply_code("PVW", 10_000)
    assert {:ok, 2_000, 2} = TieredPromoCodes.preview("PVW", 10_000)

    {:ok, _} = TieredPromoCodes.create(%{code: "PVU", tiers: @pct_tiers, max_uses: 1})
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("PVU", 10_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("PVU", 10_000)
    assert {:ok, 2_000, 2} = TieredPromoCodes.preview("PVU", 10_000)

    {:ok, _} = TieredPromoCodes.create(%{code: "PVF", tiers: @pct_tiers, valid_from: @future})
    assert {:ok, 500, 1} = TieredPromoCodes.preview("PVF", 5_000)
  end

  test "expired window outranks a below-minimum order total" do
    # TODO
  end

  test "max_uses failure outranks the per-user failure when both are exhausted" do
    {:ok, _} =
      TieredPromoCodes.create(%{
        code: "BOTH",
        tiers: @pct_tiers,
        max_uses: 1,
        max_uses_per_user: 1
      })

    assert {:ok, 2_000} = TieredPromoCodes.apply_code("BOTH", 10_000, user_id: "u1")

    assert {:error, :max_uses_exceeded} =
             TieredPromoCodes.apply_code("BOTH", 10_000, user_id: "u1")
  end

  test "create rejects malformed thresholds and negative values" do
    neg_threshold = [%{threshold: -1, type: :percentage, value: 10}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NT", tiers: neg_threshold})

    float_threshold = [%{threshold: 1_000.0, type: :percentage, value: 10}]

    assert {:error, :invalid_tiers} =
             TieredPromoCodes.create(%{code: "FT", tiers: float_threshold})

    neg_fixed = [%{threshold: 0, type: :fixed_amount, value: -5}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NF", tiers: neg_fixed})

    bad_value = [%{threshold: 0, type: :percentage, value: "10"}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "BV", tiers: bad_value})

    not_a_map = [%{threshold: 0, type: :percentage, value: 10}, :nope]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NM", tiers: not_a_map})
  end

  test "a per-user rejection does not consume a total use" do
    {:ok, _} =
      TieredPromoCodes.create(%{
        code: "NOBURN",
        tiers: @pct_tiers,
        max_uses: 2,
        max_uses_per_user: 1
      })

    assert {:ok, 2_000} = TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u1")

    assert {:error, :max_uses_per_user_exceeded} =
             TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u1")

    # the rejected attempt must not have burned the second total use
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u2")

    assert {:error, :max_uses_exceeded} =
             TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u3")
  end
end
```
