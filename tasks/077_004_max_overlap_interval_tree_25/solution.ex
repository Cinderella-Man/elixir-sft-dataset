  @doc """
  Returns the smallest integer point achieving `max_overlap/1`, or `nil` when
  the tree is empty.
  """
  @spec busiest_point(t()) :: integer() | nil
  def busiest_point(nil), do: nil

  def busiest_point(tree) do
    {_run, _best, coord} =
      tree
      |> in_order([])
      |> Enum.reduce({0, @neg_inf, nil}, fn {c, d}, {run, best, coord} ->
        run2 = run + d

        if run2 > best do
          {run2, run2, c}
        else
          {run2, best, coord}
        end
      end)

    coord
  end