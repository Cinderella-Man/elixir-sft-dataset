  @spec order_table_name(name()) :: atom()
  defp order_table_name(name), do: :"#{name}_order"