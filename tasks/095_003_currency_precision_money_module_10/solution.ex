  @doc """
  Creates a money struct from an integer number of minor units.

  Raises `ArgumentError` if `minor_units` is not an integer or `currency` is
  not supported.
  """
  @spec new(integer(), atom()) :: t()
  def new(minor_units, currency) when is_integer(minor_units) and is_atom(currency) do
    _ = exponent(currency)
    %__MODULE__{amount: minor_units, currency: currency}
  end

  def new(_minor_units, _currency) do
    raise ArgumentError, "minor_units must be an integer and currency must be a supported atom"
  end