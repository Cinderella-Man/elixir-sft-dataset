defp stack_build(0, _size, acc), do: SD.constant(Enum.reverse(acc))

defp stack_build(n, size, acc) do
  SD.bind(stack_command(size), fn cmd ->
    stack_build(n - 1, stack_apply(size, cmd), [cmd | acc])
  end)
end