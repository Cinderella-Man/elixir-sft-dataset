  defp do_delete(nil, _target), do: {nil, false}

  defp do_delete(%{interval: iv, left: l, right: r}, target) do
    cond do
      target < iv ->
        {nl, found} = do_delete(l, target)
        {balance(iv, nl, r), found}

      target > iv ->
        {nr, found} = do_delete(r, target)
        {balance(iv, l, nr), found}

      true ->
        {delete_here(l, r), true}
    end
  end