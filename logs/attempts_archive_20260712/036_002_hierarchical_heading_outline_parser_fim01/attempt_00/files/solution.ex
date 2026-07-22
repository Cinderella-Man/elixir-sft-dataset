  # Close (and attach) every open node whose level is >= the incoming level.
  defp close_until(level, roots, [%{level: tl} = top | rest]) when tl >= level do
    {roots, rest} = attach(top, roots, rest)
    close_until(level, roots, rest)
  end

  defp close_until(_level, roots, stack), do: {roots, stack}