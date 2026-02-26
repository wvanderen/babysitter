defmodule Babysitter.Workflow.Validator do
  @moduledoc """
  Validates workflow definitions before execution.

  Performs comprehensive validation including:
  - Stage reference validation (on_success, on_failure, entry_point)
  - Required field validation
  - Intelligence level validation
  - Circular reference and unreachable stage detection
  """

  alias Babysitter.Workflow.ValidationError

  @valid_intelligence_levels [:dumb, :smart, :hybrid, nil]

  @spec validate(map()) :: {:ok, map()} | {:error, [ValidationError.t()]}
  def validate(workflow) when is_map(workflow) do
    errors =
      []
      |> validate_required_fields(workflow)
      |> validate_intelligence(workflow)
      |> validate_stage_references(workflow)
      |> Enum.reverse()

    case errors do
      [] ->
        warnings = detect_warnings(workflow)
        {:ok, Map.put(workflow, :warnings, warnings)}

      errors ->
        {:error, errors}
    end
  end

  defp validate_required_fields(errors, workflow) do
    errors
    |> maybe_add_error(:id, workflow)
    |> maybe_add_error(:name, workflow)
    |> maybe_add_error(:stages, workflow)
    |> validate_stages_not_empty(workflow)
  end

  defp maybe_add_error(errors, field, workflow) do
    case Map.get(workflow, field) do
      nil ->
        [ValidationError.missing_field(field) | errors]

      value when is_map(value) and map_size(value) == 0 and field == :stages ->
        [ValidationError.missing_field(field, "Workflow must have at least one stage") | errors]

      _ ->
        errors
    end
  end

  defp validate_stages_not_empty(errors, workflow) do
    case Map.get(workflow, :stages) do
      stages when is_map(stages) and map_size(stages) == 0 ->
        [ValidationError.missing_field(:stages, "Workflow must have at least one stage") | errors]

      _ ->
        errors
    end
  end

  defp validate_intelligence(errors, workflow) do
    intelligence = Map.get(workflow, :intelligence)

    if intelligence in @valid_intelligence_levels do
      errors
    else
      valid_options = Enum.join(@valid_intelligence_levels -- [nil], ", ")
      message = "Invalid intelligence level '#{intelligence}'. Must be one of: #{valid_options}"

      [ValidationError.invalid_value(:intelligence, intelligence, message) | errors]
    end
  end

  defp validate_stage_references(errors, workflow) do
    stages = Map.get(workflow, :stages, %{})
    stage_ids = Map.keys(stages)
    entry_point = Map.get(workflow, :entry_point)

    errors
    |> validate_entry_point(entry_point, stage_ids)
    |> validate_stage_transitions(stages, stage_ids)
  end

  defp validate_entry_point(errors, nil, _stage_ids), do: errors

  defp validate_entry_point(errors, entry_point, stage_ids) do
    if entry_point in stage_ids do
      errors
    else
      [ValidationError.invalid_reference(:entry_point, nil, entry_point) | errors]
    end
  end

  defp validate_stage_transitions(errors, stages, stage_ids) do
    Enum.reduce(stages, errors, fn {stage_id, stage}, acc ->
      acc
      |> validate_transition(stage_id, :on_success, stage, stage_ids)
      |> validate_transition(stage_id, :on_failure, stage, stage_ids)
      |> validate_transition(stage_id, :on_timeout, stage, stage_ids)
    end)
  end

  defp validate_transition(errors, stage_id, field, stage, stage_ids) do
    case Map.get(stage, field) do
      nil ->
        errors

      ref ->
        if ref in stage_ids do
          errors
        else
          [ValidationError.invalid_reference(field, stage_id, ref) | errors]
        end
    end
  end

  defp detect_warnings(workflow) do
    warnings = []

    warnings
    |> detect_circular_references(workflow)
    |> detect_unreachable_stages(workflow)
  end

  defp detect_circular_references(warnings, workflow) do
    stages = Map.get(workflow, :stages, %{})
    entry_point = Map.get(workflow, :entry_point)

    if entry_point && Map.has_key?(stages, entry_point) do
      case find_cycle(stages, entry_point) do
        nil ->
          warnings

        cycle ->
          [ValidationError.circular_reference(cycle) | warnings]
      end
    else
      warnings
    end
  end

  defp find_cycle(stages, start) do
    do_find_cycle(stages, start, MapSet.new(), [])
  end

  defp do_find_cycle(stages, current, visited, path) do
    cond do
      MapSet.member?(visited, current) ->
        cycle_start = Enum.find_index(path, &(&1 == current)) || 0
        Enum.slice(path, cycle_start..length(path)//1) ++ [current]

      not Map.has_key?(stages, current) ->
        nil

      true ->
        stage = Map.get(stages, current)
        transitions = [:on_success, :on_failure, :on_timeout]

        new_visited = MapSet.put(visited, current)
        new_path = path ++ [current]

        Enum.find_value(transitions, fn field ->
          case Map.get(stage, field) do
            nil -> nil
            next -> do_find_cycle(stages, next, new_visited, new_path)
          end
        end)
    end
  end

  defp detect_unreachable_stages(warnings, workflow) do
    stages = Map.get(workflow, :stages, %{})
    entry_point = Map.get(workflow, :entry_point)

    if entry_point && Map.has_key?(stages, entry_point) do
      reachable = find_reachable_stages(stages, entry_point)
      all_stages = Map.keys(stages)
      unreachable = Enum.reject(all_stages, &MapSet.member?(reachable, &1))

      Enum.reduce(unreachable, warnings, fn stage_id, acc ->
        [ValidationError.unreachable_stage(stage_id) | acc]
      end)
    else
      warnings
    end
  end

  defp find_reachable_stages(stages, entry_point) do
    do_find_reachable(stages, entry_point, MapSet.new())
  end

  defp do_find_reachable(stages, current, visited) do
    if MapSet.member?(visited, current) or not Map.has_key?(stages, current) do
      visited
    else
      stage = Map.get(stages, current)
      new_visited = MapSet.put(visited, current)

      transitions =
        [:on_success, :on_failure, :on_timeout]
        |> Enum.map(&Map.get(stage, &1))
        |> Enum.filter(&(&1 != nil))

      Enum.reduce(transitions, new_visited, fn next, acc ->
        do_find_reachable(stages, next, acc)
      end)
    end
  end
end
