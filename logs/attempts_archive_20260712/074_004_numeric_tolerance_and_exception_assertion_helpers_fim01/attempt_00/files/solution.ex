  defmacro assert_raises_message(exception, needle, fun) do
    quote bind_quoted: [exception: exception, needle: needle, fun: fun] do
      result =
        try do
          fun.()
          {:no_raise, nil}
        rescue
          e -> {:raised, e}
        end

      case result do
        {:no_raise, _} ->
          ExUnit.Assertions.flunk("""
          assert_raises_message failed

            expected #{inspect(exception)} to be raised
            but no exception was raised
          """)

        {:raised, e} ->
          cond do
            not is_struct(e, exception) ->
              ExUnit.Assertions.flunk("""
              assert_raises_message failed

                expected exception: #{inspect(exception)}
                actual exception  : #{inspect(e.__struct__)}
                message           : #{inspect(Exception.message(e))}
              """)

            not (Exception.message(e) =~ needle) ->
              ExUnit.Assertions.flunk("""
              assert_raises_message failed

                exception #{inspect(exception)} was raised as expected
                but its message did not contain the expected text
                expected substring: #{inspect(needle)}
                actual message    : #{inspect(Exception.message(e))}
              """)

            true ->
              :ok
          end
      end
    end
  end