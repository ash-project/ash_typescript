defmodule AshTypescript.Rpc.ErrorBuilder do
  @moduledoc """
  Comprehensive error handling and message generation for the new RPC pipeline.

  Provides clear, actionable error messages for all failure modes with
  detailed context for debugging and client consumption.
  """

  @doc """
  Builds a detailed error response from various error types.

  Converts internal error tuples into structured error responses
  with clear messages and debugging context.
  """
  @spec build_error_response(term()) :: map()
  def build_error_response(error) do
    case error do
      # Action discovery errors
      {:action_not_found, action_name} ->
        %{
          type: "action_not_found",
          message: "RPC action '#{action_name}' not found",
          details: %{
            action_name: action_name,
            suggestion: "Check that the action is properly configured in your domain's rpc block"
          }
        }

      # Tenant resolution errors
      {:tenant_required, resource} ->
        suggestion =
          if AshTypescript.Rpc.require_tenant_parameters?() do
            "Add a 'tenant' parameter to your request, or set config :ash_typescript, require_tenant_parameters: false if the tenant will be added to the conn assigns in other ways."
          else
            "Make sure your request pipeline is properly setting a tenant in the conn assigns, or set config :ash_typescript, require_tenant_parameters: true to generate tenant parameters for multitenant resource actions."
          end

        %{
          type: "tenant_required",
          message: "Tenant parameter is required for multitenant resource #{inspect(resource)}",
          details: %{
            resource: inspect(resource),
            suggestion: "Add a 'tenant' parameter to your request"
          }
        }

      # Field validation errors (nested tuple format)
      {:invalid_fields, field_error} ->
        build_error_response(field_error)

      # Direct field error from RequestedFieldsProcessor
      %{type: :invalid_field, field: field_name} ->
        %{
          type: "invalid_field",
          message: "Invalid field '#{field_name}'",
          field: field_name
        }

      # === FIELD VALIDATION ERRORS WITH FIELD PATHS ===

      # Unknown field errors
      {:unknown_field, _field_atom, "map", field_path} ->
        %{
          type: "unknown_map_field",
          message: "Unknown field '#{field_path}' for map return type",
          field_path: field_path,
          details: %{
            field: field_path,
            suggestion: "Check that the field name is valid for the map's field constraints"
          }
        }

      {:unknown_field, _field_atom, "typed_struct", field_path} ->
        %{
          type: "unknown_typed_struct_field",
          message: "Unknown field '#{field_path}' for typed struct",
          field_path: field_path,
          details: %{
            field: field_path,
            suggestion: "Check that the field name is valid for the typed struct definition"
          }
        }

      {:unknown_field, _field_atom, "union_attribute", field_path} ->
        %{
          type: "unknown_union_field",
          message: "Unknown union member '#{field_path}'",
          field_path: field_path,
          details: %{
            field: field_path,
            suggestion:
              "Check that the union member name is valid for the union attribute definition"
          }
        }

      {:unknown_field, _field_atom, resource, field_path} ->
        %{
          type: "unknown_field",
          message: "Unknown field '#{field_path}' for resource #{inspect(resource)}",
          field_path: field_path,
          details: %{
            field: field_path,
            resource: inspect(resource),
            suggestion:
              "Check the field name spelling and ensure it's a public attribute, calculation, or relationship"
          }
        }

      # Calculation errors
      {:calculation_requires_args, field_atom, field_path} ->
        %{
          type: "invalid_field_format",
          message: "Calculation '#{field_path}' requires arguments",
          field_path: field_path,
          details: %{
            field: field_path,
            suggestion: "Provide arguments in the format: {\"#{field_atom}\": {\"args\": {...}}}"
          }
        }

      {:invalid_calculation_args, _field_atom, field_path} ->
        %{
          type: "invalid_calculation_args",
          message: "Invalid arguments for calculation '#{field_path}'",
          field_path: field_path,
          details: %{
            field: field_path,
            expected: "Map containing argument values or valid field selection format"
          }
        }

      # Field selection requirement errors
      {:requires_field_selection, field_type, field_path} ->
        %{
          type: "requires_field_selection",
          message:
            "#{String.capitalize(to_string(field_type))} '#{field_path}' requires field selection",
          field_path: field_path,
          details: %{
            field_type: field_type,
            field: field_path,
            suggestion: "Specify which fields to select from this #{field_type}"
          }
        }

      {:invalid_field_selection, _field_atom, field_type, field_path} ->
        field_type_string = format_field_type(field_type)
        %{
          type: "invalid_field_selection",
          message: "Cannot select fields from #{field_type_string} '#{field_path}'",
          field_path: field_path,
          details: %{
            field: field_path,
            field_type: field_type_string,
            suggestion: "Remove the field selection for this #{field_type_string} field"
          }
        }

      {:invalid_field_selection, :primitive_type, return_type} ->
        return_type_string = format_field_type(return_type)
        %{
          type: "invalid_field_selection",
          message: "Cannot select fields from primitive type #{return_type_string}",
          details: %{
            field_type: "primitive_type",
            return_type: return_type_string,
            suggestion: "Remove the field selection for this primitive type"
          }
        }

      {:invalid_field_selection, field_type, field_path} ->
        field_type_string = format_field_type(field_type)
        field_path_string = format_field_type(field_path)
        %{
          type: "invalid_field_selection",
          message: "Cannot select fields from #{field_type_string} '#{field_path_string}'",
          field_path: field_path_string,
          details: %{
            field_type: field_type_string,
            suggestion: "Remove the field selection for this #{field_type_string} field"
          }
        }

      # Field nesting errors
      {:field_does_not_support_nesting, field_path} ->
        %{
          type: "field_does_not_support_nesting",
          message: "Field '#{field_path}' does not support nested field selection",
          field_path: field_path,
          details: %{
            field: field_path,
            suggestion: "Remove the nested specification for this field"
          }
        }

      # Duplicate field errors
      {:duplicate_field, _field_atom, field_path} ->
        %{
          type: "duplicate_field",
          message: "Field '#{field_path}' was requested multiple times",
          field_path: field_path,
          details: %{
            field: field_path,
            suggestion: "Remove duplicate field specifications"
          }
        }

      # Field combination errors
      {:unsupported_field_combination, field_type, _field_atom, field_spec, field_path} ->
        %{
          type: "unsupported_field_combination",
          message: "Unsupported combination of field type and specification for '#{field_path}'",
          field_path: field_path,
          details: %{
            field: field_path,
            field_type: field_type,
            field_spec: inspect(field_spec),
            suggestion: "Check the documentation for valid field specification formats"
          }
        }

      # === LEGACY FIELD VALIDATION ERRORS (WITHOUT FIELD PATHS) ===

      {:invalid_field_format, invalid_format} ->
        %{
          type: "invalid_field_format",
          message: "Invalid field specification format",
          details: %{
            received: inspect(invalid_format),
            expected: "String field name or map with single key-value pair"
          }
        }

      {:unsupported_field_format, field} ->
        %{
          type: "unsupported_field_format",
          message: "Unsupported field specification format",
          details: %{
            received: inspect(field),
            supported_formats: ["string", "map with single entry"]
          }
        }

      {:invalid_fields_type, fields} ->
        %{
          type: "invalid_fields_type",
          message: "Fields parameter must be an array",
          details: %{
            received: inspect(fields),
            expected_type: "array",
            suggestion: "Wrap field names in an array, e.g., [\"field1\", \"field2\"]"
          }
        }

      {:simple_attribute_with_spec, field_atom, field_spec} ->
        %{
          type: "simple_attribute_with_spec",
          message: "Simple attribute '#{field_atom}' cannot have field specification",
          details: %{
            field:
              AshTypescript.FieldFormatter.format_field(
                field_atom,
                AshTypescript.Rpc.output_field_formatter()
              ),
            received_spec: inspect(field_spec),
            suggestion: "Remove the field specification or use just the field name"
          }
        }

      {:simple_calculation_with_spec, field_atom, field_spec} ->
        %{
          type: "simple_calculation_with_spec",
          message: "Simple calculation '#{field_atom}' cannot have field specification",
          details: %{
            field:
              AshTypescript.FieldFormatter.format_field(
                field_atom,
                AshTypescript.Rpc.output_field_formatter()
              ),
            received_spec: inspect(field_spec),
            suggestion: "Remove the field specification or use just the field name"
          }
        }

      {:invalid_calculation_spec, field_atom, invalid_spec} ->
        %{
          type: "invalid_calculation_spec",
          message: "Invalid calculation specification for '#{field_atom}'",
          details: %{
            field:
              AshTypescript.FieldFormatter.format_field(
                field_atom,
                AshTypescript.Rpc.output_field_formatter()
              ),
            received: inspect(invalid_spec),
            expected: "Map with 'args' key and optional 'fields' key"
          }
        }

      {:relationship_field_error, field_atom, nested_error} ->
        %{
          type: "relationship_field_error",
          message: "Error in relationship field '#{field_atom}'",
          details: %{
            field:
              AshTypescript.FieldFormatter.format_field(
                field_atom,
                AshTypescript.Rpc.output_field_formatter()
              ),
            nested_error: build_error_response(nested_error)
          }
        }

      {:embedded_resource_field_error, field_atom, nested_error} ->
        %{
          type: "embedded_resource_field_error",
          message: "Error in embedded resource field '#{field_atom}'",
          details: %{
            field:
              AshTypescript.FieldFormatter.format_field(
                field_atom,
                AshTypescript.Rpc.output_field_formatter()
              ),
            nested_error: build_error_response(nested_error)
          }
        }

      {:embedded_resource_module_not_found, field_atom} ->
        %{
          type: "embedded_resource_module_not_found",
          message: "Embedded resource module not found for field '#{field_atom}'",
          details: %{
            field:
              AshTypescript.FieldFormatter.format_field(
                field_atom,
                AshTypescript.Rpc.output_field_formatter()
              ),
            suggestion: "Ensure the field is properly configured as an embedded resource"
          }
        }

      {:field_normalization_error, exception} ->
        %{
          type: "field_normalization_error",
          message: "Error normalizing field format: #{Exception.message(exception)}",
          details: %{
            error: Exception.message(exception),
            suggestion: "Check that all fields are strings or valid field specifications"
          }
        }

      {:calculation_field_error, field_atom, nested_error} ->
        %{
          type: "calculation_field_error",
          message: "Error in calculation field '#{field_atom}'",
          details: %{
            field:
              AshTypescript.FieldFormatter.format_field(
                field_atom,
                AshTypescript.Rpc.output_field_formatter()
              ),
            nested_error: build_error_response(nested_error)
          }
        }

      {:nested_field_error, field_atom, nested_error} ->
        %{
          type: "relationship_field_error",
          message: "Error in relationship field '#{field_atom}'",
          details: %{
            field:
              AshTypescript.FieldFormatter.format_field(
                field_atom,
                AshTypescript.Rpc.output_field_formatter()
              ),
            nested_error: build_error_response(nested_error)
          }
        }

      {:fields_not_allowed, message} ->
        %{
          type: "fields_not_allowed",
          message: message,
          details: %{
            suggestion: "Remove the fields parameter for actions with primitive return types"
          }
        }

      {:invalid_field_format, field, resource} ->
        %{
          type: "invalid_field_format",
          message: "Invalid field format '#{inspect(field)}' for resource #{inspect(resource)}",
          details: %{
            field: inspect(field),
            resource: inspect(resource),
            expected: "String field name or map with single key-value pair"
          }
        }

      {:invalid_relationship_spec, field_atom, spec} ->
        %{
          type: "invalid_relationship_spec",
          message: "Invalid relationship specification for '#{field_atom}'",
          details: %{
            field:
              AshTypescript.FieldFormatter.format_field(
                field_atom,
                AshTypescript.Rpc.output_field_formatter()
              ),
            received: inspect(spec),
            expected: "List of field names for relationship field selection"
          }
        }

      {:invalid_embedded_spec, field_atom, spec} ->
        %{
          type: "invalid_embedded_spec",
          message: "Invalid embedded resource specification for '#{field_atom}'",
          details: %{
            field:
              AshTypescript.FieldFormatter.format_field(
                field_atom,
                AshTypescript.Rpc.output_field_formatter()
              ),
            received: inspect(spec),
            expected: "List of field names for embedded resource field selection"
          }
        }

      {:invalid_map_field_format, field} ->
        %{
          type: "invalid_map_field_format",
          message: "Invalid field format for map field selection",
          details: %{
            received: inspect(field),
            expected: "String field name or atom for map field selection"
          }
        }

      # === INPUT AND SYSTEM VALIDATION ERRORS ===

      {:missing_required_parameter, parameter} ->
        %{
          type: "missing_required_parameter",
          message: "Required parameter '#{parameter}' is missing or empty",
          details: %{
            parameter: parameter,
            suggestion: "Ensure '#{parameter}' parameter is provided and not empty"
          }
        }

      {:empty_fields_array, _fields} ->
        %{
          type: "empty_fields_array",
          message: "Fields array cannot be empty",
          details: %{
            suggestion: "Provide at least one field name in the fields array"
          }
        }

      {:invalid_pagination_type, parameter, value} ->
        %{
          type: "invalid_pagination_type",
          message: "Invalid data type for pagination parameter '#{parameter}'",
          details: %{
            parameter: parameter,
            received: inspect(value),
            expected: "Integer",
            suggestion: "Provide an integer value for #{parameter}"
          }
        }

      {:invalid_pagination_value, parameter, value, constraint} ->
        %{
          type: "invalid_pagination_value",
          message: "Invalid value for pagination parameter '#{parameter}': #{constraint}",
          details: %{
            parameter: parameter,
            received: value,
            constraint: constraint,
            suggestion: "Ensure #{parameter} meets the constraint: #{constraint}"
          }
        }

      {:invalid_input_format, invalid_input} ->
        %{
          type: "invalid_input_format",
          message: "Input parameter must be a map",
          details: %{
            received: inspect(invalid_input),
            expected: "Map containing input parameters"
          }
        }

      {:invalid_pagination, invalid_value} ->
        %{
          type: "invalid_pagination",
          message: "Invalid pagination parameter format",
          details: %{
            received: inspect(invalid_value),
            expected: "Map with pagination parameters (limit, offset, before, after, etc.)"
          }
        }

      # === ASH FRAMEWORK ERRORS ===

      # NotFound errors (specific handling)
      %Ash.Error.Query.NotFound{} = not_found_error ->
        %{
          type: "not_found",
          message: Exception.message(not_found_error),
          details: %{
            resource: not_found_error.resource,
            primary_key: not_found_error.primary_key
          }
        }

      # Check for NotFound errors nested inside other Ash errors
      %{class: :invalid, errors: errors} = ash_error when is_list(errors) ->
        case Enum.find(errors, &is_struct(&1, Ash.Error.Query.NotFound)) do
          %Ash.Error.Query.NotFound{} = not_found_error ->
            %{
              type: "not_found",
              message: Exception.message(not_found_error),
              details: %{
                resource: not_found_error.resource,
                primary_key: not_found_error.primary_key
              }
            }

          _ ->
            build_ash_error_response(ash_error)
        end

      # Generic Ash errors
      %{class: _class} = ash_error ->
        build_ash_error_response(ash_error)

      # === FALLBACK ERROR HANDLERS ===

      {field_error_type, _} when is_atom(field_error_type) ->
        %{
          type: "field_validation_error",
          message: "Field validation error: #{field_error_type}",
          details: %{
            error: inspect(error)
          }
        }

      other ->
        %{
          type: "unknown_error",
          message: "An unexpected error occurred",
          details: %{
            error: inspect(other)
          }
        }
    end
  end

  # Build error responses for Ash framework errors
  defp build_ash_error_response(ash_error) when is_exception(ash_error) do
    %{
      type: "ash_error",
      message: Exception.message(ash_error),
      details: %{
        class: ash_error.class,
        errors: serialize_nested_errors(ash_error.errors || []),
        path: ash_error.path || []
      }
    }
  end

  defp build_ash_error_response(ash_error) do
    %{
      type: "ash_error",
      message: inspect(ash_error),
      details: %{
        error: inspect(ash_error)
      }
    }
  end

  defp serialize_nested_errors(errors) when is_list(errors) do
    Enum.map(errors, &serialize_single_error/1)
  end

  defp serialize_single_error(error) when is_exception(error) do
    %{
      message: Exception.message(error),
      field: Map.get(error, :field),
      fields: Map.get(error, :fields, []),
      path: Map.get(error, :path, [])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp serialize_single_error(error) do
    %{message: inspect(error)}
  end

  # Format field type for error messages
  defp format_field_type(:primitive_type), do: "primitive type"
  defp format_field_type({:ash_type, type, _}), do: "#{inspect(type)}"
  defp format_field_type(other), do: "#{inspect(other)}"
end
