defmodule PasswordPolicyTest do
  def run do
    results = [
      # --- Single-rule failures ---
      test("too short",
        PasswordPolicy.validate("Ab1!", %{username: "user", min_length: 8}),
        {:error, [:too_short]}
      ),
      test("too long",
        PasswordPolicy.validate("Ab1!" <> String.duplicate("x", 200), %{username: "user", max_length: 20}),
        {:error, [:too_long]}
      ),
      test("no uppercase",
        PasswordPolicy.validate("abc123!!", %{username: "user", require_uppercase: true}),
        {:error, [:no_uppercase]}
      ),
      test("no lowercase",
        PasswordPolicy.validate("ABC123!!", %{username: "user", require_lowercase: true}),
        {:error, [:no_lowercase]}
      ),
      test("no digit",
        PasswordPolicy.validate("Abcdefg!", %{username: "user", require_digit: true}),
        {:error, [:no_digit]}
      ),
      test("no special character",
        PasswordPolicy.validate("Abcdef12", %{username: "user", require_special: true}),
        {:error, [:no_special]}
      ),
      test("common password",
        PasswordPolicy.validate("Password1!", %{
          username: "user",
          common_passwords: ["password1!", "letmein"]
        }),
        {:error, [:common_password]}
      ),
      test("common password is case-insensitive",
        PasswordPolicy.validate("PASSWORD1!", %{
          username: "user",
          common_passwords: ["password1!"]
        }),
        {:error, [:common_password]}
      ),
      test("reused password",
        PasswordPolicy.validate("Correct1!", %{
          username: "user",
          previous_passwords: ["OldPass9#", "Correct1!"]
        }),
        {:error, [:reused_password]}
      ),
      test("too similar to username - distance <= threshold",
        PasswordPolicy.validate("user1234!", %{
          username: "user",
          require_uppercase: false,
          max_username_similarity: 3
        }),
        {:error, [:too_similar_to_username]}
      ),

      # --- Multiple simultaneous failures ---
      test("multiple violations: too short + no uppercase + no digit",
        fn ->
          {:error, violations} =
            PasswordPolicy.validate("abc!", %{
              username: "other",
              min_length: 8,
              require_uppercase: true,
              require_digit: true,
              require_lowercase: true,
              require_special: true
            })
          expected = MapSet.new([:too_short, :no_uppercase, :no_digit])
          got = MapSet.new(violations)
          if MapSet.subset?(expected, got),
            do: :ok,
            else: {:error, "expected violations #{inspect(MapSet.to_list(expected))} in #{inspect(MapSet.to_list(got))}"}
        end
      ),
      test("multiple violations: common + reused",
        fn ->
          {:error, violations} =
            PasswordPolicy.validate("Letmein1!", %{
              username: "other",
              require_uppercase: false,
              require_digit: false,
              require_special: false,
              require_lowercase: false,
              common_passwords: ["letmein1!"],
              previous_passwords: ["Letmein1!"]
            })
          expected = MapSet.new([:common_password, :reused_password])
          got = MapSet.new(violations)
          if MapSet.equal?(expected, got),
            do: :ok,
            else: {:error, "expected #{inspect(MapSet.to_list(expected))}, got #{inspect(MapSet.to_list(got))}"}
        end
      ),

      # --- Passing cases ---
      test("valid password - all rules pass",
        PasswordPolicy.validate("Tr0ub4dor&3", %{
          username: "alice",
          min_length: 8,
          max_length: 64,
          require_uppercase: true,
          require_lowercase: true,
          require_digit: true,
          require_special: true,
          common_passwords: ["password123"],
          previous_passwords: ["OldPass1!"]
        }),
        :ok
      ),
      test("valid password - username similarity just outside threshold",
        PasswordPolicy.validate("userXYZW1!", %{
          username: "user",
          require_uppercase: true,
          require_lowercase: false,
          max_username_similarity: 3
        }),
        :ok
      ),
      test("valid with no optional rules enabled",
        PasswordPolicy.validate("anything",  %{
          username: "bob",
          min_length: 1,
          require_uppercase: false,
          require_lowercase: false,
          require_digit: false,
          require_special: false
        }),
        :ok
      ),

      # --- Levenshtein edge cases ---
      test("password identical to username is rejected",
        PasswordPolicy.validate("carol", %{
          username: "carol",
          require_uppercase: false,
          require_lowercase: false,
          require_digit: false,
          require_special: false,
          max_username_similarity: 3
        }),
        {:error, [:too_similar_to_username]}
      ),
      test("password far from username is accepted",
        PasswordPolicy.validate("Zx9#mQpL", %{
          username: "alice",
          max_username_similarity: 3
        }),
        :ok
      ),
    ]

    passed = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 != :ok))
    IO.puts("\n=== Results: #{passed} passed, #{failed} failed ===")
    if failed > 0, do: System.halt(1)
  end

  defp test(name, result_or_fn, expected) do
    actual =
      if is_function(result_or_fn, 0) do
        try do
          result_or_fn.()
        rescue
          e -> {:error, "exception: #{Exception.message(e)}"}
        end
      else
        result_or_fn
      end

    if actual == expected do
      IO.puts("  ✓ #{name}")
      :ok
    else
      IO.puts("  ✗ #{name}")
      IO.puts("      expected: #{inspect(expected)}")
      IO.puts("      got:      #{inspect(actual)}")
      :fail
    end
  end

  # Overload for lambda-based tests (already return :ok / {:error, msg})
  defp test(name, fun) when is_function(fun, 0) do
    result =
      try do
        fun.()
      rescue
        e -> {:error, "exception: #{Exception.message(e)}"}
      end

    case result do
      :ok ->
        IO.puts("  ✓ #{name}")
        :ok
      {:error, msg} ->
        IO.puts("  ✗ #{name}: #{msg}")
        :fail
    end
  end
end
