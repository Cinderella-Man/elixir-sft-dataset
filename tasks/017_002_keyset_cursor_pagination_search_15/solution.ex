  defp sorter(params) do
    ord = order(params)

    fn a, b ->
      compare_key(ord, key_of(a, params), key_of(b, params)) != :after
    end
  end