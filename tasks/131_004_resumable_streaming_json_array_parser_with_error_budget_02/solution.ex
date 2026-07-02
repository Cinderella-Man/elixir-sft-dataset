  defp step(_line, %{index: index} = acc, _handler_fn, resume_from, _max_errors)
       when index <= resume_from do
    {:cont, acc}
  end

  defp step(line, acc, handler_fn, _resume_from, max_errors) do
    case decode_line(line) do
      {:ok, item} ->
        handler_fn.(item)
        {:cont, %{acc | processed: acc.processed + 1}}

      {:error, _reason} ->
        errors = acc.errors + 1
        acc = %{acc | errors: errors}

        if exceeds?(errors, max_errors) do
          {:halt, %{acc | aborted: true}}
        else
          {:cont, acc}
        end
    end
  end