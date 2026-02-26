defmodule Babysitter.Workflow.ValidatorTest do
  use ExUnit.Case, async: true

  alias Babysitter.Workflow.{Parser, Validator}

  describe "validate/1 with valid workflow" do
    test "returns {:ok, workflow} for valid workflow" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          on_success: s2
        - id: s2
      """

      {:ok, workflow} = Parser.parse_string(yaml)
      assert {:ok, validated} = Validator.validate(workflow)
      assert validated.id == workflow.id
      assert validated.stages == workflow.stages
      assert Map.has_key?(validated, :warnings)
    end

    test "validates workflow with all valid stage references" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: planning
          on_success: implementation
        - id: implementation
          on_success: review
          on_failure: retry
        - id: review
          on_success: complete
        - id: retry
          on_success: implementation
        - id: complete
      """

      {:ok, workflow} = Parser.parse_string(yaml)
      assert {:ok, _} = Validator.validate(workflow)
    end
  end

  describe "AC1: validate stage references" do
    test "returns error when on_success references non-existent stage" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          on_success: nonexistent
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:error, errors} = Validator.validate(workflow)
      assert Enum.any?(errors, &(&1.type == :invalid_reference))
    end

    test "returns error when on_failure references non-existent stage" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          on_failure: missing_handler
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:error, errors} = Validator.validate(workflow)
      assert Enum.any?(errors, &(&1.type == :invalid_reference))
    end

    test "returns error when on_timeout references non-existent stage" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          on_timeout: missing_timeout_handler
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:error, errors} = Validator.validate(workflow)
      assert Enum.any?(errors, &(&1.type == :invalid_reference))
    end

    test "returns error when entry_point references non-existent stage" do
      yaml = """
      id: test
      name: Test
      entry_point: nonexistent
      stages:
        - id: s1
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:error, errors} = Validator.validate(workflow)
      assert Enum.any?(errors, &(&1.type == :invalid_reference))
      assert Enum.any?(errors, &(&1.field == :entry_point))
    end

    test "error includes stage context for invalid references" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          on_success: missing
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:error, [error | _]} = Validator.validate(workflow)
      assert error.stage_id == :s1
      assert error.field == :on_success
      assert error.message =~ "missing"
    end

    test "allows nil on_success/on_failure/on_timeout (terminal stage)" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          on_success: s2
        - id: s2
      """

      {:ok, workflow} = Parser.parse_string(yaml)
      assert {:ok, _} = Validator.validate(workflow)
    end
  end

  describe "AC2: validate required fields" do
    test "returns error when workflow is missing id" do
      workflow = %{
        name: "Test",
        stages: %{},
        stage_order: []
      }

      assert {:error, errors} = Validator.validate(workflow)
      assert Enum.any?(errors, &(&1.type == :missing_field and &1.field == :id))
    end

    test "returns error when workflow is missing name" do
      workflow = %{
        id: "test",
        stages: %{},
        stage_order: []
      }

      assert {:error, errors} = Validator.validate(workflow)
      assert Enum.any?(errors, &(&1.type == :missing_field and &1.field == :name))
    end

    test "returns error when workflow is missing stages" do
      workflow = %{
        id: "test",
        name: "Test"
      }

      assert {:error, errors} = Validator.validate(workflow)
      assert Enum.any?(errors, &(&1.type == :missing_field and &1.field == :stages))
    end

    test "returns error when stages is empty" do
      workflow = %{
        id: "test",
        name: "Test",
        stages: %{},
        stage_order: []
      }

      assert {:error, errors} = Validator.validate(workflow)
      assert Enum.any?(errors, &(&1.type == :missing_field and &1.field == :stages))
    end

    test "collects all missing fields in one error list" do
      workflow = %{}

      assert {:error, errors} = Validator.validate(workflow)
      assert length(errors) >= 3

      fields = Enum.map(errors, & &1.field)
      assert :id in fields
      assert :name in fields
      assert :stages in fields
    end
  end

  describe "AC3: validate intelligence level" do
    test "accepts :dumb intelligence" do
      yaml = """
      id: test
      name: Test
      intelligence: dumb
      stages:
        - id: s1
      """

      {:ok, workflow} = Parser.parse_string(yaml)
      assert {:ok, _} = Validator.validate(workflow)
    end

    test "accepts :smart intelligence" do
      yaml = """
      id: test
      name: Test
      intelligence: smart
      stages:
        - id: s1
      """

      {:ok, workflow} = Parser.parse_string(yaml)
      assert {:ok, _} = Validator.validate(workflow)
    end

    test "accepts :hybrid intelligence" do
      yaml = """
      id: test
      name: Test
      intelligence: hybrid
      stages:
        - id: s1
      """

      {:ok, workflow} = Parser.parse_string(yaml)
      assert {:ok, _} = Validator.validate(workflow)
    end

    test "returns error for invalid intelligence level" do
      workflow = %{
        id: "test",
        name: "Test",
        intelligence: :invalid_level,
        stages: %{s1: %{id: "s1", type: :agent}},
        stage_order: [:s1]
      }

      assert {:error, errors} = Validator.validate(workflow)
      assert Enum.any?(errors, &(&1.type == :invalid_value and &1.field == :intelligence))
    end

    test "error message includes valid options" do
      workflow = %{
        id: "test",
        name: "Test",
        intelligence: :unknown,
        stages: %{s1: %{id: "s1", type: :agent}},
        stage_order: [:s1]
      }

      assert {:error, [error | _]} = Validator.validate(workflow)
      assert error.message =~ "dumb"
      assert error.message =~ "smart"
      assert error.message =~ "hybrid"
    end

    test "accepts nil intelligence (defaults to hybrid)" do
      workflow = %{
        id: "test",
        name: "Test",
        intelligence: nil,
        stages: %{s1: %{id: "s1", type: :agent}},
        stage_order: [:s1]
      }

      assert {:ok, _} = Validator.validate(workflow)
    end
  end

  describe "AC4: detect circular references" do
    test "warns about simple cycle (A -> B -> A)" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: a
          on_success: b
        - id: b
          on_success: a
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:ok, workflow} = Validator.validate(workflow)
      assert Map.has_key?(workflow, :warnings)
      assert Enum.any?(workflow.warnings, &(&1.type == :circular_reference))
    end

    test "warns about longer cycle (A -> B -> C -> A)" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: a
          on_success: b
        - id: b
          on_success: c
        - id: c
          on_success: a
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:ok, workflow} = Validator.validate(workflow)
      assert Enum.any?(workflow.warnings, &(&1.type == :circular_reference))
    end

    test "allows self-referencing stage (retry pattern) with warning" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: retry
          on_success: retry
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:ok, workflow} = Validator.validate(workflow)
      assert Enum.any?(workflow.warnings, &(&1.type == :circular_reference))
    end

    test "warns about unreachable stages" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: start
          on_success: end
        - id: unreachable
        - id: end
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:ok, workflow} = Validator.validate(workflow)
      assert Enum.any?(workflow.warnings, &(&1.type == :unreachable_stage))
    end

    test "no warnings for linear workflow" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: a
          on_success: b
        - id: b
          on_success: c
        - id: c
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:ok, workflow} = Validator.validate(workflow)
      warnings = Map.get(workflow, :warnings, [])
      refute Enum.any?(warnings, &(&1.type == :circular_reference))
      refute Enum.any?(warnings, &(&1.type == :unreachable_stage))
    end

    test "no warnings for valid diamond pattern" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: start
          on_success: branch_a
        - id: branch_a
          on_success: merge
        - id: merge
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:ok, _} = Validator.validate(workflow)
    end
  end

  describe "multiple errors" do
    test "collects multiple errors before returning" do
      workflow = %{
        id: "test",
        name: "Test",
        intelligence: :invalid,
        stages: %{
          s1: %{id: "s1", type: :agent, on_success: :missing_stage},
          s2: %{id: "s2", type: :agent, on_failure: :also_missing}
        },
        stage_order: [:s1, :s2]
      }

      assert {:error, errors} = Validator.validate(workflow)
      ref_errors = Enum.filter(errors, &(&1.type == :invalid_reference))
      assert length(ref_errors) >= 2
    end
  end

  describe "ValidationError struct" do
    test "error has required fields" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          on_success: missing
      """

      {:ok, workflow} = Parser.parse_string(yaml)

      assert {:error, [error | _]} = Validator.validate(workflow)
      assert error.type != nil
      assert error.message != nil
    end
  end
end
