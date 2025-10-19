# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen do
  @moduledoc """
  Generates TypeScript code for interacting with Ash resources via Rpc.
  """
  import AshTypescript.Codegen
  import AshTypescript.Filter
  import AshTypescript.Helpers

  alias AshTypescript.Rpc.RequestedFieldsProcessor
  alias AshTypescript.Rpc.ValidationErrorSchemas
  alias AshTypescript.Rpc.ZodSchemaGenerator

  @doc """
  Formats an endpoint configuration for TypeScript code generation.

  Accepts either:
  - A string: Returns the string as a quoted literal for direct embedding
  - A tuple {:runtime_expr, "expression"}: Returns the expression as-is for runtime evaluation

  ## Examples

      iex> format_endpoint_for_typescript("/rpc/run")
      "\"/rpc/run\""

      iex> format_endpoint_for_typescript({:runtime_expr, "CustomTypes.getRunEndpoint()"})
      "CustomTypes.getRunEndpoint()"
  """
  def format_endpoint_for_typescript(endpoint) when is_binary(endpoint) do
    "\"#{endpoint}\""
  end

  def format_endpoint_for_typescript({:runtime_expr, expression})
      when is_binary(expression) do
    expression
  end

  @doc """
  Generates error handling code for non-OK responses.

  Accepts either:
  - `nil`: Uses default error handling that returns a structured error object
  - A string: Calls the specified function with the response object

  ## Examples

      iex> format_error_handler(nil, "success", "errors")
      "return {\\n  success: false,\\n  errors: [{ type: \\"network\\", message: response.statusText, details: {} }],\\n};"

      iex> format_error_handler("MyAppConfig.handleRpcResponseError", "success", "errors")
      "return MyAppConfig.handleRpcResponseError(response)"
  """
  def format_error_handler(nil, success_field, errors_field) do
    """
    return {
          #{success_field}: false,
          #{errors_field}: [{ #{formatted_error_type_field()}: "network", #{formatted_error_message_field()}: response.statusText, #{formatted_error_details_field()}: {} }],
        };
    """
    |> String.trim()
  end

  def format_error_handler(error_func, _success_field, _errors_field)
      when is_binary(error_func) do
    "return #{error_func}(response)"
  end

  def generate_typescript_types(otp_app, opts \\ []) do
    endpoint_process =
      Keyword.get(opts, :run_endpoint, "/rpc/run")
      |> format_endpoint_for_typescript()

    endpoint_validate =
      Keyword.get(opts, :validate_endpoint, "/rpc/validate")
      |> format_endpoint_for_typescript()

    error_response_func = Keyword.get(opts, :error_response_func)

    resources_and_actions = get_rpc_resources_and_actions(otp_app)

    # Check verifiers before generating
    resources = extract_resources(resources_and_actions)
    domains = Ash.Info.domains(otp_app)

    case AshTypescript.VerifierChecker.check_all_verifiers(resources ++ domains) do
      :ok ->
        warn_missing_rpc_resources(otp_app, resources)

        {:ok,
         generate_full_typescript(
           resources_and_actions,
           endpoint_process,
           endpoint_validate,
           error_response_func,
           otp_app
         )}

      {:error, error_message} ->
        {:error, error_message}
    end
  end

  defp get_rpc_resources_and_actions(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)

      Enum.flat_map(rpc_config, fn %{resource: resource, rpc_actions: rpc_actions} ->
        Enum.map(rpc_actions, fn rpc_action ->
          action = Ash.Resource.Info.action(resource, rpc_action.action)
          {resource, action, rpc_action}
        end)
      end)
    end)
  end

  defp get_typed_queries(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)

      Enum.flat_map(rpc_config, fn %{resource: resource, typed_queries: typed_queries} ->
        Enum.map(typed_queries, fn typed_query ->
          action = Ash.Resource.Info.action(resource, typed_query.action)
          {resource, action, typed_query}
        end)
      end)
    end)
  end

  defp extract_resources(resources_and_actions) do
    resources_and_actions
    |> Enum.map(fn {resource, _action, _rpc_action} -> resource end)
    |> Enum.uniq()
  end

  defp warn_missing_rpc_resources(otp_app, rpc_resources) do
    all_resources_with_extension =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        Ash.Domain.Info.resources(domain)
      end)
      |> Enum.uniq()
      |> Enum.filter(fn resource ->
        extensions = Spark.extensions(resource)
        AshTypescript.Resource in extensions
      end)

    non_embedded_resources_with_extension =
      all_resources_with_extension
      |> Enum.reject(&AshTypescript.Codegen.is_embedded_resource?/1)

    missing_resources =
      non_embedded_resources_with_extension
      |> Enum.reject(&(&1 in rpc_resources))

    if missing_resources != [] do
      IO.puts(:stderr, "\n⚠️  Warning: Found resources with AshTypescript.Resource extension")
      IO.puts(:stderr, "   but not listed in any domain's typescript_rpc block:\n")

      missing_resources
      |> Enum.each(fn resource ->
        IO.puts(:stderr, "   • #{inspect(resource)}")
      end)

      IO.puts(:stderr, "\n   These resources will not have TypeScript types generated.")
      IO.puts(:stderr, "   To fix this, add them to a domain's typescript_rpc block:\n")

      example_domain =
        otp_app
        |> Ash.Info.domains()
        |> List.first()

      if example_domain do
        domain_name = inspect(example_domain)
        example_resource = missing_resources |> List.first() |> inspect()

        IO.puts(:stderr, "   defmodule #{domain_name} do")
        IO.puts(:stderr, "     use Ash.Domain, extensions: [AshTypescript.Rpc]")
        IO.puts(:stderr, "")
        IO.puts(:stderr, "     typescript_rpc do")
        IO.puts(:stderr, "       resource #{example_resource} do")
        IO.puts(:stderr, "         rpc_action :action_name, :read  # or :create, :update, etc.")
        IO.puts(:stderr, "       end")
        IO.puts(:stderr, "     end")
        IO.puts(:stderr, "   end\n")
      end
    end
  end

  defp generate_imports do
    zod_import =
      if AshTypescript.Rpc.generate_zod_schemas?() do
        zod_path = AshTypescript.Rpc.zod_import_path()
        "import { z } from \"#{zod_path}\";"
      else
        ""
      end

    phoenix_import =
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        phoenix_path = AshTypescript.Rpc.phoenix_import_path()
        "import { Channel } from \"#{phoenix_path}\";"
      else
        ""
      end

    config_imports =
      case Application.get_env(:ash_typescript, :import_into_generated) do
        nil ->
          ""

        imports when is_list(imports) ->
          imports
          |> Enum.map(fn import_config ->
            import_name = Map.get(import_config, :import_name)
            file_path = Map.get(import_config, :file)

            if import_name && file_path do
              "import * as #{import_name} from \"#{file_path}\";"
            else
              ""
            end
          end)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n")

        _ ->
          ""
      end

    all_imports =
      [zod_import, phoenix_import, config_imports]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
      |> case do
        "" -> ""
        imports_str -> imports_str <> "\n"
      end

    all_imports
  end

  defp generate_full_typescript(
         rpc_resources_and_actions,
         endpoint_process,
         endpoint_validate,
         error_response_func,
         otp_app
       ) do
    rpc_resources =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        AshTypescript.Rpc.Info.typescript_rpc(domain)
        |> Enum.map(fn %{resource: r} -> r end)
      end)

    actions =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        AshTypescript.Rpc.Info.typescript_rpc(domain)
        |> Enum.flat_map(fn %{resource: resource, rpc_actions: rpc_actions} ->
          Enum.map(rpc_actions, fn %{action: action} ->
            Ash.Resource.Info.action(resource, action)
          end)
        end)
      end)

    typed_queries = get_typed_queries(otp_app)

    embedded_resources = find_embedded_resources(rpc_resources)
    typed_struct_modules = find_typed_struct_modules(rpc_resources)
    all_resources_for_schemas = rpc_resources ++ embedded_resources

    """
    // Generated by AshTypescript
    // Do not edit this file manually

    #{generate_imports()}

    #{generate_ash_type_aliases(rpc_resources, actions)}

    #{generate_all_schemas_for_resources(all_resources_for_schemas, all_resources_for_schemas)}

    #{ZodSchemaGenerator.generate_zod_schemas_for_embedded_resources(embedded_resources)}

    #{ValidationErrorSchemas.generate_validation_error_schemas_for_embedded_resources(embedded_resources)}

    #{ValidationErrorSchemas.generate_validation_error_schemas_for_typed_structs(typed_struct_modules)}

    #{generate_filter_types(all_resources_for_schemas, all_resources_for_schemas)}

    #{generate_utility_types()}

    #{generate_helper_functions()}

    #{generate_typed_queries_section(typed_queries, all_resources_for_schemas)}

    #{generate_rpc_functions(rpc_resources_and_actions, endpoint_process, endpoint_validate, error_response_func, otp_app, all_resources_for_schemas)}
    """
  end

  defp generate_utility_types do
    """
    // Utility Types

    // Resource schema constraint
    type TypedSchema = {
      __type: "Resource" | "TypedStruct" | "TypedMap" | "Union";
      __primitiveFields: string;
    };

    // Utility type to convert union to intersection
    type UnionToIntersection<U> = (U extends any ? (k: U) => void : never) extends (
      k: infer I,
    ) => void
      ? I
      : never;

    // Helper type to infer union field values, avoiding duplication between array and non-array unions
    type InferUnionFieldValue<
      UnionSchema extends { __type: "Union"; __primitiveFields: any },
      FieldSelection extends any[],
    > = UnionToIntersection<
      {
        [FieldIndex in keyof FieldSelection]: FieldSelection[FieldIndex] extends UnionSchema["__primitiveFields"]
          ? FieldSelection[FieldIndex] extends keyof UnionSchema
            ? { [P in FieldSelection[FieldIndex]]: UnionSchema[FieldSelection[FieldIndex]] }
            : never
          : FieldSelection[FieldIndex] extends Record<string, any>
            ? {
                [UnionKey in keyof FieldSelection[FieldIndex]]: UnionKey extends keyof UnionSchema
                  ? UnionSchema[UnionKey] extends { __type: "TypedMap"; __primitiveFields: any }
                    ? UnionSchema[UnionKey]
                    : UnionSchema[UnionKey] extends TypedSchema
                      ? InferResult<UnionSchema[UnionKey], FieldSelection[FieldIndex][UnionKey]>
                      : never
                  : never;
              }
            : never;
      }[number]
    >;

    type HasComplexFields<T extends TypedSchema> = keyof Omit<
      T,
      "__primitiveFields" | "__type" | T["__primitiveFields"]
    > extends never
      ? false
      : true;

    type ComplexFieldKeys<T extends TypedSchema> = keyof Omit<
      T,
      "__primitiveFields" | "__type" | T["__primitiveFields"]
    >;

    type LeafFieldSelection<T extends TypedSchema> = T["__primitiveFields"];

    type ComplexFieldSelection<T extends TypedSchema> = {
      [K in ComplexFieldKeys<T>]?: T[K] extends {
        __type: "Relationship";
        __resource: infer Resource;
      }
        ? NonNullable<Resource> extends TypedSchema
          ? UnifiedFieldSelection<NonNullable<Resource>>[]
          : never
        : T[K] extends {
              __type: "ComplexCalculation";
              __returnType: infer ReturnType;
            }
          ? T[K] extends { __args: infer Args }
            ? NonNullable<ReturnType> extends TypedSchema
              ? {
                  #{formatted_args_field()}: Args;
                  #{formatted_fields_field()}: UnifiedFieldSelection<NonNullable<ReturnType>>[];
                }
              : { #{formatted_args_field()}: Args }
            : NonNullable<ReturnType> extends TypedSchema
              ? { #{formatted_fields_field()}: UnifiedFieldSelection<NonNullable<ReturnType>>[] }
              : never
          : T[K] extends { __type: "Union"; __primitiveFields: infer PrimitiveFields }
            ? T[K] extends { __array: true }
              ? (PrimitiveFields | {
                  [UnionKey in keyof Omit<T[K], "__type" | "__primitiveFields" | "__array">]?: T[K][UnionKey] extends { __type: "TypedMap"; __primitiveFields: any }
                    ? T[K][UnionKey]["__primitiveFields"][]
                    : T[K][UnionKey] extends TypedSchema
                      ? UnifiedFieldSelection<T[K][UnionKey]>[]
                      : never;
                })[]
              : (PrimitiveFields | {
                  [UnionKey in keyof Omit<T[K], "__type" | "__primitiveFields">]?: T[K][UnionKey] extends { __type: "TypedMap"; __primitiveFields: any }
                    ? T[K][UnionKey]["__primitiveFields"][]
                    : T[K][UnionKey] extends TypedSchema
                      ? UnifiedFieldSelection<T[K][UnionKey]>[]
                      : never;
                })[]
              : NonNullable<T[K]> extends TypedSchema
                ? UnifiedFieldSelection<NonNullable<T[K]>>[]
                : never;
    };

    // Main type: Use explicit base case detection to prevent infinite recursion
    type UnifiedFieldSelection<T extends TypedSchema> =
      HasComplexFields<T> extends false
        ? LeafFieldSelection<T> // Base case: only primitives, no recursion
        : LeafFieldSelection<T> | ComplexFieldSelection<T>; // Recursive case

    type InferFieldValue<
      T extends TypedSchema,
      Field,
    > = Field extends T["__primitiveFields"]
      ? Field extends keyof T
        ? { [K in Field]: T[Field] }
        : never
      : Field extends Record<string, any>
        ? {
            [K in keyof Field]: K extends keyof T
              ? T[K] extends {
                  __type: "Relationship";
                  __resource: infer Resource;
                }
                ? NonNullable<Resource> extends TypedSchema
                  ? T[K] extends { __array: true }
                    ? Array<InferResult<NonNullable<Resource>, Field[K]>>
                    : null extends Resource
                      ? InferResult<NonNullable<Resource>, Field[K]> | null
                      : InferResult<NonNullable<Resource>, Field[K]>
                : never
              : T[K] extends {
                    __type: "ComplexCalculation";
                    __returnType: infer ReturnType;
                  }
                ? NonNullable<ReturnType> extends TypedSchema
                  ? null extends ReturnType
                    ? InferResult<NonNullable<ReturnType>, Field[K]["fields"]> | null
                    : InferResult<NonNullable<ReturnType>, Field[K]["fields"]>
                  : ReturnType
                : T[K] extends { __type: "Union"; __primitiveFields: any }
                  ? T[K] extends { __array: true }
                    ? {
                        [CurrentK in K]: T[CurrentK] extends { __type: "Union"; __primitiveFields: any }
                          ? Field[CurrentK] extends any[]
                            ? Array<InferUnionFieldValue<T[CurrentK], Field[CurrentK]>> | null
                            : never
                          : never
                      }
                    : {
                        [CurrentK in K]: T[CurrentK] extends { __type: "Union"; __primitiveFields: any }
                          ? Field[CurrentK] extends any[]
                            ? InferUnionFieldValue<T[CurrentK], Field[CurrentK]> | null
                            : never
                          : never
                      }
                    : NonNullable<T[K]> extends TypedSchema
                      ? null extends T[K]
                        ? InferResult<NonNullable<T[K]>, Field[K]> | null
                        : InferResult<NonNullable<T[K]>, Field[K]>
                      : never
              : never;
          }
        : never;

    type InferResult<
      T extends TypedSchema,
      SelectedFields extends UnifiedFieldSelection<T>[],
    > = UnionToIntersection<
      {
        [K in keyof SelectedFields]: InferFieldValue<T, SelectedFields[K]>;
      }[number]
    >;

    // Pagination conditional types
    // Checks if a page configuration object has any pagination parameters
    type HasPaginationParams<Page> =
      Page extends { offset: any } ? true :
      Page extends { after: any } ? true :
      Page extends { before: any } ? true :
      false;

    // Infer which pagination type is being used from the page config
    type InferPaginationType<Page> =
      Page extends { offset: any } ? "offset" :
      Page extends { after: any } | { before: any } ? "keyset" :
      never;

    // Returns either non-paginated (array) or paginated result based on page params
    // For single pagination type support (offset-only or keyset-only)
    // @ts-ignore
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    type ConditionalPaginatedResult<
      Page,
      RecordType,
      PaginatedType
    > = Page extends undefined
      ? RecordType
      : HasPaginationParams<Page> extends true
        ? PaginatedType
        : RecordType;

    // For actions supporting both offset and keyset pagination
    // Infers the specific pagination type based on which params were passed
    type ConditionalPaginatedResultMixed<
      Page,
      RecordType,
      OffsetType,
      KeysetType
    > = Page extends undefined
      ? RecordType
      : HasPaginationParams<Page> extends true
        ? InferPaginationType<Page> extends "offset"
          ? OffsetType
          : InferPaginationType<Page> extends "keyset"
            ? KeysetType
            : OffsetType | KeysetType  // Fallback to union if can't determine
        : RecordType;

    export type SuccessDataFunc<T extends (...args: any[]) => Promise<any>> = Extract<
      Awaited<ReturnType<T>>,
      { success: true }
    >["data"];


    export type ErrorData<T extends (...args: any[]) => Promise<any>> = Extract<
      Awaited<ReturnType<T>>,
      { success: false }
    >["errors"];

    /**
     * Represents an error from an unsuccessful RPC call
     * @example
     * const error: AshRpcError = { type: "validation_error", message: "Something went wrong" }
     */
    export type AshRpcError = {
      type: string;
      message: string;
      field?: string;
      fieldPath?: string;
      details?: Record<string, any>;
    }



    """
  end

  defp generate_helper_functions do
    """
    // Helper Functions

    /**
     * Gets the CSRF token from the page's meta tag
     * Returns null if no CSRF token is found
     */
    export function getPhoenixCSRFToken(): string | null {
      return document
        ?.querySelector("meta[name='csrf-token']")
        ?.getAttribute("content") || null;
    }

    /**
     * Builds headers object with CSRF token for Phoenix applications
     * Returns headers object with X-CSRF-Token (if available)
     */
    export function buildCSRFHeaders(headers: Record<string, string> = {}): Record<string, string> {
      const csrfToken = getPhoenixCSRFToken();
      if (csrfToken) {
        headers["X-CSRF-Token"] = csrfToken;
      }

      return headers;
    }

    """
  end

  defp generate_rpc_functions(
         resources_and_actions,
         endpoint_process,
         endpoint_validate,
         error_response_func,
         otp_app,
         _resources
       ) do
    rpc_functions =
      resources_and_actions
      |> Enum.map_join("\n\n", fn resource_and_action ->
        generate_rpc_function(
          resource_and_action,
          resources_and_actions,
          endpoint_process,
          endpoint_validate,
          error_response_func,
          otp_app
        )
      end)

    """
    #{rpc_functions}
    """
  end

  def action_supports_pagination?(action) do
    action.type == :read and not action.get? and has_pagination_config?(action)
  end

  defp action_supports_offset_pagination?(action) do
    case get_pagination_config(action) do
      nil -> false
      pagination_config -> Map.get(pagination_config, :offset?, false)
    end
  end

  defp action_supports_keyset_pagination?(action) do
    case get_pagination_config(action) do
      nil -> false
      pagination_config -> Map.get(pagination_config, :keyset?, false)
    end
  end

  defp action_requires_pagination?(action) do
    case get_pagination_config(action) do
      nil -> false
      pagination_config -> Map.get(pagination_config, :required?, false)
    end
  end

  defp action_supports_countable?(action) do
    case get_pagination_config(action) do
      nil -> false
      pagination_config -> Map.get(pagination_config, :countable, false)
    end
  end

  defp action_has_default_limit?(action) do
    case get_pagination_config(action) do
      nil -> false
      pagination_config -> Map.has_key?(pagination_config, :default_limit)
    end
  end

  defp has_pagination_config?(action) do
    case action do
      %{pagination: pagination} when is_map(pagination) -> true
      _ -> false
    end
  end

  defp get_pagination_config(action) do
    case action do
      %{pagination: pagination} when is_map(pagination) -> pagination
      _ -> nil
    end
  end

  defp action_has_input?(resource, action) do
    case action.type do
      :read ->
        action.arguments != []

      :create ->
        accepts = Ash.Resource.Info.action(resource, action.name).accept || []
        accepts != [] || action.arguments != []

      action_type when action_type in [:update, :destroy] ->
        action.accept != [] || action.arguments != []

      :action ->
        action.arguments != []
    end
  end

  def action_returns_field_selectable_type?(action) do
    # Only check returns for generic actions
    if action.type != :action do
      {:error, :not_generic_action}
    else
      check_action_returns(action)
    end
  end

  defp check_action_returns(action) do
    case action.returns do
      {:array, Ash.Type.Struct} ->
        items_constraints = Keyword.get(action.constraints || [], :items, [])

        if Keyword.has_key?(items_constraints, :instance_of) do
          {:ok, :array_of_resource, Keyword.get(items_constraints, :instance_of)}
        else
          {:error, :no_instance_of_defined}
        end

      Ash.Type.Struct ->
        constraints = action.constraints || []

        if Keyword.has_key?(constraints, :instance_of) do
          {:ok, :resource, Keyword.get(constraints, :instance_of)}
        else
          {:error, :no_instance_of_defined}
        end

      {:array, map_like} when map_like in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Keyword] ->
        items_constraints = Keyword.get(action.constraints || [], :items, [])

        if Keyword.has_key?(items_constraints, :fields) do
          {:ok, :array_of_typed_map, Keyword.get(items_constraints, :fields)}
        else
          {:error, :no_fields_defined}
        end

      {:array, module} when is_atom(module) ->
        if AshTypescript.Codegen.is_typed_struct?(module) do
          constraints = action.constraints || []
          items_constraints = Keyword.get(constraints, :items, [])
          fields = Keyword.get(items_constraints, :fields, [])
          {:ok, :array_of_typed_struct, {module, fields}}
        else
          {:error, :not_field_selectable_type}
        end

      map_like when map_like in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Keyword] ->
        constraints = action.constraints || []

        if Keyword.has_key?(constraints, :fields) do
          {:ok, :typed_map, Keyword.get(constraints, :fields)}
        else
          {:ok, :unconstrained_map, nil}
        end

      module when is_atom(module) ->
        if AshTypescript.Codegen.is_typed_struct?(module) do
          constraints = action.constraints || []
          fields = Keyword.get(constraints, :fields, [])
          {:ok, :typed_struct, {module, fields}}
        else
          {:error, :not_field_selectable_type}
        end

      _ ->
        {:error, :not_field_selectable_type}
    end
  end

  defp generate_typed_queries_section([], _all_resources), do: ""

  defp generate_typed_queries_section(typed_queries, all_resources) do
    queries_by_resource =
      Enum.group_by(typed_queries, fn {resource, _action, _query} -> resource end)

    sections =
      Enum.map(queries_by_resource, fn {resource, queries} ->
        resource_name = build_resource_type_name(resource)

        query_types_and_consts =
          Enum.map(queries, fn {resource, action, typed_query} ->
            generate_typed_query_type_and_const(resource, action, typed_query, all_resources)
          end)

        """
        // #{resource_name} Typed Queries
        #{Enum.join(query_types_and_consts, "\n\n")}
        """
      end)

    """
    // ============================
    // Typed Queries
    // ============================
    // Use these types and field constants for server-side rendering and data fetching.
    // The field constants can be used with the corresponding RPC actions for client-side refetching.

    #{Enum.join(sections, "\n\n")}
    """
  end

  defp generate_typed_query_type_and_const(resource, action, typed_query, _all_resources) do
    resource_name = build_resource_type_name(resource)

    atomized_fields = RequestedFieldsProcessor.atomize_requested_fields(typed_query.fields)

    case RequestedFieldsProcessor.process(resource, action.name, atomized_fields) do
      {:ok, {_select, _load, _template}} ->
        type_fields = format_typed_query_fields_type_for_typescript(atomized_fields)

        type_name = typed_query.ts_result_type_name
        const_name = typed_query.ts_fields_const_name

        is_array = action.type == :read && !action.get?

        result_type =
          if is_array do
            "Array<InferResult<#{resource_name}ResourceSchema, #{type_fields}>>"
          else
            "InferResult<#{resource_name}ResourceSchema, #{type_fields}>"
          end

        const_fields = format_typed_query_fields_const_for_typescript(atomized_fields)

        """
        // Type for #{typed_query.name}
        export type #{type_name} = #{result_type};

        // Field selection for #{typed_query.name} - use with RPC actions for refetching
        export const #{const_name} = #{const_fields};
        """

      {:error, error} ->
        raise "Error processing typed query #{typed_query.name}: #{inspect(error)}"
    end
  end

  defp format_typed_query_fields_const_for_typescript(fields) do
    "[" <> format_fields_const_array(fields) <> "]"
  end

  defp format_typed_query_fields_type_for_typescript(fields) do
    "[" <> format_fields_type_array(fields) <> "]"
  end

  defp format_fields_const_array(fields) do
    fields
    |> Enum.map_join(", ", &"#{format_field_item(&1)} as const")
  end

  defp format_fields_type_array(fields) do
    fields
    |> Enum.map_join(", ", &format_field_item/1)
  end

  defp format_field_item(field) when is_atom(field) do
    ~s["#{format_field_name(field)}"]
  end

  defp format_field_item({field, nested_fields}) when is_atom(field) and is_list(nested_fields) do
    "{ #{format_field_name(field)}: [#{format_fields_type_array(nested_fields)}] }"
  end

  defp format_field_item({field, {args, nested_fields}})
       when is_atom(field) and is_map(args) and is_list(nested_fields) do
    args_json = format_args_map(args)

    "{ #{format_field_name(field)}: { #{formatted_args_field()}: #{args_json}, #{formatted_fields_field()}: [#{format_fields_type_array(nested_fields)}] } }"
  end

  defp format_field_item({field, nested_fields}) when is_atom(field) and is_map(nested_fields) do
    case nested_fields do
      %{args: args, fields: fields} ->
        args_json = format_args_map(args)

        "{ #{format_field_name(field)}: { #{formatted_args_field()}: #{args_json}, #{formatted_fields_field()}: [#{format_fields_type_array(fields)}] } }"

      _ ->
        inspect(nested_fields)
    end
  end

  defp format_field_item(%{} = field_map) do
    formatted_pairs =
      field_map
      |> Enum.map_join(", ", fn {k, v} ->
        key = format_field_name(k)
        value = format_field_item(v)
        "#{key}: #{value}"
      end)

    "{ #{formatted_pairs} }"
  end

  defp format_field_item(list) when is_list(list) do
    formatted_items =
      list
      |> Enum.map_join(", ", &format_field_item/1)

    "[#{formatted_items}]"
  end

  defp format_field_item(field), do: inspect(field)

  defp format_field_name(atom) do
    formatter = AshTypescript.Rpc.output_field_formatter()
    AshTypescript.FieldFormatter.format_field(atom, formatter)
  end

  defp format_args_map(args) do
    formatted_args =
      args
      |> Enum.map_join(", ", fn {k, v} ->
        "\"#{format_field_name(k)}\": #{Jason.encode!(v)}"
      end)

    "{ #{formatted_args} }"
  end

  defp generate_input_type(resource, action, rpc_action_name) do
    if action_has_input?(resource, action) do
      input_type_name = "#{snake_to_pascal_case(rpc_action_name)}Input"

      input_field_defs =
        case action.type do
          :read ->
            arguments = action.arguments

            if arguments != [] do
              Enum.map(arguments, fn arg ->
                optional = arg.allow_nil? || arg.default != nil

                mapped_name =
                  AshTypescript.Resource.Info.get_mapped_argument_name(
                    resource,
                    action.name,
                    arg.name
                  )

                formatted_arg_name =
                  AshTypescript.FieldFormatter.format_field(
                    mapped_name,
                    AshTypescript.Rpc.output_field_formatter()
                  )

                {formatted_arg_name, get_ts_type(arg), optional}
              end)
            else
              []
            end

          :create ->
            accepts = Ash.Resource.Info.action(resource, action.name).accept || []
            arguments = action.arguments

            if accepts != [] || arguments != [] do
              accept_field_defs =
                Enum.map(accepts, fn field_name ->
                  attr = Ash.Resource.Info.attribute(resource, field_name)
                  optional = attr.allow_nil? || attr.default != nil
                  base_type = AshTypescript.Codegen.get_ts_input_type(attr)
                  field_type = if attr.allow_nil?, do: "#{base_type} | null", else: base_type

                  mapped_name =
                    AshTypescript.Resource.Info.get_mapped_field_name(resource, field_name)

                  formatted_field_name =
                    AshTypescript.FieldFormatter.format_field(
                      mapped_name,
                      AshTypescript.Rpc.output_field_formatter()
                    )

                  {formatted_field_name, field_type, optional}
                end)

              argument_field_defs =
                Enum.map(arguments, fn arg ->
                  optional = arg.allow_nil? || arg.default != nil

                  mapped_name =
                    AshTypescript.Resource.Info.get_mapped_argument_name(
                      resource,
                      action.name,
                      arg.name
                    )

                  formatted_arg_name =
                    AshTypescript.FieldFormatter.format_field(
                      mapped_name,
                      AshTypescript.Rpc.output_field_formatter()
                    )

                  {formatted_arg_name, get_ts_type(arg), optional}
                end)

              accept_field_defs ++ argument_field_defs
            else
              []
            end

          action_type when action_type in [:update, :destroy] ->
            if action.accept != [] || action.arguments != [] do
              accept_field_defs =
                Enum.map(action.accept, fn field_name ->
                  attr = Ash.Resource.Info.attribute(resource, field_name)
                  optional = attr.allow_nil? || attr.default != nil
                  base_type = AshTypescript.Codegen.get_ts_input_type(attr)
                  field_type = if attr.allow_nil?, do: "#{base_type} | null", else: base_type

                  mapped_name =
                    AshTypescript.Resource.Info.get_mapped_field_name(resource, field_name)

                  formatted_field_name =
                    AshTypescript.FieldFormatter.format_field(
                      mapped_name,
                      AshTypescript.Rpc.output_field_formatter()
                    )

                  {formatted_field_name, field_type, optional}
                end)

              argument_field_defs =
                Enum.map(action.arguments, fn arg ->
                  optional = arg.allow_nil? || arg.default != nil

                  mapped_name =
                    AshTypescript.Resource.Info.get_mapped_argument_name(
                      resource,
                      action.name,
                      arg.name
                    )

                  formatted_arg_name =
                    AshTypescript.FieldFormatter.format_field(
                      mapped_name,
                      AshTypescript.Rpc.output_field_formatter()
                    )

                  {formatted_arg_name, get_ts_type(arg), optional}
                end)

              accept_field_defs ++ argument_field_defs
            else
              []
            end

          :action ->
            arguments = action.arguments

            if arguments != [] do
              Enum.map(arguments, fn arg ->
                optional = arg.allow_nil? || arg.default != nil

                mapped_name =
                  AshTypescript.Resource.Info.get_mapped_argument_name(
                    resource,
                    action.name,
                    arg.name
                  )

                formatted_arg_name =
                  AshTypescript.FieldFormatter.format_field(
                    mapped_name,
                    AshTypescript.Rpc.output_field_formatter()
                  )

                {formatted_arg_name, get_ts_type(arg), optional}
              end)
            else
              []
            end
        end

      field_lines =
        Enum.map(input_field_defs, fn {name, type, optional} ->
          "  #{name}#{if optional, do: "?", else: ""}: #{type};"
        end)

      """
      export type #{input_type_name} = {
      #{Enum.join(field_lines, "\n")}
      };
      """
    else
      ""
    end
  end

  defp generate_result_type(resource, action, rpc_action, rpc_action_name) do
    resource_name = build_resource_type_name(resource)
    rpc_action_name_pascal = snake_to_pascal_case(rpc_action_name)

    case action.type do
      :read when action.get? ->
        metadata_type = generate_action_metadata_type(action, rpc_action, rpc_action_name_pascal)
        has_metadata = metadata_enabled?(get_exposed_metadata_fields(rpc_action, action))

        if has_metadata do
          """
          export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{resource_name}ResourceSchema>[];
          #{metadata_type}
          type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields,
            MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
          > = (InferResult<#{resource_name}ResourceSchema, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>) | null;
          """
        else
          """
          export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{resource_name}ResourceSchema>[];
          type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields,
          > = InferResult<#{resource_name}ResourceSchema, Fields> | null;
          """
        end

      :read ->
        if action_supports_pagination?(action) do
          metadata_type =
            generate_action_metadata_type(action, rpc_action, rpc_action_name_pascal)

          has_metadata = metadata_enabled?(get_exposed_metadata_fields(rpc_action, action))

          fields_type = """
          export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{resource_name}ResourceSchema>[];
          #{metadata_type}
          """

          pagination_type =
            if action_requires_pagination?(action) do
              generate_pagination_result_type(
                resource,
                action,
                rpc_action_name_pascal,
                resource_name,
                has_metadata
              )
            else
              generate_conditional_pagination_result_type(
                resource,
                action,
                rpc_action_name_pascal,
                resource_name,
                has_metadata
              )
            end

          fields_type <> "\n" <> pagination_type
        else
          metadata_type =
            generate_action_metadata_type(action, rpc_action, rpc_action_name_pascal)

          has_metadata = metadata_enabled?(get_exposed_metadata_fields(rpc_action, action))

          if has_metadata do
            """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{resource_name}ResourceSchema>[];
            #{metadata_type}
            type Infer#{rpc_action_name_pascal}Result<
              Fields extends #{rpc_action_name_pascal}Fields,
              MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
            > = Array<InferResult<#{resource_name}ResourceSchema, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>;
            """
          else
            """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{resource_name}ResourceSchema>[];
            type Infer#{rpc_action_name_pascal}Result<
              Fields extends #{rpc_action_name_pascal}Fields,
            > = Array<InferResult<#{resource_name}ResourceSchema, Fields>>;
            """
          end
        end

      action_type when action_type in [:create, :update] ->
        metadata_type = generate_action_metadata_type(action, rpc_action, rpc_action_name_pascal)
        has_metadata = metadata_enabled?(get_exposed_metadata_fields(rpc_action, action))

        if has_metadata do
          """
          export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{resource_name}ResourceSchema>[];
          #{metadata_type}
          type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields,
            MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
          > = InferResult<#{resource_name}ResourceSchema, Fields>;
          """
        else
          """
          export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{resource_name}ResourceSchema>[];
          #{metadata_type}
          type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields,
          > = InferResult<#{resource_name}ResourceSchema, Fields>;
          """
        end

      :destroy ->
        metadata_type = generate_action_metadata_type(action, rpc_action, rpc_action_name_pascal)
        has_metadata = metadata_enabled?(get_exposed_metadata_fields(rpc_action, action))

        if has_metadata do
          """
          #{metadata_type}
          type Infer#{rpc_action_name_pascal}Result<
            MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
          > = {};
          """
        else
          metadata_type
        end

      :action ->
        case action_returns_field_selectable_type?(action) do
          {:ok, type, value} when type in [:resource, :array_of_resource] ->
            target_resource_name = build_resource_type_name(value)

            if type == :array_of_resource do
              """
              export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{target_resource_name}ResourceSchema>[];

              type Infer#{rpc_action_name_pascal}Result<
                Fields extends #{rpc_action_name_pascal}Fields,
              > = Array<InferResult<#{target_resource_name}ResourceSchema, Fields>>;
              """
            else
              """
              export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{target_resource_name}ResourceSchema>[];

              type Infer#{rpc_action_name_pascal}Result<
                Fields extends #{rpc_action_name_pascal}Fields,
              > = InferResult<#{target_resource_name}ResourceSchema, Fields>;
              """
            end

          {:ok, type, value} when type in [:typed_map, :array_of_typed_map] ->
            typed_map_schema = build_map_type(value)

            if type == :array_of_typed_map do
              """
              export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{typed_map_schema}>[];

              type Infer#{rpc_action_name_pascal}Result<
                Fields extends #{rpc_action_name_pascal}Fields,
              > = Array<InferResult<#{typed_map_schema}, Fields>>;
              """
            else
              """
              export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{typed_map_schema}>[];

              type Infer#{rpc_action_name_pascal}Result<
                Fields extends #{rpc_action_name_pascal}Fields,
              > = InferResult<#{typed_map_schema}, Fields>;
              """
            end

          {:ok, :typed_struct, {module, fields}} ->
            field_name_mappings =
              if function_exported?(module, :typescript_field_names, 0) do
                module.typescript_field_names()
              else
                nil
              end

            typed_map_schema = build_map_type(fields, nil, field_name_mappings)

            """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{typed_map_schema}>[];

            type Infer#{rpc_action_name_pascal}Result<
              Fields extends #{rpc_action_name_pascal}Fields,
            > = InferResult<#{typed_map_schema}, Fields>;
            """

          {:ok, :array_of_typed_struct, {module, fields}} ->
            field_name_mappings =
              if function_exported?(module, :typescript_field_names, 0) do
                module.typescript_field_names()
              else
                nil
              end

            typed_map_schema = build_map_type(fields, nil, field_name_mappings)

            """
            export type #{rpc_action_name_pascal}Fields = UnifiedFieldSelection<#{typed_map_schema}>[];

            type Infer#{rpc_action_name_pascal}Result<
              Fields extends #{rpc_action_name_pascal}Fields,
            > = Array<InferResult<#{typed_map_schema}, Fields>>;
            """

          {:ok, :unconstrained_map, _} ->
            """
            type Infer#{rpc_action_name_pascal}Result = Record<string, any>;
            """

          _ ->
            if action.returns do
              return_type = get_ts_type(%{type: action.returns, constraints: action.constraints})

              """
              type Infer#{rpc_action_name_pascal}Result = #{return_type};
              """
            else
              """
              type Infer#{rpc_action_name_pascal}Result = {};
              """
            end
        end
    end
  end

  def get_exposed_metadata_fields(rpc_action, ash_action) do
    show_metadata = Map.get(rpc_action, :show_metadata, nil)

    case show_metadata do
      nil -> Enum.map(Map.get(ash_action, :metadata, []), & &1.name)
      false -> []
      [] -> []
      field_list when is_list(field_list) -> field_list
    end
  end

  defp metadata_enabled?(exposed_fields) do
    not Enum.empty?(exposed_fields)
  end

  defp generate_action_metadata_type(action, rpc_action, rpc_action_name_pascal) do
    exposed_fields = get_exposed_metadata_fields(rpc_action, action)

    if metadata_enabled?(exposed_fields) do
      all_metadata_fields = Map.get(action, :metadata, [])

      metadata_fields_to_include =
        Enum.filter(all_metadata_fields, fn metadata_field ->
          metadata_field.name in exposed_fields
        end)

      metadata_field_defs =
        Enum.map(metadata_fields_to_include, fn metadata_field ->
          ts_type =
            get_ts_type(%{
              type: metadata_field.type,
              constraints: metadata_field.constraints || []
            })

          optional = Map.get(metadata_field, :allow_nil?, true)

          mapped_name =
            AshTypescript.Rpc.Info.get_mapped_metadata_field_name(rpc_action, metadata_field.name)

          formatted_name =
            AshTypescript.FieldFormatter.format_field(
              mapped_name,
              AshTypescript.Rpc.output_field_formatter()
            )

          "  #{formatted_name}#{if optional, do: "?", else: ""}: #{ts_type};"
        end)

      """

      export type #{rpc_action_name_pascal}Metadata = {
      #{Enum.join(metadata_field_defs, "\n")}
      };
      """
    else
      ""
    end
  end

  defp generate_pagination_result_type(
         _resource,
         action,
         rpc_action_name_pascal,
         resource_name,
         has_metadata
       ) do
    supports_offset = action_supports_offset_pagination?(action)
    supports_keyset = action_supports_keyset_pagination?(action)

    cond do
      supports_offset and supports_keyset ->
        generate_mixed_pagination_result_type(rpc_action_name_pascal, resource_name, has_metadata)

      supports_offset ->
        generate_offset_pagination_result_type(
          rpc_action_name_pascal,
          resource_name,
          has_metadata
        )

      supports_keyset ->
        generate_keyset_pagination_result_type(
          rpc_action_name_pascal,
          resource_name,
          has_metadata
        )
    end
  end

  defp generate_offset_pagination_result_type(rpc_action_name_pascal, resource_name, has_metadata) do
    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    offset_field = formatted_offset_field()

    if has_metadata do
      """
      type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
        MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
      > = {
        #{results_field}: Array<InferResult<#{resource_name}ResourceSchema, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
      };
      """
    else
      """
      type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
      > = {
        #{results_field}: Array<InferResult<#{resource_name}ResourceSchema, Fields>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
      };
      """
    end
  end

  defp generate_keyset_pagination_result_type(rpc_action_name_pascal, resource_name, has_metadata) do
    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    after_field = formatted_after_field()
    before_field = formatted_before_field()
    previous_page_field = formatted_previous_page_field()
    next_page_field = formatted_next_page_field()

    if has_metadata do
      """
      type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
        MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
      > = {
        #{results_field}: Array<InferResult<#{resource_name}ResourceSchema, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string;
        #{next_page_field}: string;
      };
      """
    else
      """
      type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
      > = {
        #{results_field}: Array<InferResult<#{resource_name}ResourceSchema, Fields>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string;
        #{next_page_field}: string;
      };
      """
    end
  end

  defp generate_mixed_pagination_result_type(rpc_action_name_pascal, resource_name, has_metadata) do
    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    offset_field = formatted_offset_field()
    after_field = formatted_after_field()
    before_field = formatted_before_field()
    count_field = format_output_field(:count)
    previous_page_field = formatted_previous_page_field()
    next_page_field = formatted_next_page_field()
    type_field = format_output_field(:type)

    if has_metadata do
      """
      type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
        MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []
      > = {
        #{results_field}: Array<InferResult<#{resource_name}ResourceSchema, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
        #{count_field}?: number | null;
        #{type_field}: "offset";
      } | {
        #{results_field}: Array<InferResult<#{resource_name}ResourceSchema, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string;
        #{next_page_field}: string;
        #{count_field}?: number | null;
        #{type_field}: "keyset";
      };
      """
    else
      """
      type Infer#{rpc_action_name_pascal}Result<
        Fields extends #{rpc_action_name_pascal}Fields,
      > = {
        #{results_field}: Array<InferResult<#{resource_name}ResourceSchema, Fields>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{offset_field}: number;
        #{count_field}?: number | null;
        #{type_field}: "offset";
      } | {
        #{results_field}: Array<InferResult<#{resource_name}ResourceSchema, Fields>>;
        #{has_more_field}: boolean;
        #{limit_field}: number;
        #{after_field}: string | null;
        #{before_field}: string | null;
        #{previous_page_field}: string;
        #{next_page_field}: string;
        #{count_field}?: number | null;
        #{type_field}: "keyset";
      };
      """
    end
  end

  defp generate_conditional_pagination_result_type(
         _resource,
         action,
         rpc_action_name_pascal,
         resource_name,
         has_metadata
       ) do
    supports_offset = action_supports_offset_pagination?(action)
    supports_keyset = action_supports_keyset_pagination?(action)

    if has_metadata do
      array_type =
        "Array<InferResult<#{resource_name}ResourceSchema, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>"

      cond do
        supports_offset and supports_keyset ->
          offset_type =
            generate_offset_pagination_type_inline(
              resource_name,
              rpc_action_name_pascal,
              has_metadata
            )

          keyset_type =
            generate_keyset_pagination_type_inline(
              resource_name,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields,
            MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = [],
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResultMixed<Page, #{array_type}, #{offset_type}, #{keyset_type}>;
          """

        supports_offset ->
          offset_type =
            generate_offset_pagination_type_inline(
              resource_name,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields,
            MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = [],
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{offset_type}>;
          """

        supports_keyset ->
          keyset_type =
            generate_keyset_pagination_type_inline(
              resource_name,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields,
            MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = [],
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{keyset_type}>;
          """
      end
    else
      array_type = "Array<InferResult<#{resource_name}ResourceSchema, Fields>>"

      cond do
        supports_offset and supports_keyset ->
          offset_type =
            generate_offset_pagination_type_inline(
              resource_name,
              rpc_action_name_pascal,
              has_metadata
            )

          keyset_type =
            generate_keyset_pagination_type_inline(
              resource_name,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields,
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResultMixed<Page, #{array_type}, #{offset_type}, #{keyset_type}>;
          """

        supports_offset ->
          offset_type =
            generate_offset_pagination_type_inline(
              resource_name,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields,
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{offset_type}>;
          """

        supports_keyset ->
          keyset_type =
            generate_keyset_pagination_type_inline(
              resource_name,
              rpc_action_name_pascal,
              has_metadata
            )

          """
          type Infer#{rpc_action_name_pascal}Result<
            Fields extends #{rpc_action_name_pascal}Fields,
            Page extends #{rpc_action_name_pascal}Config["page"] = undefined
          > = ConditionalPaginatedResult<Page, #{array_type}, #{keyset_type}>;
          """
      end
    end
  end

  defp generate_offset_pagination_type_inline(resource_name, rpc_action_name_pascal, has_metadata) do
    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    offset_field = formatted_offset_field()
    count_field = format_output_field(:count)
    type_field = format_output_field(:type)

    result_array_type =
      if has_metadata do
        "Array<InferResult<#{resource_name}ResourceSchema, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>"
      else
        "Array<InferResult<#{resource_name}ResourceSchema, Fields>>"
      end

    """
    {
      #{results_field}: #{result_array_type};
      #{has_more_field}: boolean;
      #{limit_field}: number;
      #{offset_field}: number;
      #{count_field}?: number | null;
      #{type_field}: "offset";
    }
    """
    |> String.trim()
  end

  defp generate_keyset_pagination_type_inline(resource_name, rpc_action_name_pascal, has_metadata) do
    results_field = formatted_results_field()
    has_more_field = formatted_has_more_field()
    limit_field = formatted_limit_field()
    after_field = formatted_after_field()
    before_field = formatted_before_field()
    previous_page_field = formatted_previous_page_field()
    next_page_field = formatted_next_page_field()
    count_field = format_output_field(:count)
    type_field = format_output_field(:type)

    result_array_type =
      if has_metadata do
        "Array<InferResult<#{resource_name}ResourceSchema, Fields> & Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>>"
      else
        "Array<InferResult<#{resource_name}ResourceSchema, Fields>>"
      end

    """
    {
      #{results_field}: #{result_array_type};
      #{has_more_field}: boolean;
      #{limit_field}: number;
      #{after_field}: string | null;
      #{before_field}: string | null;
      #{previous_page_field}: string;
      #{next_page_field}: string;
      #{count_field}?: number | null;
      #{type_field}: "keyset";
    }
    """
    |> String.trim()
  end

  defp generate_pagination_config_fields(action) do
    supports_offset = action_supports_offset_pagination?(action)
    supports_keyset = action_supports_keyset_pagination?(action)
    supports_countable = action_supports_countable?(action)
    is_required = action_requires_pagination?(action)
    has_default_limit = action_has_default_limit?(action)

    if supports_offset or supports_keyset do
      optional_mark = if is_required, do: "", else: "?"
      limit_required = if is_required and not has_default_limit, do: "", else: "?"

      cond do
        supports_offset and supports_keyset ->
          generate_mixed_pagination_config_fields(
            limit_required,
            supports_countable,
            optional_mark
          )

        supports_offset ->
          generate_offset_pagination_config_fields(
            limit_required,
            supports_countable,
            optional_mark
          )

        supports_keyset ->
          generate_keyset_pagination_config_fields(limit_required, optional_mark)
      end
    else
      []
    end
  end

  defp generate_offset_pagination_config_fields(limit_required, supports_countable, optional_mark) do
    fields = [
      "    #{formatted_limit_field()}#{limit_required}: number;",
      "    #{formatted_offset_field()}?: number;",
      "    #{formatted_after_field()}?: never;",
      "    #{formatted_before_field()}?: never;"
    ]

    fields =
      if supports_countable do
        fields ++ ["    #{format_output_field(:count)}?: boolean;"]
      else
        fields
      end

    [
      "  #{formatted_page_field()}#{optional_mark}: {"
    ] ++
      fields ++
      [
        "  };"
      ]
  end

  defp generate_keyset_pagination_config_fields(limit_required, optional_mark) do
    fields = [
      "    #{formatted_limit_field()}#{limit_required}: number;",
      "    #{formatted_after_field()}?: string;",
      "    #{formatted_before_field()}?: string;",
      "    #{formatted_offset_field()}?: never;",
      "    #{format_output_field(:count)}?: never;"
    ]

    [
      "  #{formatted_page_field()}#{optional_mark}: {"
    ] ++
      fields ++
      [
        "  };"
      ]
  end

  defp get_action_context(resource, action) do
    %{
      requires_tenant: AshTypescript.Rpc.requires_tenant_parameter?(resource),
      requires_primary_key: action.type in [:update, :destroy],
      supports_pagination:
        action.type == :read and not action.get? and action_supports_pagination?(action),
      supports_filtering: action.type == :read and not action.get?,
      has_input: action_has_input?(resource, action)
    }
  end

  defp build_primary_key_config_field(resource, opts) do
    primary_key_attrs = Ash.Resource.Info.primary_key(resource)
    simple_type = Keyword.get(opts, :simple_type, false)

    if simple_type do
      # For validation functions - always use string type
      formatted_primary_key = format_output_field(:primary_key)
      ["  #{formatted_primary_key}: string;"]
    else
      # For execution functions - use proper typing
      if Enum.count(primary_key_attrs) == 1 do
        attr_name = Enum.at(primary_key_attrs, 0)
        attr = Ash.Resource.Info.attribute(resource, attr_name)
        formatted_primary_key = format_output_field(:primary_key)
        ["  #{formatted_primary_key}: #{get_ts_type(attr)};"]
      else
        formatted_primary_key = format_output_field(:primary_key)

        [
          "  #{formatted_primary_key}: {"
        ] ++
          Enum.map(primary_key_attrs, fn attr_name ->
            attr = Ash.Resource.Info.attribute(resource, attr_name)
            formatted_attr_name = format_output_field(attr.name)
            "    #{formatted_attr_name}: #{get_ts_type(attr)};"
          end) ++
          [
            "  };"
          ]
      end
    end
  end

  defp build_common_config_fields(resource, _action, context, opts) do
    rpc_action_name_pascal = snake_to_pascal_case(opts[:rpc_action_name] || "action")
    simple_primary_key = Keyword.get(opts, :simple_primary_key, false)

    config_fields = []

    config_fields =
      if context.requires_tenant do
        config_fields ++ ["  #{format_output_field(:tenant)}: string;"]
      else
        config_fields
      end

    config_fields =
      if context.requires_primary_key do
        config_fields ++ build_primary_key_config_field(resource, simple_type: simple_primary_key)
      else
        config_fields
      end

    config_fields =
      if context.has_input do
        config_fields ++ ["  #{format_output_field(:input)}: #{rpc_action_name_pascal}Input;"]
      else
        config_fields
      end

    config_fields
  end

  defp build_payload_fields(_resource, _action, rpc_action_name, context, opts) do
    include_fields = Keyword.get(opts, :include_fields, false)
    include_filtering_pagination = Keyword.get(opts, :include_filtering_pagination, true)
    include_metadata_fields = Keyword.get(opts, :include_metadata_fields, false)

    payload_fields = ["action: \"#{rpc_action_name}\""]

    payload_fields =
      if context.requires_tenant do
        payload_fields ++
          ["#{format_output_field(:tenant)}: config.#{format_output_field(:tenant)}"]
      else
        payload_fields
      end

    payload_fields =
      if context.requires_primary_key do
        payload_fields ++
          ["#{format_output_field(:primary_key)}: config.#{format_output_field(:primary_key)}"]
      else
        payload_fields
      end

    payload_fields =
      if context.has_input do
        payload_fields ++
          ["#{format_output_field(:input)}: config.#{format_output_field(:input)}"]
      else
        payload_fields
      end

    payload_fields =
      if include_fields do
        payload_fields ++ ["#{formatted_fields_field()}: config.#{formatted_fields_field()}"]
      else
        payload_fields
      end

    payload_fields =
      if include_metadata_fields do
        metadata_fields_key = format_output_field(:metadata_fields)

        payload_fields ++
          [
            "...(config.#{metadata_fields_key} && { #{metadata_fields_key}: config.#{metadata_fields_key} })"
          ]
      else
        payload_fields
      end

    payload_fields =
      if include_filtering_pagination and context.supports_filtering do
        payload_fields ++
          [
            "...(config.#{format_output_field(:filter)} && { #{format_output_field(:filter)}: config.#{format_output_field(:filter)} })",
            "...(config.#{format_output_field(:sort)} && { #{format_output_field(:sort)}: config.#{format_output_field(:sort)} })"
          ]
      else
        payload_fields
      end

    payload_fields =
      if include_filtering_pagination and context.supports_pagination do
        payload_fields ++
          [
            "...(config.#{formatted_page_field()} && { #{formatted_page_field()}: config.#{formatted_page_field()} })"
          ]
      else
        payload_fields
      end

    payload_fields
  end

  defp generate_mixed_pagination_config_fields(limit_required, supports_countable, optional_mark) do
    offset_fields = [
      "      #{formatted_limit_field()}#{limit_required}: number;",
      "      #{formatted_offset_field()}?: number;"
    ]

    offset_fields =
      if supports_countable do
        offset_fields ++ ["      #{format_output_field(:count)}?: boolean;"]
      else
        offset_fields
      end

    keyset_fields = [
      "      #{formatted_limit_field()}#{limit_required}: number;",
      "      #{formatted_after_field()}?: string;",
      "      #{formatted_before_field()}?: string;"
    ]

    [
      "  #{formatted_page_field()}#{optional_mark}: ("
    ] ++
      [
        "    {"
      ] ++
      offset_fields ++
      [
        "    } | {"
      ] ++
      keyset_fields ++
      [
        "    }"
      ] ++
      [
        "  );"
      ]
  end

  defp generate_rpc_execution_function(
         resource,
         action,
         rpc_action,
         rpc_action_name,
         endpoint_process,
         error_response_func
       ) do
    function_name =
      AshTypescript.FieldFormatter.format_field(
        rpc_action_name,
        AshTypescript.Rpc.output_field_formatter()
      )

    rpc_action_name_pascal = snake_to_pascal_case(rpc_action_name)
    resource_name = build_resource_type_name(resource)
    context = get_action_context(resource, action)

    has_metadata = metadata_enabled?(get_exposed_metadata_fields(rpc_action, action))

    config_fields =
      build_common_config_fields(resource, action, context, rpc_action_name: rpc_action_name)

    {config_fields, has_fields, fields_generic} =
      if action.type != :destroy do
        case action.type do
          :action ->
            case action_returns_field_selectable_type?(action) do
              {:ok, type, _value} when type in [:resource, :array_of_resource] ->
                updated_fields = config_fields ++ ["  #{formatted_fields_field()}: Fields;"]

                {updated_fields, true, "Fields extends #{rpc_action_name_pascal}Fields"}

              {:ok, type, _fields}
              when type in [
                     :typed_map,
                     :array_of_typed_map,
                     :typed_struct,
                     :array_of_typed_struct
                   ] ->
                updated_fields =
                  config_fields ++
                    [
                      "  #{formatted_fields_field()}: Fields;"
                    ]

                {updated_fields, true, "Fields extends #{rpc_action_name_pascal}Fields"}

              {:ok, :unconstrained_map, _} ->
                # Unconstrained maps don't support field selection
                {config_fields, false, nil}

              _ ->
                {config_fields, false, nil}
            end

          _ ->
            updated_fields = config_fields ++ ["  #{formatted_fields_field()}: Fields;"]

            {updated_fields, true, "Fields extends #{rpc_action_name_pascal}Fields"}
        end
      else
        {config_fields, false, nil}
      end

    config_fields =
      if context.supports_filtering do
        config_fields ++ ["  #{format_output_field(:filter)}?: #{resource_name}FilterInput;"]
      else
        config_fields
      end

    config_fields =
      if context.supports_filtering do
        config_fields ++ ["  #{format_output_field(:sort)}?: string;"]
      else
        config_fields
      end

    config_fields =
      if context.supports_pagination do
        pagination_fields = generate_pagination_config_fields(action)
        config_fields ++ pagination_fields
      else
        config_fields
      end

    config_fields =
      config_fields ++
        [
          "  headers?: Record<string, string>;",
          "  fetchOptions?: RequestInit;",
          "  customFetch?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;"
        ]

    config_fields =
      if has_metadata do
        metadata_fields_key = format_output_field(:metadata_fields)
        config_fields ++ ["  #{metadata_fields_key}?: MetadataFields;"]
      else
        config_fields
      end

    is_optional_pagination =
      action.type == :read and not action.get? and action_supports_pagination?(action) and
        not action_requires_pagination?(action) and has_fields

    {config_type_export, config_type_ref} =
      if is_optional_pagination do
        config_type_name = "#{rpc_action_name_pascal}Config"

        config_fields_concrete =
          Enum.map(config_fields, fn field_def ->
            String.replace(field_def, ": Fields;", ": #{rpc_action_name_pascal}Fields;")
            |> String.replace(
              ": MetadataFields;",
              ": ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata>;"
            )
          end)

        config_body = "{\n#{Enum.join(config_fields_concrete, "\n")}\n}"
        config_export = "export type #{config_type_name} = #{config_body};\n\n"
        {config_export, config_type_name}
      else
        config_body = "{\n#{Enum.join(config_fields, "\n")}\n}"
        {"", config_body}
      end

    success_field = format_output_field(:success)
    errors_field = format_output_field(:errors)

    {result_type_def, return_type_def, generic_param, function_signature} =
      cond do
        action.type == :destroy ->
          if has_metadata do
            result_type = """
            | { #{success_field}: true; data: {}; #{format_output_field(:metadata)}: Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>; }
            | {
                #{success_field}: false;
                #{errors_field}: Array<{
                  #{formatted_error_type_field()}: string;
                  #{formatted_error_message_field()}: string;
                  #{formatted_error_field_path_field()}?: string;
                  #{formatted_error_details_field()}: Record<string, string>;
                }>;
              }
            """

            result_type_def =
              "export type #{rpc_action_name_pascal}Result<MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []> = #{result_type};"

            {result_type_def, "#{rpc_action_name_pascal}Result<MetadataFields>",
             "MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []",
             "config: #{config_type_ref}"}
          else
            result_type = """
            | { #{success_field}: true; data: {}; }
            | {
                #{success_field}: false;
                #{errors_field}: Array<{
                  #{formatted_error_type_field()}: string;
                  #{formatted_error_message_field()}: string;
                  #{formatted_error_field_path_field()}?: string;
                  #{formatted_error_details_field()}: Record<string, string>;
                }>;
              }
            """

            result_type_def = "export type #{rpc_action_name_pascal}Result = #{result_type};"

            {result_type_def, "#{rpc_action_name_pascal}Result", "", "config: #{config_type_ref}"}
          end

        has_fields ->
          is_mutation = action.type in [:create, :update]

          mutation_metadata_field =
            if is_mutation and has_metadata,
              do:
                " #{format_output_field(:metadata)}: Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>;",
              else: ""

          # For optional pagination, update result type to include Page generic
          {result_type_generics, return_type_generics, function_generics, function_sig,
           function_return_generics} =
            cond do
              is_optional_pagination and has_metadata and action.type == :read ->
                page_param = "Page extends #{rpc_action_name_pascal}Config[\"page\"] = undefined"

                metadata_param =
                  "MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []"

                result_type_generics_str = "#{fields_generic}, #{metadata_param}, #{page_param}"
                result_data_generics_str = "<Fields, MetadataFields, Page>"
                metadata_fields_key = format_output_field(:metadata_fields)

                function_return_generics_str =
                  "<Fields, Config[\"#{metadata_fields_key}\"] extends ReadonlyArray<any> ? Config[\"#{metadata_fields_key}\"] : [], Config[\"page\"]>"

                config_generic = "Config extends #{rpc_action_name_pascal}Config"
                function_generics_str = "#{fields_generic}, #{config_generic}"
                function_sig_str = "config: Config & { #{formatted_fields_field()}: Fields }"

                {result_type_generics_str, result_data_generics_str, function_generics_str,
                 function_sig_str, function_return_generics_str}

              is_optional_pagination ->
                page_param = "Page extends #{rpc_action_name_pascal}Config[\"page\"] = undefined"
                result_type_generics_str = "#{fields_generic}, #{page_param}"
                result_data_generics_str = "<Fields, Page>"
                function_return_generics_str = "<Fields, Config[\"page\"]>"

                config_generic = "Config extends #{rpc_action_name_pascal}Config"
                function_generics_str = "#{fields_generic}, #{config_generic}"
                function_sig_str = "config: Config & { #{formatted_fields_field()}: Fields }"

                {result_type_generics_str, result_data_generics_str, function_generics_str,
                 function_sig_str, function_return_generics_str}

              action.type == :read and has_metadata ->
                metadata_param =
                  "MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []"

                result_type_generics_str = "#{fields_generic}, #{metadata_param}"
                result_data_generics_str = "<Fields, MetadataFields>"
                function_generics_str = "#{fields_generic}, #{metadata_param}"
                function_return_generics_str = "<Fields, MetadataFields>"

                {result_type_generics_str, result_data_generics_str, function_generics_str,
                 "config: #{config_type_ref}", function_return_generics_str}

              is_mutation and has_metadata ->
                metadata_param =
                  "MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []"

                result_type_generics_str = "#{fields_generic}, #{metadata_param}"
                result_data_generics_str = "<Fields>"
                function_generics_str = "#{fields_generic}, #{metadata_param}"
                function_return_generics_str = "<Fields, MetadataFields>"

                {result_type_generics_str, result_data_generics_str, function_generics_str,
                 "config: #{config_type_ref}", function_return_generics_str}

              true ->
                {fields_generic, "<Fields>", fields_generic, "config: #{config_type_ref}",
                 "<Fields>"}
            end

          result_type = """
          | { #{success_field}: true; data: Infer#{rpc_action_name_pascal}Result#{return_type_generics};#{mutation_metadata_field} }
          | {
              #{success_field}: false;
              #{errors_field}: Array<{
                #{formatted_error_type_field()}: string;
                #{formatted_error_message_field()}: string;
                #{formatted_error_field_path_field()}?: string;
                #{formatted_error_details_field()}: Record<string, string>;
              }>;
            }
          """

          result_type_def =
            "export type #{rpc_action_name_pascal}Result<#{result_type_generics}> = #{result_type};"

          {result_type_def, "#{rpc_action_name_pascal}Result#{function_return_generics}",
           function_generics, function_sig}

        true ->
          if has_metadata do
            action_metadata_field =
              " #{format_output_field(:metadata)}: Pick<#{rpc_action_name_pascal}Metadata, MetadataFields[number]>;"

            result_type = """
            | { #{success_field}: true; data: Infer#{rpc_action_name_pascal}Result;#{action_metadata_field} }
            | {
                #{success_field}: false;
                #{errors_field}: Array<{
                  #{formatted_error_type_field()}: string;
                  #{formatted_error_message_field()}: string;
                  #{formatted_error_field_path_field()}?: string;
                  #{formatted_error_details_field()}: Record<string, string>;
                }>;
              }
            """

            result_type_def =
              "export type #{rpc_action_name_pascal}Result<MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []> = #{result_type};"

            {result_type_def, "#{rpc_action_name_pascal}Result<MetadataFields>",
             "MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []",
             "config: #{config_type_ref}"}
          else
            result_type = """
            | { #{success_field}: true; data: Infer#{rpc_action_name_pascal}Result; }
            | {
                #{success_field}: false;
                #{errors_field}: Array<{
                  #{formatted_error_type_field()}: string;
                  #{formatted_error_message_field()}: string;
                  #{formatted_error_field_path_field()}?: string;
                  #{formatted_error_details_field()}: Record<string, string>;
                }>;
              }
            """

            result_type_def = "export type #{rpc_action_name_pascal}Result = #{result_type};"

            {result_type_def, "#{rpc_action_name_pascal}Result", "", "config: #{config_type_ref}"}
          end
      end

    generic_part = if generic_param != "", do: "<#{generic_param}>", else: ""

    payload_fields =
      build_payload_fields(resource, action, rpc_action_name, context,
        include_fields: has_fields,
        include_metadata_fields: has_metadata
      )

    payload_def = "{\n    #{Enum.join(payload_fields, ",\n    ")}\n  }"

    """
    #{config_type_export}#{result_type_def}

    export async function #{function_name}#{generic_part}(
      #{function_signature}
    ): Promise<#{return_type_def}> {
      const payload = #{payload_def};

      const headers: Record<string, string> = {
        "Content-Type": "application/json",
        ...config.headers,
      };

      const fetchFunction = config.customFetch || fetch;
      const fetchOptions: RequestInit = {
        ...config.fetchOptions,
        method: "POST",
        headers,
        body: JSON.stringify(payload),
      };

      const response = await fetchFunction(#{endpoint_process}, fetchOptions);

      if (!response.ok) {
        #{format_error_handler(error_response_func, success_field, errors_field)}
      }

      const result = await response.json();
      return result as #{return_type_def};
    }
    """
  end

  defp generate_validation_function(
         resource,
         action,
         rpc_action_name,
         endpoint_validate,
         error_response_func
       ) do
    function_name =
      AshTypescript.FieldFormatter.format_field(
        "validate_#{rpc_action_name}",
        AshTypescript.Rpc.output_field_formatter()
      )

    rpc_action_name_pascal = snake_to_pascal_case(rpc_action_name)
    context = get_action_context(resource, action)

    # Build config fields using helper (validation uses simple primary key type)
    config_fields =
      build_common_config_fields(resource, action, context,
        rpc_action_name: rpc_action_name,
        simple_primary_key: true
      )

    config_fields =
      config_fields ++
        [
          "  headers?: Record<string, string>;",
          "  fetchOptions?: RequestInit;",
          "  customFetch?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;"
        ]

    config_type_def = "{\n#{Enum.join(config_fields, "\n")}\n}"

    success_field = format_output_field(:success)
    errors_field = format_output_field(:errors)

    validation_result_type = """
    export type Validate#{rpc_action_name_pascal}Result =
      | { #{success_field}: true }
      | {
          #{success_field}: false;
          #{errors_field}: Array<{
            #{formatted_error_type_field()}: string;
            #{formatted_error_message_field()}: string;
            #{format_output_field(:field)}?: string;
            #{formatted_error_field_path_field()}?: string;
            #{formatted_error_details_field()}?: Record<string, any>;
          }>;
        };
    """

    # Build the validation payload using helper (no fields or filtering/pagination for validation)
    validation_payload_fields =
      build_payload_fields(resource, action, rpc_action_name, context,
        include_fields: false,
        include_filtering_pagination: false
      )

    validation_payload_def = "{\n    #{Enum.join(validation_payload_fields, ",\n    ")}\n  }"

    """
    #{validation_result_type}

    export async function #{function_name}(
      config: #{config_type_def}
    ): Promise<Validate#{rpc_action_name_pascal}Result> {
      const payload = #{validation_payload_def};

      const headers: Record<string, string> = {
        "Content-Type": "application/json",
        ...config.headers,
      };

      const fetchFunction = config.customFetch || fetch;
      const fetchOptions: RequestInit = {
        ...config.fetchOptions,
        method: "POST",
        headers,
        body: JSON.stringify(payload),
      };

      const response = await fetchFunction(#{endpoint_validate}, fetchOptions);

      if (!response.ok) {
        #{format_error_handler(error_response_func, success_field, errors_field)}
      }

      const result = await response.json();
      return result as Validate#{rpc_action_name_pascal}Result;
    }
    """
  end

  defp generate_channel_validation_function(resource, action, rpc_action_name) do
    function_name =
      AshTypescript.FieldFormatter.format_field(
        "validate_#{rpc_action_name}_channel",
        AshTypescript.Rpc.output_field_formatter()
      )

    rpc_action_name_pascal = snake_to_pascal_case(rpc_action_name)
    context = get_action_context(resource, action)

    # Build config fields using helper, then add channel-specific fields
    config_fields =
      ["  channel: Channel;"] ++
        build_common_config_fields(resource, action, context,
          rpc_action_name: rpc_action_name,
          simple_primary_key: true
        )

    result_handler_type = "(result: Validate#{rpc_action_name_pascal}Result) => void"
    error_handler_type = "any"
    timeout_handler_type = "() => void"

    config_fields =
      config_fields ++
        [
          "  resultHandler: #{result_handler_type};",
          "  errorHandler?: (error: #{error_handler_type}) => void;",
          "  timeoutHandler?: #{timeout_handler_type};",
          "  timeout?: number;"
        ]

    config_type_def = "{\n#{Enum.join(config_fields, "\n")}\n}"

    # Build the payload using helper (no fields or filtering/pagination for validation)
    payload_fields =
      build_payload_fields(resource, action, rpc_action_name, context,
        include_fields: false,
        include_filtering_pagination: false
      )

    payload_def = "{\n    #{Enum.join(payload_fields, ",\n    ")}\n  }"

    """
    export function #{function_name}(config: #{config_type_def}) {
      config.channel
        .push("validate", #{payload_def}, config.timeout)
        .receive("ok", config.resultHandler)
        .receive(
          "error",
          config.errorHandler
            ? config.errorHandler
            : (error: any) => {
                console.error(
                  "An error occurred while validating action #{rpc_action_name}:",
                  error,
                );
              },
        )
        .receive(
          "timeout",
          config.timeoutHandler
            ? config.timeoutHandler
            : () => {
                console.error("Timeout occurred while validating action #{rpc_action_name}");
              },
        );
    }
    """
  end

  defp generate_channel_execution_function(resource, action, rpc_action, rpc_action_name) do
    function_name =
      AshTypescript.FieldFormatter.format_field(
        "#{rpc_action_name}_channel",
        AshTypescript.Rpc.output_field_formatter()
      )

    rpc_action_name_pascal = snake_to_pascal_case(rpc_action_name)
    resource_name = build_resource_type_name(resource)
    context = get_action_context(resource, action)

    # Build config fields using helper, starting with channel field
    config_fields =
      ["  channel: Channel;"] ++
        build_common_config_fields(resource, action, context, rpc_action_name: rpc_action_name)

    {config_fields, has_fields, fields_generic} =
      if action.type != :destroy do
        case action.type do
          :action ->
            case action_returns_field_selectable_type?(action) do
              {:ok, type, _value} when type in [:resource, :array_of_resource] ->
                updated_fields = config_fields ++ ["  #{formatted_fields_field()}: Fields;"]

                {updated_fields, true, "Fields extends #{rpc_action_name_pascal}Fields"}

              {:ok, type, _fields}
              when type in [
                     :typed_map,
                     :array_of_typed_map,
                     :typed_struct,
                     :array_of_typed_struct
                   ] ->
                updated_fields =
                  config_fields ++
                    [
                      "  #{formatted_fields_field()}: Fields;"
                    ]

                {updated_fields, true, "Fields extends #{rpc_action_name_pascal}Fields"}

              {:ok, :unconstrained_map, _} ->
                # Unconstrained maps don't support field selection
                {config_fields, false, nil}

              _ ->
                {config_fields, false, nil}
            end

          _ ->
            updated_fields = config_fields ++ ["  #{formatted_fields_field()}: Fields;"]

            {updated_fields, true, "Fields extends #{rpc_action_name_pascal}Fields"}
        end
      else
        {config_fields, false, nil}
      end

    config_fields =
      if context.supports_filtering do
        config_fields ++ ["  #{format_output_field(:filter)}?: #{resource_name}FilterInput;"]
      else
        config_fields
      end

    config_fields =
      if context.supports_filtering do
        config_fields ++ ["  #{format_output_field(:sort)}?: string;"]
      else
        config_fields
      end

    config_fields =
      if context.supports_pagination do
        pagination_fields = generate_pagination_config_fields(action)
        config_fields ++ pagination_fields
      else
        config_fields
      end

    # Add metadataFields to config if metadata is enabled (same as RPC execution function)
    # Check if metadata is enabled based on show_metadata configuration
    has_metadata = metadata_enabled?(get_exposed_metadata_fields(rpc_action, action))

    config_fields =
      if has_metadata do
        metadata_fields_key = format_output_field(:metadata_fields)
        config_fields ++ ["  #{metadata_fields_key}?: MetadataFields;"]
      else
        config_fields
      end

    {result_handler_type, error_handler_type, timeout_handler_type, generic_part} =
      cond do
        action.type == :destroy ->
          if has_metadata do
            result_type = "#{rpc_action_name_pascal}Result<MetadataFields>"
            error_type = "any"
            timeout_type = "() => void"

            metadata_param =
              "MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []"

            {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}",
             "<#{metadata_param}>"}
          else
            result_type = "#{rpc_action_name_pascal}Result"
            error_type = "any"
            timeout_type = "() => void"
            {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}", ""}
          end

        has_fields ->
          # For actions with metadata, add MetadataFields generic
          if has_metadata do
            metadata_param =
              "MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []"

            result_type = "#{rpc_action_name_pascal}Result<Fields, MetadataFields>"
            error_type = "any"
            timeout_type = "() => void"

            {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}",
             "<#{fields_generic}, #{metadata_param}>"}
          else
            result_type = "#{rpc_action_name_pascal}Result<Fields>"
            error_type = "any"
            timeout_type = "() => void"

            {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}",
             "<#{fields_generic}>"}
          end

        true ->
          if has_metadata do
            result_type = "#{rpc_action_name_pascal}Result<MetadataFields>"
            error_type = "any"
            timeout_type = "() => void"

            metadata_param =
              "MetadataFields extends ReadonlyArray<keyof #{rpc_action_name_pascal}Metadata> = []"

            {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}",
             "<#{metadata_param}>"}
          else
            result_type = "#{rpc_action_name_pascal}Result"
            error_type = "any"
            timeout_type = "() => void"
            {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}", ""}
          end
      end

    config_fields =
      config_fields ++
        [
          "  resultHandler: #{result_handler_type};",
          "  errorHandler?: (error: #{error_handler_type}) => void;",
          "  timeoutHandler?: #{timeout_handler_type};",
          "  timeout?: number;"
        ]

    config_type_def = "{\n#{Enum.join(config_fields, "\n")}\n}"

    # Check if metadata is enabled based on show_metadata configuration (must match config type definition)
    has_metadata_for_payload = metadata_enabled?(get_exposed_metadata_fields(rpc_action, action))

    # Build the payload using helper - include metadata_fields only when metadata is exposed
    payload_fields =
      build_payload_fields(resource, action, rpc_action_name, context,
        include_fields: has_fields,
        include_metadata_fields: has_metadata_for_payload
      )

    payload_def = "{\n    #{Enum.join(payload_fields, ",\n    ")}\n  }"

    """
    export function #{function_name}#{generic_part}(config: #{config_type_def}) {
      config.channel
        .push("run", #{payload_def}, config.timeout)
        .receive("ok", config.resultHandler)
        .receive(
          "error",
          config.errorHandler
            ? config.errorHandler
            : (error: any) => {
                console.error(
                  "An error occurred while running action #{rpc_action_name}:",
                  error,
                );
              },
        )
        .receive(
          "timeout",
          config.timeoutHandler
            ? config.timeoutHandler
            : () => {
                console.error("Timeout occurred while running action #{rpc_action_name}");
              },
        );
    }
    """
  end

  defp generate_rpc_function(
         {resource, action, rpc_action},
         _resources_and_actions,
         endpoint_process,
         endpoint_validate,
         error_response_func,
         _otp_app
       ) do
    rpc_action_name = to_string(rpc_action.name)

    input_type = generate_input_type(resource, action, rpc_action_name)

    error_type =
      ValidationErrorSchemas.generate_validation_error_type(resource, action, rpc_action_name)

    zod_schema =
      if AshTypescript.Rpc.generate_zod_schemas?() do
        ZodSchemaGenerator.generate_zod_schema(resource, action, rpc_action_name)
      else
        ""
      end

    result_type = generate_result_type(resource, action, rpc_action, rpc_action_name)

    rpc_function =
      generate_rpc_execution_function(
        resource,
        action,
        rpc_action,
        rpc_action_name,
        endpoint_process,
        error_response_func
      )

    validation_function =
      generate_validation_function(
        resource,
        action,
        rpc_action_name,
        endpoint_validate,
        error_response_func
      )

    channel_function =
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        generate_channel_execution_function(resource, action, rpc_action, rpc_action_name)
      else
        ""
      end

    channel_validation_function =
      if AshTypescript.Rpc.generate_validation_functions?() and
           AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        generate_channel_validation_function(resource, action, rpc_action_name)
      else
        ""
      end

    function_parts = [rpc_function]

    function_parts =
      if validation_function != "" do
        function_parts ++ [validation_function]
      else
        function_parts
      end

    function_parts =
      if channel_validation_function != "" do
        function_parts ++ [channel_validation_function]
      else
        function_parts
      end

    function_parts =
      if channel_function != "" do
        function_parts ++ [channel_function]
      else
        function_parts
      end

    functions_section = Enum.join(function_parts, "\n\n")

    base_types = [input_type, error_type] |> Enum.reject(&(&1 == ""))

    output_parts =
      if zod_schema != "" do
        base_types ++ [zod_schema, result_type, functions_section]
      else
        base_types ++ [result_type, functions_section]
      end

    Enum.join(output_parts, "\n")
    |> String.trim_trailing("\n")
    |> then(&(&1 <> "\n"))
  end
end
