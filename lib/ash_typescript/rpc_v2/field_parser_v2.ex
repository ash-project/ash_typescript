defmodule AshTypescript.RpcV2.FieldParserV2 do
  @moduledoc """
  Strict field parser with fail-fast validation.
  
  This is a complete rewrite focused on:
  - Strict validation: Fail immediately on unknown fields
  - Performance: Single-pass processing, minimal allocations
  - Simplicity: Clean classification with clear error messages
  - No permissive modes: All invalid fields are errors
  
  Replaces the 920-line FieldParser with a clean, optimized implementation.
  """

  alias AshTypescript.RpcV2.{Context, ExtractionTemplateV2}
  alias AshTypescript.FieldFormatter

  @doc """
  Main entry point for strict field parsing.
  
  Validates all fields and fails immediately on any unknown field.
  Returns {:ok, {select, load, template}} or {:error, reason}.
  
  ## Performance optimizations
  - Single-pass field processing
  - Pre-computed classification lookup
  - Minimal pattern matching overhead
  - Template building integrated with parsing
  """
  @spec parse_requested_fields_strict(list(), module(), atom()) ::
    {:ok, {list(), list(), map()}} | {:error, term()}
  def parse_requested_fields_strict(fields, resource, formatter) do
    context = Context.new(resource, formatter)
    
    # Pre-compute field classification map for O(1) lookup
    field_classifications = build_field_classification_map(resource)
    
    # Single-pass processing with fail-fast validation
    case process_fields_strict(fields, context, field_classifications) do
      {:ok, {select, load, template}} ->
        {:ok, {Enum.reverse(select), Enum.reverse(load), template}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Single-pass field processing with strict validation
  defp process_fields_strict(fields, context, classifications) do
    initial_state = {[], [], ExtractionTemplateV2.new()}
    
    Enum.reduce_while(fields, {:ok, initial_state}, fn field, {:ok, {select_acc, load_acc, template_acc}} ->
      case process_single_field_strict(field, context, classifications) do
        {:ok, field_result} ->
          updated_state = merge_field_result(field_result, {select_acc, load_acc, template_acc})
          {:cont, {:ok, updated_state}}
        
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # Process a single field with strict validation
  defp process_single_field_strict(field, context, classifications) do
    case normalize_field_strict(field, context) do
      {:ok, {field_atom, field_spec}} ->
        classify_and_process_strict(field_atom, field_spec, context, classifications)
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Normalize field input with strict validation
  defp normalize_field_strict(field, context) when is_binary(field) do
    field_atom = FieldFormatter.parse_input_field(field, context.formatter)
    {:ok, {field_atom, nil}}
  end

  defp normalize_field_strict(field_map, context) when is_map(field_map) do
    case Map.to_list(field_map) do
      [{field_name, field_spec}] when is_binary(field_name) ->
        field_atom = FieldFormatter.parse_input_field(field_name, context.formatter)
        {:ok, {field_atom, field_spec}}
      
      invalid ->
        {:error, {:invalid_field_format, invalid}}
    end
  end

  defp normalize_field_strict(field, _context) do
    {:error, {:unsupported_field_format, field}}
  end

  # Classify and process field with strict validation  
  defp classify_and_process_strict(field_atom, field_spec, context, classifications) do
    case Map.get(classifications, field_atom) do
      nil ->
        {:error, {:unknown_field, field_atom, context.resource}}
      
      field_type ->
        process_field_by_type_strict(field_type, field_atom, field_spec, context)
    end
  end

  # Process field based on its type with strict validation
  defp process_field_by_type_strict(:simple_attribute, field_atom, nil, context) do
    output_field = format_output_field_name(field_atom, context.formatter)
    instruction = ExtractionTemplateV2.extract_field(field_atom)
    {:ok, {:select, field_atom, output_field, instruction}}
  end

  defp process_field_by_type_strict(:simple_attribute, field_atom, field_spec, _context) when field_spec != nil do
    {:error, {:simple_attribute_with_spec, field_atom, field_spec}}
  end

  defp process_field_by_type_strict(:simple_calculation, field_atom, nil, context) do
    output_field = format_output_field_name(field_atom, context.formatter)
    instruction = ExtractionTemplateV2.extract_field(field_atom)
    {:ok, {:load, field_atom, output_field, instruction}}
  end

  defp process_field_by_type_strict(:simple_calculation, field_atom, field_spec, _context) when field_spec != nil do
    {:error, {:simple_calculation_with_spec, field_atom, field_spec}}
  end

  defp process_field_by_type_strict(:complex_calculation, field_atom, field_spec, context) when is_map(field_spec) do
    case build_calculation_load_strict(field_atom, field_spec, context) do
      {:ok, {load_statement, template_instruction}} ->
        output_field = format_output_field_name(field_atom, context.formatter)
        {:ok, {:load, load_statement, output_field, template_instruction}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_field_by_type_strict(:complex_calculation, field_atom, field_spec, context) when is_list(field_spec) do
    # Complex calculation with field selection but no arguments
    output_field = format_output_field_name(field_atom, context.formatter)
    load_statement = {field_atom, field_spec}
    template_instruction = ExtractionTemplateV2.extract_field(field_atom)
    {:ok, {:load, load_statement, output_field, template_instruction}}
  end

  defp process_field_by_type_strict(:complex_calculation, field_atom, nil, context) do
    # Complex calculation without arguments - treat as simple
    output_field = format_output_field_name(field_atom, context.formatter)
    instruction = ExtractionTemplateV2.extract_field(field_atom)
    {:ok, {:load, field_atom, output_field, instruction}}
  end

  defp process_field_by_type_strict(:relationship, field_atom, field_spec, context) when is_list(field_spec) do
    case process_relationship_strict(field_atom, field_spec, context) do
      {:ok, {load_statement, template_instruction}} ->
        output_field = format_output_field_name(field_atom, context.formatter)
        {:ok, {:load, load_statement, output_field, template_instruction}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_field_by_type_strict(:relationship, field_atom, nil, context) do
    # Relationship without nested fields
    output_field = format_output_field_name(field_atom, context.formatter)
    instruction = ExtractionTemplateV2.extract_field(field_atom)
    {:ok, {:load, field_atom, output_field, instruction}}
  end

  defp process_field_by_type_strict(:embedded_resource, field_atom, field_spec, context) when is_list(field_spec) do
    case process_embedded_resource_strict(field_atom, field_spec, context) do
      {:ok, result} ->
        {:ok, result}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_field_by_type_strict(:embedded_resource, field_atom, nil, context) do
    # Embedded resource without field selection
    output_field = format_output_field_name(field_atom, context.formatter)
    instruction = ExtractionTemplateV2.extract_field(field_atom)
    {:ok, {:select, field_atom, output_field, instruction}}
  end

  defp process_field_by_type_strict(field_type, field_atom, field_spec, _context) do
    {:error, {:unsupported_field_combination, field_type, field_atom, field_spec}}
  end

  # Build field classification map for O(1) lookup
  defp build_field_classification_map(resource) do
    Map.new()
    |> add_simple_attributes(resource)
    |> add_calculations(resource)
    |> add_aggregates(resource)
    |> add_relationships(resource)
    |> add_embedded_resources(resource)
  end

  defp add_simple_attributes(classifications, resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.reduce(classifications, fn attr, acc ->
      Map.put(acc, attr.name, :simple_attribute)
    end)
  end

  defp add_calculations(classifications, resource) do
    resource
    |> Ash.Resource.Info.calculations()
    |> Enum.reduce(classifications, fn calc, acc ->
      field_type = if length(calc.arguments) > 0, do: :complex_calculation, else: :simple_calculation
      Map.put(acc, calc.name, field_type)
    end)
  end

  defp add_aggregates(classifications, resource) do
    resource
    |> Ash.Resource.Info.aggregates()
    |> Enum.reduce(classifications, fn agg, acc ->
      Map.put(acc, agg.name, :aggregate)
    end)
  end

  defp add_relationships(classifications, resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.reduce(classifications, fn rel, acc ->
      Map.put(acc, rel.name, :relationship)
    end)
  end

  defp add_embedded_resources(classifications, resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.reduce(classifications, fn attr, acc ->
      if is_embedded_resource_type?(attr.type) do
        Map.put(acc, attr.name, :embedded_resource)
      else
        acc
      end
    end)
  end

  # Helper functions

  defp merge_field_result({:select, field_atom, output_field, instruction}, {select_acc, load_acc, template_acc}) do
    updated_template = ExtractionTemplateV2.put_instruction(template_acc, output_field, instruction)
    {[field_atom | select_acc], load_acc, updated_template}
  end

  defp merge_field_result({:load, load_statement, output_field, instruction}, {select_acc, load_acc, template_acc}) do
    updated_template = ExtractionTemplateV2.put_instruction(template_acc, output_field, instruction)
    {select_acc, [load_statement | load_acc], updated_template}
  end

  defp merge_field_result({:both, field_atom, load_statement, output_field, instruction}, {select_acc, load_acc, template_acc}) do
    updated_template = ExtractionTemplateV2.put_instruction(template_acc, output_field, instruction)
    {[field_atom | select_acc], [load_statement | load_acc], updated_template}
  end

  defp format_output_field_name(field_atom, formatter) when is_atom(field_atom) do
    field_string = Atom.to_string(field_atom)
    FieldFormatter.format_field(field_string, formatter)
  end

  defp build_calculation_load_strict(field_atom, field_spec, context) do
    # Validate field_spec structure for calculations
    case field_spec do
      %{"args" => args, "fields" => fields} when is_map(args) and is_list(fields) ->
        # Convert string keys to atom keys for Ash compatibility - direct args format
        atom_args = convert_args_to_atoms(args)
        load_statement = {field_atom, atom_args}
        template_instruction = ExtractionTemplateV2.extract_field(field_atom)
        {:ok, {load_statement, template_instruction}}
      
      %{"args" => args} when is_map(args) ->
        # Convert string keys to atom keys for Ash compatibility - direct args format
        atom_args = convert_args_to_atoms(args)
        load_statement = {field_atom, atom_args}
        template_instruction = ExtractionTemplateV2.extract_field(field_atom)
        {:ok, {load_statement, template_instruction}}
      
      invalid ->
        {:error, {:invalid_calculation_spec, field_atom, invalid}}
    end
  end

  # Helper function to convert string keys to atom keys in args map
  defp convert_args_to_atoms(args) when is_map(args) do
    for {key, value} <- args, into: %{} do
      atom_key = if is_binary(key), do: String.to_atom(key), else: key
      {atom_key, value}
    end
  end

  defp process_relationship_strict(field_atom, field_spec, context) do
    # Recursively parse nested fields for relationship
    target_resource = get_relationship_target_resource(field_atom, context.resource)
    
    case parse_requested_fields_strict(field_spec, target_resource, context.formatter) do
      {:ok, {nested_select, nested_load, nested_template}} ->
        combined_nested = nested_select ++ nested_load
        load_statement = {field_atom, combined_nested}
        template_instruction = ExtractionTemplateV2.nested_field(field_atom, nested_template)
        {:ok, {load_statement, template_instruction}}
      
      {:error, reason} ->
        {:error, {:relationship_field_error, field_atom, reason}}
    end
  end

  defp process_embedded_resource_strict(field_atom, field_spec, context) do
    embedded_module = get_embedded_resource_module(field_atom, context.resource)
    
    if embedded_module do
      # Process embedded resource fields
      output_field = format_output_field_name(field_atom, context.formatter)
      
      case parse_requested_fields_strict(field_spec, embedded_module, context.formatter) do
        {:ok, {_nested_select, nested_load, nested_template}} ->
          instruction = ExtractionTemplateV2.nested_field(field_atom, nested_template)
          
          case nested_load do
            [] ->
              # No loadable items - just select
              {:ok, {:select, field_atom, output_field, instruction}}
            load_items ->
              # Both select and load needed
              load_statement = {field_atom, load_items}
              {:ok, {:both, field_atom, load_statement, output_field, instruction}}
          end
        
        {:error, reason} ->
          {:error, {:embedded_resource_field_error, field_atom, reason}}
      end
    else
      {:error, {:embedded_resource_module_not_found, field_atom}}
    end
  end

  # Type checking helpers

  defp is_embedded_resource_type?(module) when is_atom(module) do
    try do
      AshTypescript.Codegen.is_embedded_resource?(module)
    rescue
      _ -> false
    end
  end

  defp is_embedded_resource_type?({:array, module}) when is_atom(module) do
    is_embedded_resource_type?(module)
  end

  defp is_embedded_resource_type?(_), do: false

  defp get_relationship_target_resource(relationship_name, resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.find(&(&1.name == relationship_name))
    |> case do
      nil -> resource  # Fallback
      relationship -> relationship.destination
    end
  end

  defp get_embedded_resource_module(field_name, resource) do
    case Ash.Resource.Info.attribute(resource, field_name) do
      nil -> nil
      attribute ->
        case attribute.type do
          module when is_atom(module) -> module
          {:array, module} when is_atom(module) -> module
          _ -> nil
        end
    end
  end
end