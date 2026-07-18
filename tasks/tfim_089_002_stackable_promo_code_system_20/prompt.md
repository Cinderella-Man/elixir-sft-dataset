# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
  @spec apply_codes([String.t()], non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, atom()}
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

## Test harness — implement the `# TODO` test

```elixir
defmodule StackablePromoCodesTest do
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
    start_supervised!({StackablePromoCodes, clock: &Clock.now/0})
    :ok
  end

  defp find(list, code), do: Enum.find(list, &(&1.code == code))

  # --- create ---

  test "create returns {:ok, code} for a valid code" do
    assert {:ok, _} = StackablePromoCodes.create(%{code: "P20", type: :percentage, value: 20})
  end

  test "create rejects duplicate codes" do
    assert {:ok, _} = StackablePromoCodes.create(%{code: "DUP", type: :percentage, value: 10})

    assert {:error, :already_exists} =
             StackablePromoCodes.create(%{code: "DUP", type: :fixed_amount, value: 500})
  end

  test "create rejects an invalid type" do
    assert {:error, :invalid_type} =
             StackablePromoCodes.create(%{code: "BAD", type: :bogus, value: 1})
  end

  # --- empty list ---

  test "empty code list returns :no_codes" do
    assert {:error, :no_codes} = StackablePromoCodes.apply_codes([], 10_000)
  end

  # --- stacking of a percentage and a fixed code ---

  test "a percentage and a fixed code stack" do
    {:ok, _} = StackablePromoCodes.create(%{code: "PCT20", type: :percentage, value: 20})
    {:ok, _} = StackablePromoCodes.create(%{code: "FIX15", type: :fixed_amount, value: 1_500})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["PCT20", "FIX15"], 10_000)
    # 20% of 10_000 = 2_000; then 1_500 off the remaining 8_000
    assert r.total_discount == 3_500
    assert r.final_total == 6_500
    assert find(r.applied, "PCT20").discount == 2_000
    assert find(r.applied, "FIX15").discount == 1_500
    assert r.rejected == []
  end

  # --- only the best percentage applies ---

  test "only the highest percentage code applies; others rejected" do
    {:ok, _} = StackablePromoCodes.create(%{code: "P20", type: :percentage, value: 20})
    {:ok, _} = StackablePromoCodes.create(%{code: "P50", type: :percentage, value: 50})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["P20", "P50"], 10_000)
    assert find(r.applied, "P50").discount == 5_000
    assert find(r.applied, "P20") == nil
    assert find(r.rejected, "P20").reason == :percentage_already_applied
    assert r.total_discount == 5_000
  end

  # --- free shipping stacks with a percentage ---

  test "free shipping stacks with a percentage" do
    {:ok, _} = StackablePromoCodes.create(%{code: "P10", type: :percentage, value: 10})
    {:ok, _} = StackablePromoCodes.create(%{code: "SHIP", type: :free_shipping, value: 999})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["P10", "SHIP"], 10_000)
    assert find(r.applied, "P10").discount == 1_000
    assert find(r.applied, "SHIP").discount == 999
    assert r.total_discount == 1_999
    assert r.final_total == 8_001
  end

  test "only one free shipping code applies" do
    {:ok, _} = StackablePromoCodes.create(%{code: "S1", type: :free_shipping, value: 500})
    {:ok, _} = StackablePromoCodes.create(%{code: "S2", type: :free_shipping, value: 700})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["S1", "S2"], 10_000)
    assert find(r.applied, "S1").discount == 500
    assert find(r.rejected, "S2").reason == :free_shipping_already_applied
  end

  # --- total discount capped at the order total ---

  test "total discount never exceeds the order total" do
    {:ok, _} = StackablePromoCodes.create(%{code: "BIG", type: :fixed_amount, value: 5_000})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["BIG"], 3_000)
    assert find(r.applied, "BIG").discount == 3_000
    assert r.total_discount == 3_000
    assert r.final_total == 0
  end

  # --- invalid codes rejected, valid ones still apply ---

  test "unknown code is rejected while valid codes apply" do
    {:ok, _} = StackablePromoCodes.create(%{code: "GOOD", type: :fixed_amount, value: 250})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["GOOD", "NOPE"], 10_000)
    assert find(r.applied, "GOOD").discount == 250
    assert find(r.rejected, "NOPE").reason == :not_found
  end

  test "duplicate code in the same order is rejected once" do
    {:ok, _} = StackablePromoCodes.create(%{code: "F5", type: :fixed_amount, value: 500})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["F5", "F5"], 10_000)
    assert length(Enum.filter(r.applied, &(&1.code == "F5"))) == 1
    assert find(r.rejected, "F5").reason == :duplicate_in_order
  end

  test "below-minimum code is rejected but others apply" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "MIN",
        type: :fixed_amount,
        value: 500,
        min_order_total: 5_000
      })

    {:ok, _} = StackablePromoCodes.create(%{code: "ANY", type: :fixed_amount, value: 250})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["MIN", "ANY"], 3_000)
    assert find(r.rejected, "MIN").reason == :below_min_order
    assert find(r.applied, "ANY").discount == 250
  end

  # --- usage accounting ---

  test "only applied codes consume uses" do
    {:ok, _} =
      StackablePromoCodes.create(%{code: "ONCE", type: :fixed_amount, value: 500, max_uses: 1})

    {:ok, _} = StackablePromoCodes.create(%{code: "DUPE", type: :percentage, value: 10})
    {:ok, _} = StackablePromoCodes.create(%{code: "DUPE2", type: :percentage, value: 20})

    # DUPE loses to DUPE2 and is rejected -> must not consume
    assert {:ok, _} = StackablePromoCodes.apply_codes(["ONCE", "DUPE", "DUPE2"], 10_000)
    assert {:ok, r} = StackablePromoCodes.apply_codes(["ONCE"], 10_000)
    assert find(r.rejected, "ONCE").reason == :max_uses_exceeded

    # DUPE was never consumed, still usable
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["DUPE"], 10_000)
    assert find(r2.applied, "DUPE").discount == 1_000
  end

  test "per-user limit is enforced independently" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "PU",
        type: :fixed_amount,
        value: 500,
        max_uses_per_user: 1
      })

    assert {:ok, r1} = StackablePromoCodes.apply_codes(["PU"], 10_000, user_id: "u1")
    assert find(r1.applied, "PU")
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["PU"], 10_000, user_id: "u1")
    assert find(r2.rejected, "PU").reason == :max_uses_per_user_exceeded
    assert {:ok, r3} = StackablePromoCodes.apply_codes(["PU"], 10_000, user_id: "u2")
    assert find(r3.applied, "PU").discount == 500
  end

  # --- time window ---

  test "expired code is rejected once the clock advances" do
    valid_until = ~U[2026-06-10 00:00:00Z]

    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "WIN",
        type: :percentage,
        value: 10,
        valid_until: valid_until
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["WIN"], 10_000)
    assert find(r.applied, "WIN").discount == 1_000

    Clock.set(~U[2026-06-11 00:00:00Z])
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["WIN"], 10_000)
    assert find(r2.rejected, "WIN").reason == :expired
  end

  test "not-yet-valid and inclusive boundaries" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "SOON",
        type: :percentage,
        value: 10,
        valid_from: @future
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["SOON"], 10_000)
    assert find(r.rejected, "SOON").reason == :not_yet_valid

    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "EDGE",
        type: :percentage,
        value: 10,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    assert {:ok, r2} = StackablePromoCodes.apply_codes(["EDGE"], 10_000)
    assert find(r2.applied, "EDGE").discount == 1_000
    assert @past
  end

  test "each discount is capped at the remaining total in prompt order" do
    {:ok, _} = StackablePromoCodes.create(%{code: "P90", type: :percentage, value: 90})
    {:ok, _} = StackablePromoCodes.create(%{code: "SH", type: :free_shipping, value: 500})
    {:ok, _} = StackablePromoCodes.create(%{code: "FA", type: :fixed_amount, value: 400})
    {:ok, _} = StackablePromoCodes.create(%{code: "FB", type: :fixed_amount, value: 300})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["FA", "SH", "FB", "P90"], 1_000)
    assert find(r.applied, "P90").discount == 900
    assert find(r.applied, "P90").type == :percentage
    assert find(r.applied, "SH").discount == 100
    assert find(r.applied, "FA").discount == 0
    assert find(r.applied, "FB").discount == 0
    assert r.total_discount == 1_000
    assert r.final_total == 0
    assert r.rejected == []
  end

  test "expiry outranks the minimum-order check for the same code" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "OLD",
        type: :fixed_amount,
        value: 500,
        min_order_total: 50_000,
        valid_until: ~U[2026-05-01 00:00:00Z]
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["OLD"], 1_000)
    assert find(r.rejected, "OLD").reason == :expired
    assert r.applied == []
    assert r.total_discount == 0
  end

  test "an order total exactly equal to min_order_total applies the code" do
    # TODO
  end

  test "max_uses and max_uses_per_user default to unlimited applications" do
    {:ok, _} = StackablePromoCodes.create(%{code: "FREE", type: :fixed_amount, value: 100})

    for _ <- 1..3 do
      assert {:ok, r} = StackablePromoCodes.apply_codes(["FREE"], 10_000, user_id: "u1")
      assert find(r.applied, "FREE").discount == 100
      assert r.rejected == []
    end
  end

  test "max_uses counts applications across all users" do
    {:ok, _} =
      StackablePromoCodes.create(%{code: "CAP2", type: :fixed_amount, value: 500, max_uses: 2})

    assert {:ok, r1} = StackablePromoCodes.apply_codes(["CAP2"], 10_000, user_id: "u1")
    assert find(r1.applied, "CAP2").discount == 500
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["CAP2"], 10_000, user_id: "u2")
    assert find(r2.applied, "CAP2").discount == 500
    assert {:ok, r3} = StackablePromoCodes.apply_codes(["CAP2"], 10_000, user_id: "u3")
    assert find(r3.rejected, "CAP2").reason == :max_uses_exceeded
    assert r3.applied == []
  end

  test "not-yet-valid outranks expired when both window checks fail" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "BOTH",
        type: :percentage,
        value: 10,
        valid_from: @future,
        valid_until: @past
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["BOTH"], 10_000)
    assert find(r.rejected, "BOTH").reason == :not_yet_valid
  end
end
```
