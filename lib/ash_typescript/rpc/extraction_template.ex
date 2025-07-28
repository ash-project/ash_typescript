defmodule AshTypescript.Rpc.ExtractionTemplate do
  @moduledoc """
  Optimized extraction template system for the new RPC pipeline.
  
  Provides pre-computed instructions for efficient field extraction
  with simplified instruction types and better performance.
  """

  @typedoc """
  Extraction template with pre-formatted output field names as keys.
  """
  @type extraction_template :: %{String.t() => extraction_instruction()}

  @typedoc """
  Simplified extraction instructions for better performance.
  """
  @type extraction_instruction ::
          {:extract, atom()}
          | {:extract_with_spec, atom(), term()}
          | {:nested, atom(), extraction_template()}
          | {:calc_result, atom(), extraction_template()}

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
  Creates a field extraction instruction with attribute specification.
  Used for resource attributes that need type-specific transformation.
  """
  @spec extract_field_with_spec(atom(), term()) :: extraction_instruction()
  def extract_field_with_spec(source_atom, attribute_spec) when is_atom(source_atom) do
    {:extract_with_spec, source_atom, attribute_spec}
  end

  @doc """
  Creates a nested resource processing instruction.
  """
  @spec nested_field(atom(), extraction_template()) :: extraction_instruction()
  def nested_field(source_atom, nested_template) when is_atom(source_atom) do
    {:nested, source_atom, nested_template}
  end

  @doc """
  Creates a calculation result processing instruction.
  """
  @spec calc_result_field(atom(), extraction_template()) :: extraction_instruction()
  def calc_result_field(source_atom, field_template) when is_atom(source_atom) do
    {:calc_result, source_atom, field_template}
  end
end