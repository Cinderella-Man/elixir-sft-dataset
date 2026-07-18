  @doc """
  Creates and returns a new, empty `%Cart{}`.

  ## Options

    * `:tax_rate` — a non-negative float representing the sales-tax rate,
      e.g. `0.08` for 8 %.  Defaults to `0.0`.

  ## Examples

      iex> Cart.new()
      %Cart{tax_rate: 0.0, items: %{}}

      iex> Cart.new(tax_rate: 0.07)
      %Cart{tax_rate: 0.07, items: %{}}
  """
  @spec new(keyword()) :: %Cart{}
  def new(opts \\ []) do
    tax_rate = Keyword.get(opts, :tax_rate, 0.0)
    %Cart{tax_rate: tax_rate, items: %{}}
  end