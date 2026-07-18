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

  @exponents %{USD: 2, EUR: 2, GBP: 2, JPY: 0, KWD: 3, BHD: 3}

  def exponent(currency) do
    case Map.fetch(@exponents, currency) do
      {:ok, exp} -> exp
      :error -> raise ArgumentError, "unsupported currency: #{inspect(currency)}"
    end
  end

  def new(minor_units, currency) when is_integer(minor_units) and is_atom(currency) do
    _ = exponent(currency)
    %__MODULE__{amount: minor_units, currency: currency}
  end

  def new(_minor_units, _currency) do
    raise ArgumentError, "minor_units must be an integer and currency must be a supported atom"
  end

  def from_major(major, currency) when is_number(major) and is_atom(currency) do
    exp = exponent(currency)
    %__MODULE__{amount: round(major * Integer.pow(10, exp)), currency: currency}
  end

  def from_major(_major, _currency) do
    raise ArgumentError, "major must be a number and currency must be a supported atom"
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

  def split(%__MODULE__{amount: amount, currency: currency}, n)
      when is_integer(n) and n > 0 do
    base = Integer.floor_div(amount, n)
    remainder = Integer.mod(amount, n)

    Enum.map(0..(n - 1), fn i ->
      cents = if i < remainder, do: base + 1, else: base
      %__MODULE__{amount: cents, currency: currency}
    end)
  end

  def split(%__MODULE__{}, _n) do
    raise ArgumentError, "n must be a positive integer"
  end

  def to_string(%__MODULE__{amount: amount, currency: currency}) do
    exp = exponent(currency)
    sign = if amount < 0, do: "-", else: ""
    abs_amount = abs(amount)

    if exp == 0 do
      "#{sign}#{abs_amount} #{currency}"
    else
      divisor = Integer.pow(10, exp)
      major = div(abs_amount, divisor)
      minor = rem(abs_amount, divisor)
      minor_str = minor |> Integer.to_string() |> String.pad_leading(exp, "0")
      "#{sign}#{major}.#{minor_str} #{currency}"
    end
  end
end
```
