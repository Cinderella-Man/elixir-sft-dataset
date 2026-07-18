  @doc "Adds two money values of the same currency (never auto-converts)."
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{amount: a, currency: cur}, %__MODULE__{amount: b, currency: cur}) do
    %__MODULE__{amount: a + b, currency: cur}
  end

  def add(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError,
          "cannot add different currencies: #{inspect(c1)} and #{inspect(c2)}; use convert/3"
  end