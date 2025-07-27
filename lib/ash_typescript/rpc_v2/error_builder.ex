defmodule AshTypescript.RpcV2.ErrorBuilder do
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
        %{
          type: "tenant_required", 
          message: "Tenant parameter is required for multitenant resource #{inspect(resource)}",
          details: %{
            resource: inspect(resource),
            suggestion: "Add a 'tenant' parameter to your request"
          }
        }

      # Field validation errors
      {:invalid_fields, field_error} ->
        build_field_error_response(field_error)

      # Pagination errors
      {:invalid_pagination, invalid_value} ->
        %{
          type: "invalid_pagination",
          message: "Invalid pagination parameter format",
          details: %{
            received: inspect(invalid_value),
            expected: "Map with pagination parameters (limit, offset, before, after, etc.)"
          }
        }

      # Generic Ash errors
      %{class: _class} = ash_error ->
        build_ash_error_response(ash_error)

      # Unknown errors
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

  # Build detailed error responses for field validation errors
  defp build_field_error_response(field_error) do
    case field_error do
      {:unknown_field, field_atom, resource} ->
        %{
          type: "unknown_field",
          message: "Unknown field '#{field_atom}' for resource #{inspect(resource)}",
          details: %{
            field: to_string(field_atom),
            resource: inspect(resource),
            suggestion: "Check the field name spelling and ensure it's a public attribute, calculation, or relationship"
          }
        }

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

      {:simple_attribute_with_spec, field_atom, field_spec} ->
        %{
          type: "simple_attribute_with_spec",
          message: "Simple attribute '#{field_atom}' cannot have field specification",
          details: %{
            field: to_string(field_atom),
            received_spec: inspect(field_spec),
            suggestion: "Remove the field specification or use just the field name"
          }
        }

      {:simple_calculation_with_spec, field_atom, field_spec} ->
        %{
          type: "simple_calculation_with_spec",
          message: "Simple calculation '#{field_atom}' cannot have field specification",
          details: %{
            field: to_string(field_atom),
            received_spec: inspect(field_spec),
            suggestion: "Remove the field specification or use just the field name"
          }
        }

      {:invalid_calculation_spec, field_atom, invalid_spec} ->
        %{
          type: "invalid_calculation_spec",
          message: "Invalid calculation specification for '#{field_atom}'",
          details: %{
            field: to_string(field_atom),
            received: inspect(invalid_spec),
            expected: "Map with 'args' key and optional 'fields' key"
          }
        }

      {:relationship_field_error, field_atom, nested_error} ->
        %{
          type: "relationship_field_error",
          message: "Error in relationship field '#{field_atom}'",
          details: %{
            field: to_string(field_atom),
            nested_error: build_field_error_response(nested_error)
          }
        }

      {:embedded_resource_field_error, field_atom, nested_error} ->
        %{
          type: "embedded_resource_field_error",
          message: "Error in embedded resource field '#{field_atom}'",
          details: %{
            field: to_string(field_atom),
            nested_error: build_field_error_response(nested_error)
          }
        }

      {:embedded_resource_module_not_found, field_atom} ->
        %{
          type: "embedded_resource_module_not_found",
          message: "Embedded resource module not found for field '#{field_atom}'",
          details: %{
            field: to_string(field_atom),
            suggestion: "Ensure the field is properly configured as an embedded resource"
          }
        }

      {:unsupported_field_combination, field_type, field_atom, field_spec} ->
        %{
          type: "unsupported_field_combination",
          message: "Unsupported combination of field type and specification",
          details: %{
            field: to_string(field_atom),
            field_type: field_type,
            field_spec: inspect(field_spec),
            suggestion: "Check the documentation for valid field specification formats"
          }
        }

      other ->
        %{
          type: "field_validation_error",
          message: "Field validation error",
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

  # Serialize nested Ash errors
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
end