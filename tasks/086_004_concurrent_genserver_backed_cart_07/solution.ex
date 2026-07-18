  @impl true
  def init(tax_rate) do
    {:ok, %{tax_rate: tax_rate, items: %{}}}
  end