defmodule Babysitter.Workflow.ParserTest do
  use ExUnit.Case, async: true

  alias Babysitter.Workflow.Parser
  alias Babysitter.{Stage, Validation}

  describe "parse_string/1" do
    test "parses minimal workflow" do
      yaml = """
      id: test-workflow
      name: Test Workflow
      stages:
        - id: step1
          type: action
          command: echo hello
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)

      assert workflow.id == "test-workflow"
      assert workflow.name == "Test Workflow"
      assert workflow.intelligence == :hybrid
      assert Map.has_key?(workflow.stages, :step1)
    end

    test "parses workflow with description" do
      yaml = """
      id: my-workflow
      name: My Workflow
      description: A workflow for testing
      stages:
        - id: start
          type: action
          command: start
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.description == "A workflow for testing"
    end

    test "parses intelligence levels" do
      for intelligence <- ["dumb", "smart", "hybrid"] do
        yaml = """
        id: test
        name: Test
        intelligence: #{intelligence}
        stages:
          - id: s1
            type: action
            command: x
        """

        assert {:ok, workflow} = Parser.parse_string(yaml)
        assert workflow.intelligence == String.to_atom(intelligence)
      end
    end

    test "defaults intelligence to hybrid" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          type: action
          command: x
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.intelligence == :hybrid
    end

    test "returns error for missing id" do
      yaml = """
      name: Test
      stages:
        - id: s1
      """

      assert {:error, {:missing_required_field, :id}} = Parser.parse_string(yaml)
    end

    test "returns error for missing name" do
      yaml = """
      id: test
      stages:
        - id: s1
      """

      assert {:error, {:missing_required_field, :name}} = Parser.parse_string(yaml)
    end

    test "returns error for missing stages" do
      yaml = """
      id: test
      name: Test
      """

      assert {:error, {:missing_required_field, :stages}} = Parser.parse_string(yaml)
    end

    test "returns error for missing stage id" do
      yaml = """
      id: test
      name: Test
      stages:
        - type: action
          command: x
      """

      assert {:error, {:missing_stage_id, _}} = Parser.parse_string(yaml)
    end

    test "returns error for invalid stage type" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          type: invalid_type
      """

      assert {:error, {:invalid_stage_type, "invalid_type"}} = Parser.parse_string(yaml)
    end
  end

  describe "stage parsing" do
    test "parses action stage with command" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: run-tests
          type: action
          command: mix test
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      stage = workflow.stages[:"run-tests"]

      assert %Stage{} = stage
      assert stage.id == "run-tests"
      assert stage.type == :action
      assert stage.command == "mix test"
    end

    test "parses agent stage with prompt" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: implement
          type: agent
          prompt: |
            Implement this feature
            Multi-line prompt
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      stage = workflow.stages[:implement]

      assert stage.type == :agent
      assert stage.prompt =~ "Implement this feature"
    end

    test "parses agent stage with prompt_template alias" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: implement
          type: agent
          prompt_template: Template content
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      stage = workflow.stages[:implement]

      assert stage.prompt == "Template content"
    end


    test "parses stage with per-stage agent" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: custom
          type: agent
          agent: opencode
          prompt: Do something
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      stage = workflow.stages[:custom]

      assert stage.agent == :opencode
    end

    test "stage agent defaults to nil" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: noagent
          type: agent
          prompt: Do something
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      stage = workflow.stages[:noagent]

      assert stage.agent == nil
    end
    test "parses validation stage" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: validate
          type: validation
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      stage = workflow.stages[:validate]
      assert stage.type == :validation
    end

    test "parses decision stage" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: decide
          type: decision
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      stage = workflow.stages[:decide]
      assert stage.type == :decision
    end

    test "defaults stage type to agent" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          prompt: hello
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stages[:s1].type == :agent
    end
  end

  describe "timeout parsing" do
    test "parses timeout in seconds" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          timeout: 30s
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stages[:s1].timeout == 30_000
    end

    test "parses timeout in minutes" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          timeout: 5m
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stages[:s1].timeout == 300_000
    end

    test "parses timeout in hours" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          timeout: 2h
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stages[:s1].timeout == 7_200_000
    end

    test "parses bare integer as milliseconds" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          timeout: 5000
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stages[:s1].timeout == 5000
    end

    test "defaults timeout to infinity" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stages[:s1].timeout == :infinity
    end
  end

  describe "transition parsing" do
    test "parses on_success transition" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          on_success: s2
        - id: s2
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stages[:s1].on_success == :s2
    end

    test "parses on_failure transition" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          on_failure: error_handler
        - id: error_handler
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stages[:s1].on_failure == :error_handler
    end

    test "parses on_timeout transition" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          on_timeout: timeout_handler
        - id: timeout_handler
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stages[:s1].on_timeout == :timeout_handler
    end
  end

  describe "validation parsing" do
    test "parses compile validation" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          validation:
            - type: compile
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      [validation] = workflow.stages[:s1].validations

      assert %Validation{} = validation
      assert validation.type == :exit_code
      assert validation.pattern == 0
    end

    test "parses tests validation" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          validation:
            - type: tests
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      [validation] = workflow.stages[:s1].validations

      assert validation.type == :exit_code
      assert validation.error_message =~ "Tests failed"
    end

    test "parses lint validation" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          validation:
            - type: lint
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      [validation] = workflow.stages[:s1].validations

      assert validation.type == :exit_code
      assert validation.error_message =~ "Lint"
    end

    test "parses output_contains validation" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          validation:
            - type: output_contains
              pattern: "success"
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      [validation] = workflow.stages[:s1].validations

      assert validation.type == :output_contains
      assert validation.pattern == "success"
    end

    test "parses output_matches validation with regex" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          validation:
            - type: output_matches
              pattern: "passed.*\\\\d+"
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      [validation] = workflow.stages[:s1].validations

      assert validation.type == :output_matches
      assert %Regex{} = validation.pattern
      assert Regex.match?(validation.pattern, "passed 5 tests")
    end

    test "parses exit_code validation" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          validation:
            - type: exit_code
              pattern: 0
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      [validation] = workflow.stages[:s1].validations

      assert validation.type == :exit_code
      assert validation.pattern == 0
    end

    test "parses validation with negate option" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          validation:
            - type: output_contains
              pattern: "error"
              negate: true
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      [validation] = workflow.stages[:s1].validations

      assert validation.negate == true
    end

    test "parses validation with custom error message" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          validation:
            - type: compile
              error_message: Build failed!
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      [validation] = workflow.stages[:s1].validations

      assert validation.error_message == "Build failed!"
    end

    test "parses multiple validations" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          validation:
            - type: compile
            - type: tests
            - type: lint
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert length(workflow.stages[:s1].validations) == 3
    end

    test "supports validations alias" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          validations:
            - type: compile
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert length(workflow.stages[:s1].validations) == 1
    end
  end

  describe "entry point" do
    test "defaults entry_point to first stage" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: first
        - id: second
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.entry_point == :first
    end

    test "parses explicit entry_point" do
      yaml = """
      id: test
      name: Test
      entry_point: second
      stages:
        - id: first
        - id: second
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.entry_point == :second
    end
  end

  describe "stage_order" do
    test "preserves stage order from YAML" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: planning
        - id: implementation
        - id: review
        - id: complete
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stage_order == [:planning, :implementation, :review, :complete]
    end
  end

  describe "metadata" do
    test "extracts additional stage fields as metadata" do
      yaml = """
      id: test
      name: Test
      stages:
        - id: s1
          custom_field: custom_value
          another_field: 123
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.stages[:s1].metadata[:custom_field] == "custom_value"
      assert workflow.stages[:s1].metadata[:another_field] == 123
    end

    test "extracts additional workflow fields as metadata" do
      yaml = """
      id: test
      name: Test
      version: "1.0"
      author: developer
      stages:
        - id: s1
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)
      assert workflow.metadata[:version] == "1.0"
      assert workflow.metadata[:author] == "developer"
    end
  end

  describe "complex workflow" do
    test "parses complete feature implementation workflow" do
      yaml = """
      id: feature-implementation
      name: Feature Implementation
      description: Full feature implementation workflow
      intelligence: hybrid

      stages:
        - id: planning
          type: action
          command: "td critical-path"
          timeout: 5m
          on_success: implementation

        - id: implementation
          type: agent
          prompt_template: |
            Implement the feature from td issue {{issue.id}}
            Title: {{issue.title}}
          timeout: 30m
          validation:
            - type: compile
            - type: tests
          on_success: review
          on_failure: retry
          max_retries: 2

        - id: review
          type: action
          command: "td review {{session.issue_id}}"
          timeout: 5m
          on_success: complete

        - id: complete
          type: action
          command: "td approve {{session.issue_id}}"

      entry_point: planning
      """

      assert {:ok, workflow} = Parser.parse_string(yaml)

      assert workflow.id == "feature-implementation"
      assert workflow.name == "Feature Implementation"
      assert workflow.description == "Full feature implementation workflow"
      assert workflow.intelligence == :hybrid
      assert workflow.entry_point == :planning

      assert Map.keys(workflow.stages) |> length() == 4

      planning = workflow.stages[:planning]
      assert planning.type == :action
      assert planning.command == "td critical-path"
      assert planning.timeout == 300_000
      assert planning.on_success == :implementation

      implementation = workflow.stages[:implementation]
      assert implementation.type == :agent
      assert implementation.prompt =~ "{{issue.id}}"
      assert implementation.timeout == 1_800_000
      assert implementation.on_success == :review
      assert implementation.on_failure == :retry
      assert length(implementation.validations) == 2
      assert implementation.metadata[:max_retries] == 2

      review = workflow.stages[:review]
      assert review.type == :action
      assert review.on_success == :complete
    end
  end
end
