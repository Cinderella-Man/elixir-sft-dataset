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
defmodule Money do
  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  def new(cents, currency) when is_integer(cents) and is_atom(currency) do
    %__MODULE__{amount: cents, currency: currency}
  end

  def new(_cents, _currency) do
    raise ArgumentError, "cents must be an integer and currency must be an atom"
  end

  def add(%__MODULE__{amount: a, currency: cur}, %__MODULE__{amount: b, currency: cur}) do
    %__MODULE__{amount: a + b, currency: cur}
  end

  def add(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError, "cannot add different currencies: #{inspect(c1)} and #{inspect(c2)}"
  end

  def subtract(%__MODULE__{amount: a, currency: cur}, %__MODULE__{amount: b, currency: cur}) do
    %__MODULE__{amount: a - b, currency: cur}
  end

  def subtract(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError, "cannot subtract different currencies: #{inspect(c1)} and #{inspect(c2)}"
  end

  def multiply(%__MODULE__{amount: amount, currency: currency}, factor) when is_number(factor) do
    %__MODULE__{amount: round(amount * factor), currency: currency}
  end

  def multiply(%__MODULE__{}, _factor) do
    raise ArgumentError, "factor must be a number"
  end

  def allocate(%__MODULE__{amount: amount, currency: currency}, ratios)
      when is_list(ratios) and ratios != [] do
    unless Enum.all?(ratios, &(is_integer(&1) and &1 >= 0)) do
      raise ArgumentError, "ratios must be non-negative integers"
    end

    total = Enum.sum(ratios)

    if total <= 0 do
      raise ArgumentError, "ratios must sum to a strictly positive value"
    end

    shares = Enum.map(ratios, fn r -> div(amount * r, total) end)
    remainder = amount - Enum.sum(shares)
    unit = if remainder >= 0, do: 1, else: -1
    count = abs(remainder)

    shares
    |> Enum.with_index()
    |> Enum.map(fn {share, i} ->
      cents = if i < count, do: share + unit, else: share
      %__MODULE__{amount: cents, currency: currency}
    end)
  end

  def allocate(%__MODULE__{}, _ratios) do
    raise ArgumentError, "ratios must be a non-empty list of non-negative integers"
  end

  def split(%__MODULE__{} = money, n) when is_integer(n) and n > 0 do
    allocate(money, List.duplicate(1, n))
  end

  def split(%__MODULE__{}, _n) do
    raise ArgumentError, "n must be a positive integer"
  end
end
```
