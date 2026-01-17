# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ErrorBuilder do
  @moduledoc """
  Comprehensive error handling and message generation for the new RPC pipeline.

  Provides clear, actionable error messages for all failure modes with
  detailed context for debugging and client consumption.
  """

  alias AshTypescript.Rpc.Errors

  @stale_generated_file_hint "This error is most likely happening because the generated typescript file used is not up to date with the running backend. Check that you are using the latest generated file, and/or that a new file has been generated after the last backend changes."

  @doc """
  Builds a detailed error response from various error types.

  Converts internal error tuples into structured error responses
  with clear messages and debugging context.

  For Ash framework errors, uses the new Error protocol for standardized extraction.

  Returns either a single error map or a list of error maps (for Ash errors with multiple sub-errors).
  """
  @spec build_error_response(term()) :: map() | list(map())
  def build_error_response(error) do
    case error do
      # Action discovery errors
      {:action_not_found, action_name} ->
        %{
          type: "action_not_found",
          message: "RPC action %{action_name} not found",
          short_message: "Action not found",
          vars: %{action_name: action_name},
          path: [],
          fields: [],
          details: %{
            suggestion: "Check that the action is properly configured in your domain's rpc block",
            hint: @stale_generated_file_hint
          }
        }

      # Tenant resolution errors
      {:tenant_required, resource} ->
        %{
          type: "tenant_required",
          message: "Tenant parameter is required for multitenant resource %{resource}",
          short_message: "Tenant required",
          vars: %{resource: inspect(resource)},
          path: [],
          fields: [],
          details: %{
            suggestion: "Add a 'tenant' parameter to your request",
            hint: @stale_generated_file_hint
          }
        }

      # Field validation errors (nested tuple format)
      {:invalid_fields, field_error} ->
        build_error_response(field_error)

      # === FIELD VALIDATION ERRORS WITH FIELD PATHS ===

      # Unknown field errors - now accepts raw path instead of formatted field_path
      {:unknown_field, field_atom, "map", path} when is_list(path) ->
        full_field_path = build_complete_field_path(path, field_atom)
        formatted_path = format_path(path)

        %{
          type: "unknown_map_field",
          message: "Unknown field %{field} for map return type",
          short_message: "Unknown map field",
          vars: %{field: full_field_path},
          path: formatted_path,
          fields: [full_field_path],
          details: %{
            suggestion: "Check that the field name is valid for the map's field constraints",
            hint: @stale_generated_file_hint
          }
        }

      {:unknown_field, field_atom, "union_attribute", path} when is_list(path) ->
        full_field_path = build_complete_field_path(path, field_atom)
        formatted_path = format_path(path)

        %{
          type: "unknown_union_field",
          message: "Unknown union member %{field}",
          short_message: "Unknown union member",
          vars: %{field: full_field_path},
          path: formatted_path,
          fields: [full_field_path],
          details: %{
            suggestion:
              "Check that the union member name is valid for the union attribute definition",
            hint: @stale_generated_file_hint
          }
        }

      {:unknown_field, field_atom, resource, path} when is_list(path) ->
        full_field_path = build_complete_field_path(path, field_atom)
        formatted_path = format_path(path)

        %{
          type: "unknown_field",
          message: "Unknown field %{field} for resource %{resource}",
          short_message: "Unknown field",
          vars: %{field: full_field_path, resource: inspect(resource)},
          path: formatted_path,
          fields: [full_field_path],
          details: %{
            suggestion:
              "Check the field name spelling and ensure it's a public attribute, calculation, or relationship",
            hint: @stale_generated_file_hint
          }
        }

      # Calculation errors - now accepts raw path
      {:calculation_requires_args, field_atom, path} when is_list(path) ->
        full_field_path = build_complete_field_path(path, field_atom)
        formatted_path = format_path(path)

        %{
          type: "invalid_field_format",
          message: "Calculation %{field} requires arguments",
          short_message: "Calculation requires arguments",
          vars: %{field: full_field_path},
          path: formatted_path,
          fields: [full_field_path],
          details: %{
            suggestion: "Provide arguments in the format: {\"#{field_atom}\": {\"args\": {...}}}",
            hint: @stale_generated_file_hint
          }
        }

      {:invalid_calculation_args, field_atom, path} when is_list(path) ->
        full_field_path = build_complete_field_path(path, field_atom)
        formatted_path = format_path(path)

        %{
          type: "invalid_calculation_args",
          message: "Invalid arguments for calculation %{field}",
          short_message: "Invalid calculation arguments",
          vars: %{field: full_field_path},
          path: formatted_path,
          fields: [full_field_path],
          details: %{
            expected: "Map containing argument values or valid field selection format",
            hint: @stale_generated_file_hint
          }
        }

      # Field selection requirement errors - accepts raw path and field_name
      {:requires_field_selection, field_type, field_name, path}
      when is_list(path) and is_atom(field_name) ->
        full_field_path = build_complete_field_path(path, field_name)
        formatted_path = format_path(path)

        %{
          type: "requires_field_selection",
          message: "%{field_type} %{field} requires field selection",
          short_message: "Field selection required",
          vars: %{
            field_type: String.capitalize(to_string(field_type)),
            field: full_field_path
          },
          path: formatted_path,
          fields: [full_field_path],
          details: %{
            suggestion: "Specify which fields to select from this #{field_type}",
            hint: @stale_generated_file_hint
          }
        }

      # Legacy pattern for requires_field_selection with nil field
      {:requires_field_selection, field_type, nil} ->
        %{
          type: "requires_field_selection",
          message: "%{field_type} requires field selection",
          short_message: "Field selection required",
          vars: %{
            field_type: String.capitalize(to_string(field_type))
          },
          path: [],
          fields: [],
          details: %{
            suggestion: "Specify which fields to select from this #{field_type}",
            hint: @stale_generated_file_hint
          }
        }

      {:invalid_field_selection, field_atom, field_type, path} when is_list(path) ->
        field_type_string = format_field_type(field_type)
        full_field_path = build_complete_field_path(path, field_atom)
        formatted_path = format_path(path)

        %{
          type: "invalid_field_selection",
          message: "Cannot select fields from %{field_type} %{field}",
          short_message: "Invalid field selection",
          vars: %{field_type: field_type_string, field: full_field_path},
          path: formatted_path,
          fields: [full_field_path],
          details: %{
            suggestion: "Remove the field selection for this #{field_type_string} field",
            hint: @stale_generated_file_hint
          }
        }

      {:invalid_field_selection, :primitive_type, return_type, requested_fields, path} ->
        return_type_string = format_field_type(return_type)

        %{
          type: "invalid_field_selection",
          message: "Cannot select fields from primitive type %{return_type}",
          short_message: "Invalid field selection",
          vars: %{return_type: return_type_string},
          path: format_path(path),
          fields: [],
          details: %{
            requested_fields: requested_fields,
            suggestion: "Remove the field selection for this primitive type",
            hint: @stale_generated_file_hint
          }
        }

      {:invalid_field_selection, field_type, field_path} ->
        field_type_string = format_field_type(field_type)
        field_path_string = format_field_type(field_path)

        %{
          type: "invalid_field_selection",
          message: "Cannot select fields from %{field_type} %{field}",
          short_message: "Invalid field selection",
          vars: %{field_type: field_type_string, field: field_path_string},
          path: parse_field_path_to_formatted_path(field_path_string),
          fields: [field_path_string],
          details: %{
            suggestion: "Remove the field selection for this #{field_type_string} field",
            hint: @stale_generated_file_hint
          }
        }

      # Field nesting errors - now accepts raw path
      {:field_does_not_support_nesting, field_name, path} when is_list(path) ->
        full_field_path = build_complete_field_path(path, field_name)
        formatted_path = format_path(path)

        %{
          type: "field_does_not_support_nesting",
          message: "Field %{field} does not support nested field selection",
          short_message: "Field does not support nesting",
          vars: %{field: full_field_path},
          path: formatted_path,
          fields: [full_field_path],
          details: %{
            suggestion: "Remove the nested specification for this field",
            hint: @stale_generated_file_hint
          }
        }

      # Duplicate field errors - now accepts raw path
      {:duplicate_field, field_atom, path} when is_list(path) ->
        full_field_path = build_complete_field_path(path, field_atom)
        formatted_path = format_path(path)

        %{
          type: "duplicate_field",
          message: "Field %{field} was requested multiple times",
          short_message: "Duplicate field",
          vars: %{field: full_field_path},
          path: formatted_path,
          fields: [full_field_path],
          details: %{
            suggestion: "Remove duplicate field specifications",
            hint: @stale_generated_file_hint
          }
        }

      # Field combination errors - now accepts raw path
      {:unsupported_field_combination, field_type, field_atom, field_spec, path}
      when is_list(path) ->
        full_field_path = build_complete_field_path(path, field_atom)
        formatted_path = format_path(path)

        %{
          type: "unsupported_field_combination",
          message: "Unsupported combination of field type and specification for %{field}",
          short_message: "Unsupported field combination",
          vars: %{field: full_field_path, field_type: to_string(field_type)},
          path: formatted_path,
          fields: [full_field_path],
          details: %{
            field_spec: inspect(field_spec),
            suggestion: "Check the documentation for valid field specification formats",
            hint: @stale_generated_file_hint
          }
        }

      # === LEGACY FIELD VALIDATION ERRORS (WITHOUT FIELD PATHS) ===

      {:invalid_fields_type, fields} ->
        %{
          type: "invalid_fields_type",
          message: "Fields parameter must be an array",
          short_message: "Invalid fields type",
          vars: %{received: inspect(fields)},
          path: [],
          fields: [],
          details: %{
            expected_code: "array",
            suggestion: "Wrap field names in an array, e.g., [\"field1\", \"field2\"]",
            hint: @stale_generated_file_hint
          }
        }

      # === UNION INPUT VALIDATION ERRORS ===

      {:invalid_union_input, :not_a_map} ->
        %{
          type: "invalid_union_input",
          message: "Union input must be a map with exactly one member key",
          short_message: "Invalid union input",
          vars: %{},
          path: [],
          fields: [],
          details: %{
            suggestion: "Provide union input in the format: {\"member_name\": value}",
            hint: @stale_generated_file_hint
          }
        }

      {:invalid_union_input, :no_member_key, member_names} ->
        %{
          type: "invalid_union_input",
          message: "Union input map does not contain any valid member key",
          short_message: "Invalid union input",
          vars: %{expected_members: Enum.join(member_names, ", ")},
          path: [],
          fields: [],
          details: %{
            expected_members: member_names,
            suggestion: "Provide exactly one of the following keys: %{expected_members}",
            hint: @stale_generated_file_hint
          }
        }

      {:invalid_union_input, :multiple_member_keys, found_keys, member_names} ->
        %{
          type: "invalid_union_input",
          message: "Union input map contains multiple member keys: %{found_keys}",
          short_message: "Invalid union input",
          vars: %{
            found_keys: Enum.join(found_keys, ", "),
            expected_members: Enum.join(member_names, ", ")
          },
          path: [],
          fields: [],
          details: %{
            suggestion:
              "Provide exactly one member key, not multiple. Choose one of: %{expected_members}",
            hint: @stale_generated_file_hint
          }
        }

      # === INPUT AND SYSTEM VALIDATION ERRORS ===

      {:missing_required_parameter, parameter} ->
        %{
          type: "missing_required_parameter",
          message: "Required parameter %{parameter} is missing or empty",
          short_message: "Missing required parameter",
          vars: %{parameter: to_string(parameter)},
          path: [],
          fields: [],
          details: %{
            suggestion: "Ensure %{parameter} parameter is provided and not empty",
            hint: @stale_generated_file_hint
          }
        }

      {:missing_get_by_fields, missing_fields} ->
        # Field names are already formatted by the pipeline
        field_names = Enum.join(missing_fields, ", ")

        %{
          type: "missing_required_input",
          message: "Required getBy fields are missing: %{fields}",
          short_message: "Missing required getBy fields",
          vars: %{fields: field_names},
          path: [:get_by],
          fields: missing_fields,
          details: %{
            suggestion: "Provide values for all required getBy fields",
            hint: @stale_generated_file_hint
          }
        }

      {:unexpected_get_by_fields, extra_fields, allowed_fields} ->
        # Field names are already formatted by the pipeline
        extra_field_names = Enum.join(extra_fields, ", ")
        allowed_field_names = Enum.join(allowed_fields, ", ")

        %{
          type: "unexpected_get_by_fields",
          message: "Unexpected getBy fields: %{extra_fields}. Allowed fields: %{allowed_fields}",
          short_message: "Unexpected getBy fields",
          vars: %{extra_fields: extra_field_names, allowed_fields: allowed_field_names},
          path: [:get_by],
          fields: extra_fields,
          details: %{
            allowed_fields: allowed_fields,
            suggestion: "Only provide the allowed getBy fields: %{allowed_fields}",
            hint: @stale_generated_file_hint
          }
        }

      {:empty_fields_array, _fields} ->
        %{
          type: "empty_fields_array",
          message: "Fields array cannot be empty",
          short_message: "Empty fields array",
          vars: %{},
          path: [],
          fields: [],
          details: %{
            suggestion: "Provide at least one field name in the fields array",
            hint: @stale_generated_file_hint
          }
        }

      # === LOAD RESTRICTION ERRORS ===

      {:load_not_allowed, disallowed_paths} ->
        paths_str = Enum.join(disallowed_paths, ", ")

        %{
          type: "load_not_allowed",
          message: "Loading the following fields is not allowed: %{fields}",
          short_message: "Load not allowed",
          vars: %{fields: paths_str},
          path: [],
          fields: disallowed_paths,
          details: %{
            disallowed_paths: disallowed_paths,
            suggestion:
              "Remove these fields from your request or check allowed_loads configuration",
            hint: @stale_generated_file_hint
          }
        }

      {:load_denied, denied_paths} ->
        paths_str = Enum.join(denied_paths, ", ")

        %{
          type: "load_denied",
          message: "Loading the following fields is denied: %{fields}",
          short_message: "Load denied",
          vars: %{fields: paths_str},
          path: [],
          fields: denied_paths,
          details: %{
            denied_paths: denied_paths,
            suggestion: "Remove these fields from your request",
            hint: @stale_generated_file_hint
          }
        }

      {:invalid_input_format, invalid_input} ->
        %{
          type: "invalid_input_format",
          message: "Input parameter must be a map",
          short_message: "Invalid input format",
          vars: %{received: inspect(invalid_input)},
          path: [],
          fields: [],
          details: %{
            expected: "Map containing input parameters",
            hint: @stale_generated_file_hint
          }
        }

      {:invalid_pagination, invalid_value} ->
        %{
          type: "invalid_pagination",
          message: "Invalid pagination parameter format",
          short_message: "Invalid pagination",
          vars: %{received: inspect(invalid_value)},
          path: [],
          fields: [],
          details: %{
            expected: "Map with pagination parameters (limit, offset, before, after, etc.)",
            hint: @stale_generated_file_hint
          }
        }

      # === IDENTITY VALIDATION ERRORS ===

      {:invalid_identity, %{provided_keys: provided_keys, expected_keys: expected_keys}} ->
        # Keys are already formatted for client display by the pipeline
        provided_keys_str = Enum.join(provided_keys, ", ")
        expected_keys_str = Enum.join(expected_keys, ", ")

        %{
          type: "invalid_identity",
          message:
            "Identity fields do not match any configured identity. Provided: [%{provided_keys}], expected: [%{expected_keys}]",
          short_message: "Invalid identity",
          vars: %{provided_keys: provided_keys_str, expected_keys: expected_keys_str},
          path: [:identity],
          fields: [],
          details: %{
            provided_keys: provided_keys,
            expected_keys: expected_keys,
            suggestion:
              "Provide all required fields for one of the configured identities: #{expected_keys_str}",
            hint: @stale_generated_file_hint
          }
        }

      {:invalid_identity, %{message: message}} ->
        %{
          type: "invalid_identity",
          message: message,
          short_message: "Invalid identity",
          vars: %{},
          path: [:identity],
          fields: [],
          details: %{
            suggestion: "Check the configured identities for this action",
            hint: @stale_generated_file_hint
          }
        }

      {:missing_identity, %{expected_keys: expected_keys, identities: identities}} ->
        expected_keys_str = Enum.join(expected_keys, ", ")

        # Check if the only identity is _primary_key with a single field
        # In this case, provide a simpler, clearer message
        {message, suggestion} =
          case {identities, expected_keys} do
            {[:_primary_key], [single_key]} ->
              {"Identity is required. Provide the #{single_key} value directly.",
               "Pass the #{single_key} value directly as the identity field (e.g., identity: \"your-#{single_key}-here\")"}

            _ ->
              {"Identity is required but not provided. Expected one of: [%{expected_keys}]",
               "Provide identity fields for one of the configured identities: #{expected_keys_str}"}
          end

        %{
          type: "missing_identity",
          message: message,
          short_message: "Missing identity",
          vars: %{expected_keys: expected_keys_str},
          path: [:identity],
          fields: [],
          details: %{
            expected_keys: expected_keys,
            suggestion: suggestion,
            hint: @stale_generated_file_hint
          }
        }

      # === ASH FRAMEWORK ERRORS ===

      # Any exception or Ash error - convert to Ash error class and process
      error when is_exception(error) or is_map(error) ->
        ash_error = Ash.Error.to_error_class(error)

        # Returns list directly - caller handles both single and multiple errors
        Errors.to_errors(ash_error)

      # === FALLBACK ERROR HANDLERS ===

      # Invalid field type errors (from validator throws)
      {:invalid_field_type, field_name, path} ->
        formatted_path = format_path(path)

        formatted_field =
          AshTypescript.FieldFormatter.format_field_name(
            to_string(field_name),
            AshTypescript.Rpc.output_field_formatter()
          )

        field_path = Enum.join(formatted_path ++ [formatted_field], ".")

        %{
          type: "unknown_field",
          message: "Unknown field %{field}",
          short_message: "Unknown field",
          vars: %{field: field_path},
          path: formatted_path,
          fields: [field_path],
          details: %{
            suggestion: "Check that the field exists and is accessible",
            hint: @stale_generated_file_hint
          }
        }

      {field_error_type, _} when is_atom(field_error_type) ->
        %{
          type: "field_validation_error",
          message: "Field validation error: %{error_type}",
          short_message: "Field validation error",
          vars: %{error_type: to_string(field_error_type)},
          path: [],
          fields: [],
          details: %{
            error: inspect(error),
            hint: @stale_generated_file_hint
          }
        }

      other ->
        %{
          type: "unknown_error",
          message: "An unexpected error occurred",
          short_message: "Unknown error",
          vars: %{},
          path: [],
          fields: [],
          details: %{
            error: inspect(other),
            hint: @stale_generated_file_hint
          }
        }
    end
  end

  defp format_field_type(:primitive_type), do: "primitive type"
  defp format_field_type({:ash_type, type, _}), do: "#{inspect(type)}"
  defp format_field_type(other), do: "#{inspect(other)}"

  defp format_path(path) when is_list(path) do
    formatter = AshTypescript.Rpc.output_field_formatter()

    Enum.map(path, fn field ->
      AshTypescript.FieldFormatter.format_field_name(to_string(field), formatter)
    end)
  end

  defp format_field_name(field_name) when is_atom(field_name) do
    format_field_name(to_string(field_name))
  end

  defp format_field_name(field_name) when is_binary(field_name) do
    formatter = AshTypescript.Rpc.output_field_formatter()
    AshTypescript.FieldFormatter.format_field_name(field_name, formatter)
  end

  defp build_complete_field_path(path, field_name) when is_list(path) do
    formatted_path = format_path(path)
    formatted_field = format_field_name(field_name)

    case formatted_path do
      [] -> formatted_field
      _ -> Enum.join(formatted_path ++ [formatted_field], ".")
    end
  end

  defp parse_field_path_to_formatted_path(field_path) when is_binary(field_path) do
    String.split(field_path, ".")
  end
end
