@doc """
Builds a struct for `factory_name`, merging `overrides` into the result.

Association fields stored as zero-arity thunks (`fn -> value end`) are
resolved *after* overrides are merged. Overriding `user_id:` on a `:post`
therefore suppresses the implicit `insert(:user)` call entirely.
"""
@spec build(atom(), Keyword.t()) :: struct()
def build(factory_name, overrides) do
  factory_name
  |> factory()
  |> merge_overrides(overrides)
  |> resolve_thunks()
end