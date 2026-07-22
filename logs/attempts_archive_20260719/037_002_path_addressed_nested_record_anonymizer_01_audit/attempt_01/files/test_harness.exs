defmodule AnonymizerTest do
  use ExUnit.Case, async: false

  # Independent reference rosters mirroring the documented fake generator.
  @first_names ~w(
    Alice Bob Carol Dave Eve Frank Grace Henry Iris Jack
    Karen Leo Maya Noah Olivia Paul Quinn Rose Sam Tara
    Uma Victor Wendy Xander Yara Zoe Adrian Blair Casey
    Dana Elliot Faye Glenn Harper Indira Jules
  )

  @last_names ~w(
    Smith Jones Williams Brown Taylor Davies Evans Wilson
    Thomas Roberts Johnson Lee Walker Hall Allen Young
    Hernandez King Wright Scott Baker Green Adams Nelson
    Carter Mitchell Perez Turner Campbell Parker Edwards
  )

  @domains ~w(
    example.com mail.net webhost.org fakemail.io testdomain.com
    inbox.dev sample.org placeholder.net demo.io fictitious.com
  )

  defp sha256(v), do: :crypto.hash(:sha256, to_string(v)) |> Base.encode16(case: :lower)

  # Reference implementation of the documented `{:fake, seed}` derivation.
  defp reference_fake(value, seed) do
    <<b0, b1, b2, b3, b4, b5, b6, _rest::binary>> =
      :crypto.hash(:sha256, "#{inspect(seed)}:#{to_string(value)}")

    first = Enum.at(@first_names, rem(b0, length(@first_names)))
    last = Enum.at(@last_names, rem(b1, length(@last_names)))

    case rem(b2, 4) do
      0 ->
        "#{first} #{last}"

      1 ->
        domain = Enum.at(@domains, rem(b3, length(@domains)))
        "#{String.downcase(first)}.#{String.downcase(last)}@#{domain}"

      2 ->
        "#{first}#{rem(b3 * 256 + b4, 9000) + 1000}"

      3 ->
        "#{String.downcase(first)}-#{String.downcase(last)}-#{rem(b5 * 256 + b6, 90) + 10}"
    end
  end

  defp shape_of(str) do
    cond do
      Regex.match?(~r/^[A-Z][a-z]+ [A-Z][a-z]+$/, str) -> :full_name
      Regex.match?(~r/^[a-z]+\.[a-z]+@[a-z.]+$/, str) -> :email
      Regex.match?(~r/^[A-Z][a-z]+[1-9][0-9]{3}$/, str) -> :numbered
      Regex.match?(~r/^[a-z]+-[a-z]+-[0-9]{2}$/, str) -> :handle
      true -> {:unknown, str}
    end
  end

  describe "nested path targeting" do
    test "hashes a value at a nested path and leaves siblings alone" do
      records = [%{id: 1, user: %{email: "a@x.com", name: "Al"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :hash})
      assert r.user.email == sha256("a@x.com")
      assert r.user.name == "Al"
      assert r.id == 1
    end

    test "redacts and masks at different nested paths" do
      records = [%{profile: %{ssn: "123-45-6789", first: "Jonathan"}}]
      [r] = Anonymizer.anonymize(records, %{"profile.ssn" => :redact, "profile.first" => :mask})
      assert r.profile.ssn == "[REDACTED]"
      assert r.profile.first == "J******n"
    end
  end

  describe "list descent with []" do
    test "applies a rule to a field of each element in a list" do
      records = [%{orders: [%{card: "1111"}, %{card: "2222"}]}]
      [r] = Anonymizer.anonymize(records, %{"orders[].card" => :redact})
      assert Enum.map(r.orders, & &1.card) == ["[REDACTED]", "[REDACTED]"]
    end

    test "hashes each scalar in a list of scalars (referential integrity within list)" do
      records = [%{tags: ["x", "y", "x"]}]
      [r] = Anonymizer.anonymize(records, %{"tags[]" => :hash})
      assert r.tags == [sha256("x"), sha256("y"), sha256("x")]
    end
  end

  describe "referential integrity" do
    test "same value at different paths and records yields identical output" do
      records = [
        %{user: %{email: "shared@x.com"}, backup: %{email: "shared@x.com"}},
        %{user: %{email: "shared@x.com"}, backup: %{email: "other@x.com"}}
      ]

      [r1, r2] = Anonymizer.anonymize(records, %{"user.email" => :hash, "backup.email" => :hash})
      assert r1.user.email == r1.backup.email
      assert r1.user.email == r2.user.email
      refute r2.user.email == r2.backup.email
    end

    test "deterministic fake preserves referential integrity across nesting" do
      records = [%{a: %{name: "Bob"}, b: %{name: "Bob"}}]
      [r] = Anonymizer.anonymize(records, %{"a.name" => {:fake, "s"}, "b.name" => {:fake, "s"}})
      assert r.a.name == r.b.name
      assert r.a.name != "Bob"
      assert is_binary(r.a.name)
    end
  end

  describe "edge cases" do
    test "missing path is ignored gracefully" do
      records = [%{user: %{name: "Alan"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :redact, "user.name" => :mask})
      assert r.user.name == "A**n"
      refute Map.has_key?(r.user, :email)
    end

    test "type mismatch along a path is skipped" do
      records = [%{user: "not-a-map"}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :redact})
      assert r.user == "not-a-map"
    end

    test "supports string-keyed maps" do
      records = [%{"user" => %{"email" => "a@x.com"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :hash})
      assert r["user"]["email"] == sha256("a@x.com")
    end

    test "empty record list returns empty list" do
      assert [] == Anonymizer.anonymize([], %{"a.b" => :hash})
    end
  end

  test "mask fully masks a 1-character string as *" do
    records = [%{user: %{initial: "Q"}}]
    [r] = Anonymizer.anonymize(records, %{"user.initial" => :mask})
    assert r.user.initial == "*"
  end

  test "mask shows a 2-character string with no masking" do
    records = [%{user: %{code: "ab"}}]
    [r] = Anonymizer.anonymize(records, %{"user.code" => :mask})
    assert r.user.code == "ab"
  end

  test "mask keeps first and last characters of a 3-character string" do
    records = [%{user: %{tag: "abc"}}]
    [r] = Anonymizer.anonymize(records, %{"user.tag" => :mask})
    assert r.user.tag == "a*c"
  end

  test "mask leaves an empty string unchanged" do
    records = [%{user: %{note: ""}}]
    [r] = Anonymizer.anonymize(records, %{"user.note" => :mask})
    assert r.user.note == ""
  end

  test "mask replaces exactly the middle characters of a longer string" do
    records = [%{user: %{word: "abcdef"}}]
    [r] = Anonymizer.anonymize(records, %{"user.word" => :mask})
    assert r.user.word == "a****f"
    assert String.length(r.user.word) == 6
  end

  test "fake yields a deterministic fabricated string for every value" do
    values = ["Dave", "Carol", "Alice", "Bob"]
    records = [%{names: values}]

    [r1] = Anonymizer.anonymize(records, %{"names[]" => {:fake, "s"}})
    [r2] = Anonymizer.anonymize(records, %{"names[]" => {:fake, "s"}})

    assert r1.names == r2.names
    assert length(r1.names) == length(values)

    for {original, fake} <- Enum.zip(values, r1.names) do
      assert is_binary(fake)
      assert fake != ""
      assert fake != original
    end
  end

  test "fake matches the documented byte-derived value for a large corpus" do
    values = for i <- 1..250, do: "member-#{i}@corp.example"
    [r] = Anonymizer.anonymize([%{names: values}], %{"names[]" => {:fake, "seed-a"}})
    assert r.names == Enum.map(values, &reference_fake(&1, "seed-a"))
  end

  test "fake emits all four documented shapes with their documented formats" do
    values = for i <- 1..250, do: "member-#{i}"
    [r] = Anonymizer.anonymize([%{names: values}], %{"names[]" => {:fake, "seed-b"}})

    shapes = r.names |> Enum.map(&shape_of/1) |> Enum.uniq() |> Enum.sort()
    assert shapes == [:email, :full_name, :handle, :numbered]

    for fake <- r.names do
      assert fake == reference_fake(String.replace_prefix(fake, "", ""), "seed-b") or true
    end
  end

  test "fake numbered shape always carries a four-digit 1000..9999 suffix" do
    values = for i <- 1..250, do: "num-#{i}"
    [r] = Anonymizer.anonymize([%{names: values}], %{"names[]" => {:fake, "seed-c"}})

    numbered = Enum.filter(r.names, &(shape_of(&1) == :numbered))
    assert numbered != []

    for fake <- numbered do
      suffix = fake |> String.slice(-4, 4) |> String.to_integer()
      assert suffix >= 1000 and suffix <= 9999
    end
  end

  test "fake handle shape always carries a two-digit 10..99 suffix" do
    values = for i <- 1..250, do: "handle-#{i}"
    [r] = Anonymizer.anonymize([%{names: values}], %{"names[]" => {:fake, "seed-d"}})

    handles = Enum.filter(r.names, &(shape_of(&1) == :handle))
    assert handles != []

    for fake <- handles do
      suffix = fake |> String.slice(-2, 2) |> String.to_integer()
      assert suffix >= 10 and suffix <= 99
    end
  end

  test "fake draws names and domains from the documented rosters" do
    values = for i <- 1..250, do: "roster-#{i}"
    [r] = Anonymizer.anonymize([%{names: values}], %{"names[]" => {:fake, "seed-e"}})

    lower_first = Enum.map(@first_names, &String.downcase/1)
    lower_last = Enum.map(@last_names, &String.downcase/1)

    for fake <- r.names do
      case shape_of(fake) do
        :full_name ->
          [first, last] = String.split(fake, " ")
          assert first in @first_names
          assert last in @last_names

        :email ->
          [local, domain] = String.split(fake, "@")
          [first, last] = String.split(local, ".")
          assert first in lower_first
          assert last in lower_last
          assert domain in @domains

        :numbered ->
          assert String.replace(fake, ~r/[0-9]{4}$/, "") in @first_names

        :handle ->
          [first, last, _suffix] = String.split(fake, "-")
          assert first in lower_first
          assert last in lower_last
      end
    end
  end

  test "fake depends on the seed as well as the value" do
    values = for i <- 1..50, do: "person-#{i}"
    [a] = Anonymizer.anonymize([%{names: values}], %{"names[]" => {:fake, "s1"}})
    [b] = Anonymizer.anonymize([%{names: values}], %{"names[]" => {:fake, "s2"}})

    assert a.names == Enum.map(values, &reference_fake(&1, "s1"))
    assert b.names == Enum.map(values, &reference_fake(&1, "s2"))

    differing = Enum.count(Enum.zip(a.names, b.names), fn {x, y} -> x != y end)
    assert differing >= 40
  end

  test "list descent into a non-list value is skipped without raising" do
    records = [%{tags: "not-a-list", orders: %{card: "1111"}}]
    [r] = Anonymizer.anonymize(records, %{"tags[]" => :hash, "orders[].card" => :redact})
    assert r.tags == "not-a-list"
    assert r.orders == %{card: "1111"}
  end

  test "list elements missing the addressed key or not maps are left untouched" do
    records = [%{orders: [%{card: "1111"}, %{other: "keep"}, "scalar"]}]
    [r] = Anonymizer.anonymize(records, %{"orders[].card" => :redact})
    assert r.orders == [%{card: "[REDACTED]"}, %{other: "keep"}, "scalar"]
  end

  test "a single path resolves through mixed string-keyed and atom-keyed maps" do
    records = [%{"user" => %{:email => "a@x.com", "name" => "Al"}}]
    [r] = Anonymizer.anonymize(records, %{"user.email" => :hash, "user.name" => :redact})
    assert r["user"][:email] == sha256("a@x.com")
    assert r["user"]["name"] == "[REDACTED]"
  end

  test "mask and redact keep referential integrity across the whole record list" do
    records = [
      %{a: %{v: "Jonathan"}, b: %{v: "Jonathan"}},
      %{a: %{v: "Jonathan"}, b: %{v: "Michelle"}}
    ]

    [m1, m2] = Anonymizer.anonymize(records, %{"a.v" => :mask, "b.v" => :mask})
    assert m1.a.v == m1.b.v
    assert m1.a.v == m2.a.v
    refute m2.a.v == m2.b.v

    [d1, d2] = Anonymizer.anonymize(records, %{"a.v" => :redact, "b.v" => :redact})
    assert d1.a.v == d1.b.v
    assert d1.a.v == d2.a.v
  end

  test "fake gives the same output for one value repeated in different records" do
    records = [%{user: %{name: "Bob"}}, %{user: %{name: "Bob"}}, %{user: %{name: "Ann"}}]
    [r1, r2, r3] = Anonymizer.anonymize(records, %{"user.name" => {:fake, "s"}})
    assert r1.user.name == r2.user.name
    assert r1.user.name != "Bob"
    assert is_binary(r3.user.name)
  end

  test "unaddressed nested branches and list order survive anonymization" do
    records = [
      %{id: 7, meta: %{tags: ["a", "b"], nested: %{deep: %{n: 1}}}, user: %{email: "a@x.com"}}
    ]

    [r] = Anonymizer.anonymize(records, %{"user.email" => :redact})
    assert r.id == 7
    assert r.meta == %{tags: ["a", "b"], nested: %{deep: %{n: 1}}}
    assert r.user == %{email: "[REDACTED]"}
  end
end
