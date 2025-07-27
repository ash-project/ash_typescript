defmodule AshTypescript.Rpc.ExtractionTemplate do
  @moduledoc """
  Data structures and utilities for extraction templates.

  Extraction templates provide pre-computed instructions for efficiently
  extracting and formatting fields from Ash query results.
  """

  @typedoc """
  An extraction template is a map where keys are output field names (pre-formatted)
  and values are extraction instructions that specify how to extract the field value.
  """
  @type extraction_template :: %{String.t() => extraction_instruction()}

  @typedoc """
  Extraction instructions specify how to extract a field value from the source data.
  """
  @type extraction_instruction ::
          {:extract, atom()}
          | {:nested, atom(), extraction_template()}
          | {:array, extraction_instruction()}
          | {:calc_result, atom(), extraction_template()}
          | {:union_selection, atom(), union_member_specs()}
          | {:typed_struct_selection, atom(), field_specs()}
          | {:typed_struct_nested_selection, atom(), nested_field_specs()}
          | {:custom_transform, atom(), transform_function()}

  @type union_member_specs :: %{String.t() => :primitive | list()}
  @type field_specs :: list(atom())
  @type nested_field_specs :: %{atom() => list(atom())}
  @type transform_function :: (any() -> any())

  @doc """
  Creates an empty extraction template.
  """
  @spec new() :: extraction_template()
  def new, do: %{}

  @doc """
  Adds an extraction instruction to a template.
  """
  @spec put_instruction(extraction_template(), String.t(), extraction_instruction()) ::
          extraction_template()
  def put_instruction(template, output_field, instruction) do
    Map.put(template, output_field, instruction)
  end

  @doc """
  Creates a simple field extraction instruction.
  """
  @spec extract_field(atom()) :: extraction_instruction()
  def extract_field(source_atom) when is_atom(source_atom) do
    {:extract, source_atom}
  end

  @doc """
  Creates a nested resource processing instruction.
  """
  @spec nested_field(atom(), extraction_template()) :: extraction_instruction()
  def nested_field(source_atom, nested_template) when is_atom(source_atom) do
    {:nested, source_atom, nested_template}
  end

  @doc """
  Creates an array processing instruction.
  """
  @spec array_field(extraction_instruction()) :: extraction_instruction()
  def array_field(inner_instruction) do
    {:array, inner_instruction}
  end

  @doc """
  Creates a calculation result processing instruction.
  """
  @spec calc_result_field(atom(), extraction_template()) :: extraction_instruction()
  def calc_result_field(source_atom, field_template) when is_atom(source_atom) do
    {:calc_result, source_atom, field_template}
  end

  @doc """
  Creates a union type field selection instruction.
  """
  @spec union_selection_field(atom(), union_member_specs()) :: extraction_instruction()
  def union_selection_field(source_atom, union_specs) when is_atom(source_atom) do
    {:union_selection, source_atom, union_specs}
  end

  @doc """
  Creates a TypedStruct field selection instruction.
  """
  @spec typed_struct_selection_field(atom(), field_specs()) :: extraction_instruction()
  def typed_struct_selection_field(source_atom, field_specs) when is_atom(source_atom) do
    {:typed_struct_selection, source_atom, field_specs}
  end

  @doc """
  Creates a TypedStruct nested field selection instruction.
  """
  @spec typed_struct_nested_selection_field(atom(), nested_field_specs()) ::
          extraction_instruction()
  def typed_struct_nested_selection_field(source_atom, nested_field_specs)
      when is_atom(source_atom) do
    {:typed_struct_nested_selection, source_atom, nested_field_specs}
  end

  @doc """
  Creates a custom transformation instruction.
  """
  @spec custom_transform_field(atom(), transform_function()) :: extraction_instruction()
  def custom_transform_field(source_atom, transform_fn) when is_atom(source_atom) do
    {:custom_transform, source_atom, transform_fn}
  end

  @doc """
  Validates that an extraction template is well-formed.
  """
  @spec validate(extraction_template()) :: :ok | {:error, String.t()}
  def validate(template) when is_map(template) do
    case validate_instructions(Map.values(template)) do
      :ok -> :ok
      {:error, reason} -> {:error, "Invalid template: #{reason}"}
    end
  end

  def validate(_), do: {:error, "Template must be a map"}

  defp validate_instructions([]), do: :ok

  defp validate_instructions([instruction | rest]) do
    case validate_instruction(instruction) do
      :ok -> validate_instructions(rest)
      error -> error
    end
  end

  defp validate_instruction({:extract, source_atom}) when is_atom(source_atom), do: :ok

  defp validate_instruction({:nested, source_atom, nested_template})
       when is_atom(source_atom) and is_map(nested_template) do
    validate(nested_template)
  end

  defp validate_instruction({:array, inner_instruction}) do
    validate_instruction(inner_instruction)
  end

  defp validate_instruction({:calc_result, source_atom, field_template})
       when is_atom(source_atom) and is_map(field_template) do
    validate(field_template)
  end

  defp validate_instruction({:union_selection, source_atom, union_specs})
       when is_atom(source_atom) and is_map(union_specs) do
    :ok
  end

  defp validate_instruction({:typed_struct_selection, source_atom, field_specs})
       when is_atom(source_atom) and is_list(field_specs) do
    if Enum.all?(field_specs, &is_atom/1) do
      :ok
    else
      {:error, "typed_struct_selection field_specs must be list of atoms"}
    end
  end

  defp validate_instruction({:typed_struct_nested_selection, source_atom, nested_specs})
       when is_atom(source_atom) and is_map(nested_specs) do
    if Enum.all?(nested_specs, fn {k, v} -> is_atom(k) and is_list(v) end) do
      :ok
    else
      {:error, "typed_struct_nested_selection nested_specs must be map of atom -> list"}
    end
  end

  defp validate_instruction({:custom_transform, source_atom, transform_fn})
       when is_atom(source_atom) and is_function(transform_fn, 1) do
    :ok
  end

  defp validate_instruction(instruction) do
    {:error, "Unknown instruction type: #{inspect(instruction)}"}
  end

  @doc """
  Pretty prints an extraction template for debugging.
  """
  @spec pretty_print(extraction_template()) :: String.t()
  def pretty_print(template) do
    template
    |> Enum.map(fn {output_field, instruction} ->
      "#{output_field} => #{inspect_instruction(instruction)}"
    end)
    |> Enum.join("\n")
  end

  defp inspect_instruction({:extract, source_atom}) do
    "extract(:#{source_atom})"
  end

  defp inspect_instruction({:nested, source_atom, nested_template}) do
    nested_size = map_size(nested_template)
    "nested(:#{source_atom}, #{nested_size} fields)"
  end

  defp inspect_instruction({:array, inner_instruction}) do
    "array(#{inspect_instruction(inner_instruction)})"
  end

  defp inspect_instruction({:calc_result, source_atom, field_template}) do
    field_count = map_size(field_template)
    "calc_result(:#{source_atom}, #{field_count} fields)"
  end

  defp inspect_instruction({:union_selection, source_atom, union_specs}) do
    member_count = map_size(union_specs)
    "union_selection(:#{source_atom}, #{member_count} members)"
  end

  defp inspect_instruction({:typed_struct_selection, source_atom, field_specs}) do
    field_count = length(field_specs)
    "typed_struct_selection(:#{source_atom}, #{field_count} fields)"
  end

  defp inspect_instruction({:typed_struct_nested_selection, source_atom, nested_specs}) do
    nested_count = map_size(nested_specs)
    "typed_struct_nested_selection(:#{source_atom}, #{nested_count} composites)"
  end

  defp inspect_instruction({:custom_transform, source_atom, _transform_fn}) do
    "custom_transform(:#{source_atom})"
  end

  defp inspect_instruction(instruction) do
    inspect(instruction)
  end
end