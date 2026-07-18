  defp do_member?(nil, _target), do: false

  defp do_member?(%{interval: iv, left: l, right: r}, target) do
    cond do
      target == iv -> true
      target < iv -> do_member?(l, target)
      true -> do_member?(r, target)
    end
  end