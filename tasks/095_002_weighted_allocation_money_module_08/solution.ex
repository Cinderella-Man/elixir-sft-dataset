  @doc """
  Creates a money struct from an integer number of `cents` and a currency atom.

  Raises `ArgumentError` if `cents` is not an integer or `currency` is not an atom.
  """
  @spec new(integer(), atom()) :: t()
  def new(cents, currency) when is_integer(cents) and is_atom(currency) do
    %__MODULE__{amount: cents, currency: currency}
  end

  def new(_cents, _currency) do
    raise ArgumentError, "cents must be an integer and currency must be an atom"
  end