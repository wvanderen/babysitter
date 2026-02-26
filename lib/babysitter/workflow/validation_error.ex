defmodule Babysitter.Workflow.ValidationError do
  @moduledoc """
  Represents a validation error found in a workflow definition.
  """

  @type error_type ::
          :missing_field
          | :invalid_reference
          | :invalid_value
          | :circular_reference
          | :unreachable_stage

  @type t :: %__MODULE__{
          type: error_type(),
          field: atom() | nil,
          stage_id: atom() | nil,
          message: String.t(),
          details: map()
        }

  @enforce_keys [:type, :message]
  defstruct [:type, :field, :stage_id, :message, details: %{}]

  @spec missing_field(atom(), String.t()) :: t()
  def missing_field(field, message \\ nil) do
    %__MODULE__{
      type: :missing_field,
      field: field,
      message: message || "Missing required field: #{field}"
    }
  end

  @spec invalid_reference(atom(), atom(), atom(), String.t()) :: t()
  def invalid_reference(field, stage_id, referenced_stage, message \\ nil) do
    %__MODULE__{
      type: :invalid_reference,
      field: field,
      stage_id: stage_id,
      message:
        message ||
          "Stage '#{stage_id}' references non-existent stage '#{referenced_stage}' in #{field}",
      details: %{referenced_stage: referenced_stage}
    }
  end

  @spec invalid_value(atom(), term(), String.t()) :: t()
  def invalid_value(field, value, message) do
    %__MODULE__{
      type: :invalid_value,
      field: field,
      message: message,
      details: %{invalid_value: value}
    }
  end

  @spec circular_reference([atom()]) :: t()
  def circular_reference(cycle) do
    cycle_str = Enum.join(cycle, " -> ")

    %__MODULE__{
      type: :circular_reference,
      message: "Circular reference detected: #{cycle_str}",
      details: %{cycle: cycle}
    }
  end

  @spec unreachable_stage(atom()) :: t()
  def unreachable_stage(stage_id) do
    %__MODULE__{
      type: :unreachable_stage,
      stage_id: stage_id,
      message: "Stage '#{stage_id}' is not reachable from entry point",
      details: %{}
    }
  end
end
