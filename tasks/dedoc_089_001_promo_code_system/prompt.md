# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule PromoCodes do
  use GenServer

  @valid_types [:percentage, :fixed_amount, :free_shipping]

  # ---------------------------------------------------------------------------
  # Process lifecycle
  # ---------------------------------------------------------------------------

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

  def create(attrs) when is_map(attrs) do
    GenServer.call(server(), {:create, attrs})
  end

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
