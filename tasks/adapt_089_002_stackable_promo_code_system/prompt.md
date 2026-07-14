# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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
  @spec create(map()) :: {:ok, map()} | {:error, atom()}
  def create(attrs) when is_map(attrs) do
    GenServer.call(server(), {:create, attrs})
  end

  @doc """
  Applies a code to an order total (in cents).

  Returns `{:ok, discount_amount}` (a non-negative integer in cents) or
  `{:error, reason}`.

  `opts` may contain `:user_id` for per-user usage limits.
  """
  @spec apply(String.t(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, atom()}
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
      {:ok, _code, discount} ->
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

  defp user_uses(state, code_string, user_id) do
    Map.get(state.user_uses, {code_string, user_id}, 0)
  end

  defp record_use(state, code_string, user_id) do
    state = update_in(state.total_uses[code_string], &((&1 || 0) + 1))

    case user_id do
      nil -> state
      _ -> update_in(state.user_uses[{code_string, user_id}], &((&1 || 0) + 1))
    end
  end
end
```

## New specification

# Stackable Promo Code System

Write me an Elixir context module called `StackablePromoCodes` that manages
promotional discount codes and applies **several codes at once** to a single
order. It keeps its data in-memory in a single supervised process (use a
`GenServer` or `Agent`).

## Money & units

All monetary values are **non-negative integers representing cents** (so
`$100.00` is `10_000`). Order totals, fixed discount amounts, and returned
discount amounts are all integer cents. Percentages are plain numbers in the
range `0..100`.

## Starting the process

- `StackablePromoCodes.start_link(opts)` starts the process and returns
  `{:ok, pid}`.
  - It must accept a `:clock` option: a zero-arity function returning the
    current time as a UTC `DateTime`. Default `fn -> DateTime.utc_now() end`.
  - It must accept a `:name` option. Default `__MODULE__` (named singleton).
  - It must be startable under a supervisor.

All API functions operate on the default (`__MODULE__`) instance.

## Creating codes: `create/1`

`StackablePromoCodes.create(attrs)` takes a map and returns `{:ok, code}` or
`{:error, reason}`.

`attrs` fields:

- `:code` — required string, unique.
- `:type` — required, one of `:percentage`, `:fixed_amount`, `:free_shipping`.
- `:value` — required number, interpreted per type (percent off / cents off /
  shipping cents waived).
- `:min_order_total` — optional integer cents, default `0` (order total must be
  `>=` this).
- `:max_uses` — optional integer, default `nil` (unlimited total applications).
- `:max_uses_per_user` — optional integer, default `nil`.
- `:valid_from` / `:valid_until` — optional `DateTime`, default `nil`.

Validation:

- `:type` not one of the three atoms → `{:error, :invalid_type}`.
- Duplicate `:code` → `{:error, :already_exists}`.

## Applying codes: `apply_codes/2` and `apply_codes/3`

`StackablePromoCodes.apply_codes(codes, order_total, opts \\ [])` where `codes`
is a **list of code strings**. `opts` may contain `:user_id`.

An empty list returns `{:error, :no_codes}`. Otherwise it always returns
`{:ok, result}` where `result` is a map:

```
%{
  total_discount: integer,          # cents, never exceeds order_total
  final_total:    integer,          # order_total - total_discount
  applied:  [%{code: str, type: atom, discount: integer}, ...],
  rejected: [%{code: str, reason: atom}, ...]
}
```

### Per-code validity (first failure wins, base precedence)

For each code, in this order: unknown → `:not_found`; before `:valid_from` →
`:not_yet_valid`; after `:valid_until` → `:expired`; below `:min_order_total` →
`:below_min_order`; total uses `>= :max_uses` → `:max_uses_exceeded`; this
user's uses `>= :max_uses_per_user` → `:max_uses_per_user_exceeded`. A code
string appearing more than once in `codes` → the later occurrence is rejected
with `:duplicate_in_order`. Boundaries are inclusive.

### Stacking rules

Among the codes that pass validity:

- **At most one percentage code** may apply: the one with the highest `value`
  wins; the rest are rejected with `:percentage_already_applied`.
- **At most one free_shipping code** may apply: the first (in list order) wins;
  the rest are rejected with `:free_shipping_already_applied`.
- Any number of `:fixed_amount` codes may apply.

### Discount computation

Start `remaining = order_total`. Apply, in this order, capping each discount at
the current `remaining` and subtracting it:

1. the chosen percentage code → `round(order_total * value / 100)`,
2. the chosen free_shipping code → `value`,
3. each fixed_amount code (in list order) → `value`.

`total_discount = order_total - remaining`. Every code placed in `applied`
consumes a use (increment total, and per-user when `:user_id` is given). Codes
in `rejected` consume nothing.

## Constraints

Give me the complete module in a single file (`solution.ex`). Use only the OTP
standard library — no external dependencies.
