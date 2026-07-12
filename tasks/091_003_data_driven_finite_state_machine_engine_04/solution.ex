  defp normalize({event, from, to})
       when is_atom(event) and is_atom(from) and is_atom(to),
       do: {event, from, to, nil}

  defp normalize({event, from, to, guard})
       when is_atom(event) and is_atom(from) and is_atom(to) and is_function(guard, 1),
       do: {event, from, to, guard}

  defp normalize(other),
    do: raise(ArgumentError, "invalid transition spec: #{inspect(other)}")
