defmodule Babysitter.ValidationTest do
  use ExUnit.Case, async: true

  alias Babysitter.Validation

  describe "output_contains/2" do
    test "passes when output contains pattern" do
      validation = Validation.output_contains("success")
      assert :ok = Validation.run(validation, "The operation was a success", 0)
    end

    test "fails when output does not contain pattern" do
      validation = Validation.output_contains("success")
      assert {:error, _} = Validation.run(validation, "The operation failed", 1)
    end

    test "negate inverts the result" do
      validation = Validation.output_contains("error", negate: true)
      assert :ok = Validation.run(validation, "All good", 0)
    end
  end

  describe "output_matches/2" do
    test "passes when output matches regex" do
      validation = Validation.output_matches(~r/\d+ items/)
      assert :ok = Validation.run(validation, "Processed 42 items", 0)
    end

    test "accepts string pattern" do
      validation = Validation.output_matches("pass(ed)?")
      assert :ok = Validation.run(validation, "All tests passed", 0)
    end
  end

  describe "exit_code/2" do
    test "passes when exit code matches" do
      validation = Validation.exit_code(0)
      assert :ok = Validation.run(validation, "output", 0)
    end

    test "accepts list of valid codes" do
      validation = Validation.exit_code([0, 1])
      assert :ok = Validation.run(validation, "output", 1)
    end

    test "fails for non-matching exit code" do
      validation = Validation.exit_code(0)
      assert {:error, _} = Validation.run(validation, "output", 1)
    end
  end

  describe "output_equals/2" do
    test "passes when output equals expected" do
      validation = Validation.output_equals("ok")
      assert :ok = Validation.run(validation, "ok", 0)
    end

    test "fails when output differs" do
      validation = Validation.output_equals("ok")
      assert {:error, _} = Validation.run(validation, "OK", 0)
    end
  end

  describe "custom validation" do
    test "runs custom function" do
      validation =
        Validation.__struct__(
          type: :custom,
          pattern: fn output, _exit -> {:ok, output} |> elem(0) end
        )

      assert :ok = Validation.run(validation, "any", 0)
    end
  end
end
