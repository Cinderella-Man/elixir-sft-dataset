# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

# Promo Code System

Write me an Elixir context module called `PromoCodes` that manages promotional
discount codes and applies them to orders. It keeps its data in-memory in a
single supervised process (use a `GenServer` or `Agent`).

## Money & units

All monetary values in this system are **non-negative integers representing
cents** (so `$100.00` is `10_000`). Order totals, fixed discount amounts, and
returned discount amounts are all integer cents. Percentages are plain numbers
in the range `0..100` (e.g. `20` means "20% off").

## Starting the process

- `PromoCodes.start_link(opts)` starts the process and returns `{:ok, pid}`.
  - It must accept a `:clock` option: a zero-arity function that returns the
    current time as a `DateTime` (UTC). If not provided, default to
    `fn -> DateTime.utc_now() end`.
  - It must accept a `:name` option for process registration. If not provided,
    register under `__MODULE__` (the module acts as a named singleton).
  - It must be startable under a supervisor (provide a child spec — `use
    GenServer` / `use Agent` gives you one for free).

All the API functions below operate on the default (named `__MODULE__`)
instance — they take no explicit server argument.

## Creating codes: `create/1`

`PromoCodes.create(attrs)` takes a map and returns `{:ok, code}` or
`{:error, reason}`.

`attrs` fields:

- `:code` — required, a string, e.g. `"SAVE20"`. Codes are unique.
- `:type` — required, one of `:percentage`, `:fixed_amount`, `:free_shipping`.
- `:value` — required integer/number, interpreted per type:
  - `:percentage` → the percent off (`0..100`).
  - `:fixed_amount` → the amount off, in cents.
  - `:free_shipping` → the shipping amount waived, in cents.
- `:min_order_total` — optional integer cents, default `0`. The order total must
  be **greater than or equal to** this for the code to apply.
- `:max_uses` — optional integer, default `nil` (unlimited). Total number of
  successful applications across all users.
- `:max_uses_per_user` — optional integer, default `nil` (unlimited). Number of
  successful applications per user (see `:user_id` below).
- `:valid_from` — optional `DateTime`, default `nil` (no lower bound).
- `:valid_until` — optional `DateTime`, default `nil` (no upper bound).

Validation:

- If `:type` is not one of the three allowed atoms, return `{:error, :invalid_type}`.
- If a code with the same `:code` string already exists, return
  `{:error, :already_exists}`.

On success return `{:ok, code}` where `code` is a map/struct describing the
stored code.

## Applying codes: `apply/2` and `apply/3`

`PromoCodes.apply(code_string, order_total, opts \\ [])` attempts to apply the
code to an order and returns `{:ok, discount_amount}` (a non-negative integer in
cents) or `{:error, reason}`.

`opts` may contain `:user_id` (any term identifying the user). When present, it
is used for the per-user usage limit. Calls without a `:user_id` still count
toward the total `:max_uses` but are not tracked per user.

### Discount calculation (on success)

- `:percentage` → `round(order_total * value / 100)`.
  (e.g. 50% of `10_000` → `5_000`; 20% of `10_000` → `2_000`.)
- `:fixed_amount` → `min(value, order_total)` (you can never discount more than
  the order total).
- `:free_shipping` → `value` (the configured shipping amount waived).

### Checks and error reasons

Evaluate in this precedence order and return the **first** failure:

1. Unknown code → `{:error, :not_found}`.
2. Now is before `:valid_from` → `{:error, :not_yet_valid}`.
3. Now is after `:valid_until` → `{:error, :expired}`.
4. `order_total` is below `:min_order_total` → `{:error, :below_min_order}`.
5. Total successful uses already `>= :max_uses` → `{:error, :max_uses_exceeded}`.
6. This user's successful uses already `>= :max_uses_per_user` →
   `{:error, :max_uses_per_user_exceeded}`.

"Now" is obtained by calling the injected `:clock`. Boundaries are inclusive:
`now == valid_from` is valid (not yet-valid), `now == valid_until` is valid (not
expired), and `order_total == min_order_total` passes the minimum check.

### Usage accounting

Only a **successful** application consumes a use. A call that returns
`{:error, _}` (e.g. below minimum order) must not increment any usage counter.
On success, increment the total use count and, when a `:user_id` is given, that
user's per-user count.

## Constraints

Give me the complete module in a single file (`solution.ex`). Use only the OTP
standard library — no external dependencies.

## Module under test

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
