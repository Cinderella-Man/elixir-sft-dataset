  @doc """
  Asserts that every element of `subset` also appears in `superset`.

  Membership is set-based, so duplicate elements in `subset` are fine. On
  failure the message lists the missing elements and shows both collections.
  """
  @spec assert_subset(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_subset(subset, superset) do
    quote bind_quoted: [subset: subset, superset: superset] do
      sub_list = Enum.to_list(subset)
      sup_list = Enum.to_list(superset)
      sup_set = MapSet.new(sup_list)

      missing =
        sub_list
        |> Enum.reject(fn el -> MapSet.member?(sup_set, el) end)
        |> Enum.uniq()

      unless missing == [] do
        ExUnit.Assertions.flunk("""
        assert_subset failed

          expected every element of the subset to appear in the superset
          missing elements: #{inspect(missing)}
          subset          : #{inspect(sub_list)}
          superset        : #{inspect(sup_list)}
        """)
      end
    end
  end