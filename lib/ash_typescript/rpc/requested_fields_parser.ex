defmodule AshTypescript.Rpc.RequestedFieldsParser do
  @moduledoc """
  Parser for requested fields in RPC requests with strict validation.
  
  This module is responsible for:
  - Validating requested fields exist on the resource/action return type
  - Building select and load statements for Ash queries
  - Creating extraction templates in keyword list format
  - Handling different action types (CRUD vs generic)
  - Enforcing empty fields for primitive/unknown return types
  """

  alias AshTypescript.FieldFormatter
  alias AshTypescript.Rpc.ExtractionTemplate

  @doc """
  Parse requested fields for an action.
  
  Returns {:ok, {select, load, extraction_template}} or {:error, reason}
  
  For CRUD actions (create, read, update), fields are validated against the resource.
  For generic actions, fields are validated against the action's return type.
  
  ## Parameters
  - resource: The Ash resource module
  - action: The action struct from Ash.Resource.Info.action/2
  - requested_fields: The fields requested by the client
  
  ## Returns
  - select: List of fields to select (atoms)
  - load: List of fields/relationships to load (atoms or tuples)
  - extraction_template: Map for result extraction with output field names as keys
  """
  @spec parse_requested_fields(module(), struct(), list()) ::
          {:ok, {list(), list(), map()}} | {:error, term()}
  def parse_requested_fields(resource, action, requested_fields) do
    with {:ok, formatter} <- get_formatter(),
         {:ok, normalized_fields} <- normalize_fields(requested_fields, formatter),
         {:ok, action_return_info} <- get_action_return_info(resource, action),
         :ok <- validate_fields_allowed(action_return_info, normalized_fields),
         {:ok, result} <- build_field_statements(resource, action, action_return_info, normalized_fields, formatter) do
      {:ok, result}
    end
  end

  # Get the input field formatter from configuration
  defp get_formatter do
    {:ok, AshTypescript.Rpc.input_field_formatter()}
  end

  # Normalize field specifications to atoms
  defp normalize_fields(fields, formatter) when is_list(fields) do
    normalized = Enum.map(fields, &normalize_field(&1, formatter))
    {:ok, normalized}
  rescue
    e -> {:error, {:field_normalization_error, e}}
  end

  defp normalize_fields(_fields, _formatter) do
    {:error, {:invalid_fields_format, "Fields must be a list"}}
  end

  defp normalize_field(field, formatter) when is_binary(field) do
    FieldFormatter.parse_input_field(field, formatter)
  end

  defp normalize_field(field, formatter) when is_map(field) and map_size(field) == 1 do
    [{key, value}] = Map.to_list(field)
    normalized_key = normalize_field_key(key, formatter)
    normalized_value = normalize_field_value(value, formatter)
    {normalized_key, normalized_value}
  end

  defp normalize_field(field, _formatter) when is_atom(field) do
    field
  end

  defp normalize_field(field, _formatter) do
    raise ArgumentError, "Invalid field format: #{inspect(field)}"
  end

  defp normalize_field_key(key, formatter) when is_binary(key) do
    FieldFormatter.parse_input_field(key, formatter)
  end

  defp normalize_field_key(key, _formatter) when is_atom(key) do
    key
  end

  defp normalize_field_value(value, formatter) when is_list(value) do
    Enum.map(value, &normalize_field(&1, formatter))
  end

  defp normalize_field_value(value, formatter) when is_map(value) do
    # Recursively normalize map values (for args/fields in calculations)
    for {k, v} <- value, into: %{} do
      {k, normalize_field_value(v, formatter)}
    end
  end

  defp normalize_field_value(value, _formatter) do
    value
  end

  # Get information about what the action returns
  defp get_action_return_info(_resource, %{type: type} = action) when type in [:create, :read, :update] do
    # CRUD actions always return the resource (or list of resources for read)
    {:ok, {:resource, action.type}}
  end

  defp get_action_return_info(_resource, %{type: :destroy} = _action) do
    # Destroy actions typically return :ok or the destroyed record
    {:ok, {:resource, :destroy}}
  end

  defp get_action_return_info(resource, %{type: :action} = action) do
    # Generic actions need to be inspected for their return type
    case action do
      %{returns: nil} ->
        # No explicit return type
        {:ok, :unknown}
        
      %{returns: return_type} ->
        analyze_return_type(return_type, resource, action)
        
      _ ->
        {:ok, :unknown}
    end
  end

  defp get_action_return_info(_resource, _action) do
    {:ok, :unknown}
  end

  # Analyze the return type of a generic action
  defp analyze_return_type(type, resource, action) when is_atom(type) do
    cond do
      # Check for map with field constraints (handles both :map and Ash.Type.Map)
      type == :map or type == Ash.Type.Map ->
        case Map.get(action, :constraints) do
          constraints when is_list(constraints) ->
            case Keyword.get(constraints, :fields) do
              fields when is_list(fields) ->
                {:ok, {:map_with_constraints, fields}}
              _ ->
                {:ok, {:primitive, :map}}
            end
          _ ->
            {:ok, {:primitive, :map}}
        end
        
      # Check if it's a built-in type
      type in [:string, :integer, :boolean, :atom, :float, :decimal, :uuid, :date, :datetime, :time, :any] ->
        {:ok, {:primitive, type}}
        
      # Check if it's the resource itself
      type == resource ->
        {:ok, {:resource, :action}}
        
      # Check if it's another resource
      ash_resource?(type) ->
        {:ok, {:other_resource, type}}
        
      # Check for struct types
      true ->
        {:ok, :unknown}
    end
  end

  defp analyze_return_type({:array, inner_type}, resource, action) do
    case analyze_return_type(inner_type, resource, action) do
      {:ok, {:primitive, _}} = result -> result
      {:ok, {:resource, _}} -> {:ok, {:resource_list, :action}}
      {:ok, {:other_resource, type}} -> {:ok, {:other_resource_list, type}}
      {:ok, {:map_with_constraints, constraints}} -> {:ok, {:map_with_constraints_list, constraints}}
      _ -> {:ok, :unknown}
    end
  end

  defp analyze_return_type(%{type: type} = spec, resource, action) when is_map(spec) do
    # Handle more complex type specifications
    analyze_return_type(type, resource, action)
  end

  defp analyze_return_type(_, _resource, _action) do
    {:ok, :unknown}
  end

  # Check if a module is an Ash resource
  defp ash_resource?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :spark_is, 0) and
      module.spark_is() == Ash.Resource
  rescue
    _ -> false
  end

  # Validate that fields are allowed for this return type
  defp validate_fields_allowed({:primitive, _type}, []) do
    :ok
  end

  defp validate_fields_allowed({:primitive, type}, fields) when fields != [] do
    {:error, {:fields_not_allowed, "Action returns primitive type #{type}, fields parameter must be empty"}}
  end

  defp validate_fields_allowed(:unknown, []) do
    :ok
  end

  defp validate_fields_allowed(:unknown, fields) when fields != [] do
    {:error, {:fields_not_allowed, "Action return type unknown, fields parameter must be empty"}}
  end

  defp validate_fields_allowed(_return_info, _fields) do
    # For resource returns, fields are allowed
    :ok
  end

  # Build select, load, and extraction template
  defp build_field_statements(resource, _action, {:resource, _action_type}, fields, formatter) do
    # For actions that return the resource itself
    target_resource = resource
    build_statements_for_resource(target_resource, fields, formatter)
  end

  defp build_field_statements(resource, _action, {:resource_list, _action_type}, fields, formatter) do
    # For actions that return a list of the resource
    # Same as single resource, just wrapped in a list
    build_statements_for_resource(resource, fields, formatter)
  end

  defp build_field_statements(_resource, _action, {:other_resource, target_resource}, fields, formatter) do
    # For actions that return a different resource
    build_statements_for_resource(target_resource, fields, formatter)
  end

  defp build_field_statements(_resource, _action, {:other_resource_list, target_resource}, fields, formatter) do
    # For actions that return a list of a different resource
    build_statements_for_resource(target_resource, fields, formatter)
  end

  defp build_field_statements(_resource, _action, {:map_with_constraints, field_constraints}, fields, formatter) do
    # For actions that return a map with field constraints
    build_statements_for_map_constraints(field_constraints, fields, formatter)
  end

  defp build_field_statements(_resource, _action, {:map_with_constraints_list, field_constraints}, fields, formatter) do
    # For actions that return a list of maps with field constraints
    build_statements_for_map_constraints(field_constraints, fields, formatter)
  end

  defp build_field_statements(_resource, _action, {:primitive, _type}, _fields, _formatter) do
    # Primitive types - no field selection possible
    {:ok, {[], [], %{}}}
  end

  defp build_field_statements(_resource, _action, :unknown, _fields, _formatter) do
    # Unknown return type - no field selection possible
    {:ok, {[], [], %{}}}
  end

  # Build statements for a specific resource
  defp build_statements_for_resource(resource, fields, formatter) do
    # Get all available fields for the resource
    attributes = Ash.Resource.Info.public_attributes(resource)
    calculations = Ash.Resource.Info.calculations(resource)
    aggregates = Ash.Resource.Info.aggregates(resource)
    relationships = Ash.Resource.Info.public_relationships(resource)
    
    # Build lookup maps
    attribute_map = Map.new(attributes, &{&1.name, &1})
    calculation_map = Map.new(calculations, &{&1.name, &1})
    aggregate_map = Map.new(aggregates, &{&1.name, &1})
    relationship_map = Map.new(relationships, &{&1.name, &1})
    
    # Process each field
    process_fields(fields, resource, formatter, %{
      attributes: attribute_map,
      calculations: calculation_map,
      aggregates: aggregate_map,
      relationships: relationship_map
    })
  end

  # Build statements for a map with field constraints
  defp build_statements_for_map_constraints(field_constraints, fields, formatter) do
    # Build a lookup map of valid field names from constraints
    valid_fields = Map.new(field_constraints, fn {field_name, _field_spec} -> {field_name, true} end)
    
    # Process each requested field
    case process_map_fields(fields, valid_fields, formatter) do
      {:ok, template} ->
        # For maps, we don't need select/load, just extraction template
        {:ok, {[], [], template}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Process fields for map constraints
  defp process_map_fields(fields, valid_fields, formatter) do
    initial_template = ExtractionTemplate.new()
    
    result = Enum.reduce_while(fields, {:ok, initial_template}, fn field, {:ok, template_acc} ->
      case normalize_and_validate_map_field(field, valid_fields, formatter) do
        {:ok, {field_atom, output_name}} ->
          instruction = ExtractionTemplate.extract_field(field_atom)
          updated_template = ExtractionTemplate.put_instruction(template_acc, output_name, instruction)
          {:cont, {:ok, updated_template}}
          
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    
    case result do
      {:ok, template} -> {:ok, template}
      error -> error
    end
  end

  # Normalize and validate a single map field
  defp normalize_and_validate_map_field(field, valid_fields, formatter) when is_binary(field) do
    field_atom = FieldFormatter.parse_input_field(field, formatter)
    
    if Map.has_key?(valid_fields, field_atom) do
      output_name = format_output_field(field_atom, formatter)
      {:ok, {field_atom, output_name}}
    else
      {:error, {:unknown_map_field, field_atom}}
    end
  end

  defp normalize_and_validate_map_field(field, valid_fields, formatter) when is_atom(field) do
    if Map.has_key?(valid_fields, field) do
      output_name = format_output_field(field, formatter)
      {:ok, {field, output_name}}
    else
      {:error, {:unknown_map_field, field}}
    end
  end

  defp normalize_and_validate_map_field(field, _valid_fields, _formatter) do
    {:error, {:invalid_map_field_format, field}}
  end

  # Process a list of fields recursively
  defp process_fields(fields, resource, formatter, field_maps) do
    initial_acc = {[], [], ExtractionTemplate.new()}
    
    result = Enum.reduce_while(fields, {:ok, initial_acc}, fn field, {:ok, {select_acc, load_acc, template_acc}} ->
      case process_single_field(field, resource, formatter, field_maps) do
        {:ok, {select_items, load_items, new_template}} ->
          new_acc = {
            select_acc ++ select_items,
            load_acc ++ load_items,
            Map.merge(template_acc, new_template)
          }
          {:cont, {:ok, new_acc}}
          
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    
    case result do
      {:ok, {select, load, template}} ->
        {:ok, {select, load, template}}
        
      error ->
        error
    end
  end

  # Process a single field (atom or tuple)
  defp process_single_field(field_atom, resource, formatter, field_maps) when is_atom(field_atom) do
    output_name = format_output_field(field_atom, formatter)
    
    cond do
      # Check if it's an attribute
      attr = Map.get(field_maps.attributes, field_atom) ->
        instruction = ExtractionTemplate.extract_field_with_spec(field_atom, attr)
        template = ExtractionTemplate.put_instruction(%{}, output_name, instruction)
        {:ok, {[field_atom], [], template}}
        
      # Check if it's a simple calculation (no args)
      calc = Map.get(field_maps.calculations, field_atom) ->
        if length(calc.arguments) == 0 do
          instruction = ExtractionTemplate.extract_field(field_atom)
          template = ExtractionTemplate.put_instruction(%{}, output_name, instruction)
          {:ok, {[], [field_atom], template}}
        else
          {:error, {:calculation_requires_args, field_atom}}
        end
        
      # Check if it's an aggregate
      Map.has_key?(field_maps.aggregates, field_atom) ->
        instruction = ExtractionTemplate.extract_field(field_atom)
        template = ExtractionTemplate.put_instruction(%{}, output_name, instruction)
        {:ok, {[], [field_atom], template}}
        
      # Check if it's a relationship (without nested fields)
      Map.has_key?(field_maps.relationships, field_atom) ->
        instruction = ExtractionTemplate.extract_field(field_atom)
        template = ExtractionTemplate.put_instruction(%{}, output_name, instruction)
        {:ok, {[], [field_atom], template}}
        
      # Unknown field
      true ->
        {:error, {:unknown_field, field_atom, resource}}
    end
  end

  defp process_single_field({field_atom, nested_spec}, resource, formatter, field_maps) when is_atom(field_atom) do
    output_name = format_output_field(field_atom, formatter)
    
    cond do
      # Relationship with nested fields
      rel = Map.get(field_maps.relationships, field_atom) ->
        process_relationship_field(field_atom, output_name, rel, nested_spec, formatter)
        
      # Calculation with args/fields
      calc = Map.get(field_maps.calculations, field_atom) ->
        process_calculation_field(field_atom, output_name, calc, nested_spec, resource, formatter)
        
      # Embedded resource
      attr = Map.get(field_maps.attributes, field_atom) ->
        if embedded_resource?(attr.type) do
          process_embedded_field(field_atom, output_name, attr, nested_spec, formatter)
        else
          {:error, {:field_does_not_support_nesting, field_atom}}
        end
        
      # Unknown field
      true ->
        {:error, {:unknown_field, field_atom, resource}}
    end
  end

  defp process_single_field(invalid_field, resource, _formatter, _field_maps) do
    {:error, {:invalid_field_format, invalid_field, resource}}
  end

  # Process a relationship field with nested field selection
  defp process_relationship_field(field_atom, output_name, relationship, nested_fields, formatter) when is_list(nested_fields) do
    # Recursively process nested fields for the related resource
    case build_statements_for_resource(relationship.destination, nested_fields, formatter) do
      {:ok, {nested_select, nested_load, nested_template}} ->
        # Combine select and load for the relationship load statement
        combined_fields = nested_select ++ nested_load
        load_statement = {field_atom, combined_fields}
        instruction = ExtractionTemplate.nested_field(field_atom, nested_template)
        template = ExtractionTemplate.put_instruction(%{}, output_name, instruction)
        {:ok, {[], [load_statement], template}}
        
      {:error, reason} ->
        {:error, {:nested_field_error, field_atom, reason}}
    end
  end

  defp process_relationship_field(field_atom, _output_name, _relationship, nested_spec, _formatter) do
    {:error, {:invalid_relationship_spec, field_atom, nested_spec}}
  end

  # Process a calculation field with arguments or nested fields
  defp process_calculation_field(field_atom, output_name, calculation, nested_spec, resource, formatter) when is_map(nested_spec) do
    cond do
      # Calculation with args and fields
      Map.has_key?(nested_spec, :args) and Map.has_key?(nested_spec, :fields) ->
        args = Map.get(nested_spec, :args)
        fields = Map.get(nested_spec, :fields)
        
        # Validate args is a map
        unless is_map(args) do
          {:error, {:invalid_calculation_args, field_atom, args}}
        else
          # Get the calculation return type
          target_resource = get_calculation_return_resource(calculation, resource)
          
          # Process the nested fields
          case build_statements_for_resource(target_resource, fields, formatter) do
            {:ok, {nested_select, nested_load, nested_template}} ->
              combined_fields = nested_select ++ nested_load
              load_statement = {field_atom, {args, combined_fields}}
              instruction = ExtractionTemplate.calc_result_field(field_atom, nested_template)
              template = ExtractionTemplate.put_instruction(%{}, output_name, instruction)
              {:ok, {[], [load_statement], template}}
              
            {:error, reason} ->
              {:error, {:calculation_field_error, field_atom, reason}}
          end
        end
        
      # Calculation with only args
      Map.has_key?(nested_spec, :args) ->
        args = Map.get(nested_spec, :args)
        unless is_map(args) do
          {:error, {:invalid_calculation_args, field_atom, args}}
        else
          load_statement = {field_atom, args}
          instruction = ExtractionTemplate.extract_field(field_atom)
          template = ExtractionTemplate.put_instruction(%{}, output_name, instruction)
          {:ok, {[], [load_statement], template}}
        end
        
      # Invalid spec
      true ->
        {:error, {:invalid_calculation_spec, field_atom, nested_spec}}
    end
  end

  defp process_calculation_field(field_atom, _output_name, _calculation, _nested_fields, _resource, _formatter) when is_list(_nested_fields) do
    # Calculation with field selection but no args (only valid for calculations that return resources)
    # For now, treat it as an error since we need args
    {:error, {:calculation_requires_args, field_atom}}
  end

  defp process_calculation_field(field_atom, _output_name, _calculation, nested_spec, _resource, _formatter) do
    {:error, {:invalid_calculation_spec, field_atom, nested_spec}}
  end

  # Process an embedded resource field
  defp process_embedded_field(field_atom, output_name, attribute, nested_fields, formatter) when is_list(nested_fields) do
    embedded_module = get_embedded_module(attribute.type)
    
    case build_statements_for_resource(embedded_module, nested_fields, formatter) do
      {:ok, {_nested_select, nested_load, nested_template}} ->
        # For embedded resources, we need both select and potentially load
        instruction = ExtractionTemplate.nested_field(field_atom, nested_template)
        template = ExtractionTemplate.put_instruction(%{}, output_name, instruction)
        
        if nested_load == [] do
          # Just select the field
          {:ok, {[field_atom], [], template}}
        else
          # Need both select and load
          load_statement = {field_atom, nested_load}
          {:ok, {[field_atom], [load_statement], template}}
        end
        
      {:error, reason} ->
        {:error, {:embedded_field_error, field_atom, reason}}
    end
  end

  defp process_embedded_field(field_atom, _output_name, _attribute, nested_spec, _formatter) do
    {:error, {:invalid_embedded_spec, field_atom, nested_spec}}
  end

  # Helper to check if a type is an embedded resource
  defp embedded_resource?(type) do
    case type do
      module when is_atom(module) ->
        ash_resource?(module)
        
      {:array, module} when is_atom(module) ->
        ash_resource?(module)
        
      _ ->
        false
    end
  end

  # Get the embedded module from a type
  defp get_embedded_module(type) do
    case type do
      module when is_atom(module) -> module
      {:array, module} when is_atom(module) -> module
      _ -> nil
    end
  end

  # Get the return resource for a calculation
  defp get_calculation_return_resource(calculation, default_resource) do
    # Try to determine the calculation's return type
    case calculation.type do
      Ash.Type.Struct ->
        # Check for instance_of constraint
        case calculation.constraints[:instance_of] do
          nil -> default_resource
          module when is_atom(module) -> module
          _ -> default_resource
        end
        
      module when is_atom(module) ->
        if ash_resource?(module) do
          module
        else
          default_resource
        end
        
      _ ->
        default_resource
    end
  end

  # Format field name for output
  defp format_output_field(field_atom, formatter) do
    field_string = Atom.to_string(field_atom)
    FieldFormatter.format_field(field_string, formatter)
  end
end