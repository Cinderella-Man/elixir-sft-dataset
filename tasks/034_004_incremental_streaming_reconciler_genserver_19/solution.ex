  @spec pending_field(:left | :right) :: :pending_left | :pending_right
  defp pending_field(:left), do: :pending_left
  defp pending_field(:right), do: :pending_right