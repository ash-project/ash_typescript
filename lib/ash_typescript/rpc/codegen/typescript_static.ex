# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.TypescriptStatic do
  @moduledoc """
  Generates static TypeScript code that doesn't depend on specific resources.

  This includes:
  - Import statements (Zod, Phoenix Channel, custom imports)
  - Hook context type definitions
  - Utility types (TypedSchema, InferResult, pagination helpers, etc.)
  - Helper functions (CSRF token, RPC request executors)
  """

  import AshTypescript.Helpers

  @doc """
  Generates TypeScript import statements based on configuration.

  Includes:
  - Zod import (if zod schemas enabled)
  - Phoenix Channel import (if channel RPC actions enabled)
  - Custom imports from application config
  """
  def generate_imports do
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

  @doc """
  Generates TypeScript type definitions for hook context types.

  Hook context types are conditionally generated based on:
  - Whether hooks are enabled for each category
  - Whether a context type is configured
  """
  def generate_hook_context_types(hook_config) do
    action_context_type = Map.get(hook_config, :rpc_action_hook_context_type)
    validation_context_type = Map.get(hook_config, :rpc_validation_hook_context_type)
    action_channel_context_type = Map.get(hook_config, :rpc_action_channel_hook_context_type)

    validation_channel_context_type =
      Map.get(hook_config, :rpc_validation_channel_hook_context_type)

    action_hooks_enabled = AshTypescript.Rpc.rpc_action_hooks_enabled?()
    validation_hooks_enabled = AshTypescript.Rpc.rpc_validation_hooks_enabled?()
    action_channel_hooks_enabled = AshTypescript.Rpc.rpc_action_channel_hooks_enabled?()
    validation_channel_hooks_enabled = AshTypescript.Rpc.rpc_validation_channel_hooks_enabled?()

    parts = []

    parts =
      if action_hooks_enabled and action_context_type != nil and action_context_type != "" do
        parts ++
          [
            """
            // RPC Action Hook Context Type
            export type ActionHookContext = #{action_context_type};
            """
          ]
      else
        parts
      end

    parts =
      if validation_hooks_enabled and validation_context_type != nil and
           validation_context_type != "" do
        parts ++
          [
            """
            // RPC Validation Hook Context Type
            export type ValidationHookContext = #{validation_context_type};
            """
          ]
      else
        parts
      end

    parts =
      if action_channel_hooks_enabled and action_channel_context_type != nil and
           action_channel_context_type != "" do
        parts ++
          [
            """
            // RPC Action Channel Hook Context Type
            export type ActionChannelHookContext = #{action_channel_context_type};
            """
          ]
      else
        parts
      end

    parts =
      if validation_channel_hooks_enabled and validation_channel_context_type != nil and
           validation_channel_context_type != "" do
        parts ++
          [
            """
            // RPC Validation Channel Hook Context Type
            export type ValidationChannelHookContext = #{validation_channel_context_type};
            """
          ]
      else
        parts
      end

    if parts == [] do
      ""
    else
      Enum.join(parts, "\n") |> String.trim()
    end
  end

  @doc """
  Generates TypeScript utility types for field selection and type inference.

  Includes:
  - TypedSchema constraint
  - UnionToIntersection helper
  - InferUnionFieldValue helper
  - Field selection types
  - InferResult type
  - Pagination conditional types
  - SuccessDataFunc and ErrorData helpers
  - AshRpcError type
  """
  def generate_utility_types do
    """
    // Utility Types

    // Resource schema constraint
    type TypedSchema = {
      __type: "Resource" | "TypedMap" | "Union";
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
                  ? UnionSchema[UnionKey] extends { __array: true; __type: "TypedMap"; __primitiveFields: infer TypedMapFields }
                    ? FieldSelection[FieldIndex][UnionKey] extends any[]
                      ? Array<
                          UnionToIntersection<
                            {
                              [FieldIdx in keyof FieldSelection[FieldIndex][UnionKey]]: FieldSelection[FieldIndex][UnionKey][FieldIdx] extends TypedMapFields
                                ? FieldSelection[FieldIndex][UnionKey][FieldIdx] extends keyof UnionSchema[UnionKey]
                                  ? { [P in FieldSelection[FieldIndex][UnionKey][FieldIdx]]: UnionSchema[UnionKey][P] }
                                  : never
                                : never;
                            }[number]
                          >
                        > | null
                      : never
                    : UnionSchema[UnionKey] extends { __type: "TypedMap"; __primitiveFields: infer TypedMapFields }
                      ? FieldSelection[FieldIndex][UnionKey] extends any[]
                        ? UnionToIntersection<
                            {
                              [FieldIdx in keyof FieldSelection[FieldIndex][UnionKey]]: FieldSelection[FieldIndex][UnionKey][FieldIdx] extends TypedMapFields
                                ? FieldSelection[FieldIndex][UnionKey][FieldIdx] extends keyof UnionSchema[UnionKey]
                                  ? { [P in FieldSelection[FieldIndex][UnionKey][FieldIdx]]: UnionSchema[UnionKey][P] }
                                  : never
                                : never;
                            }[number]
                          > | null
                        : never
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
          : T[K] extends { __type: "TypedMap"; __primitiveFields: infer PrimitiveFields }
            ? PrimitiveFields[]
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
                    [UnionKey in keyof Omit<T[K], "__type" | "__primitiveFields">]?: T[K][UnionKey] extends TypedSchema
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
                : NonNullable<T[K]> extends { __type: "TypedMap"; __primitiveFields: infer TypedMapFields }
                  ? NonNullable<T[K]> extends { __array: true }
                    ? Field[K] extends any[]
                      ? null extends T[K]
                        ? Array<
                            UnionToIntersection<
                              {
                                [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends TypedMapFields
                                  ? Field[K][FieldIndex] extends keyof NonNullable<T[K]>
                                    ? { [P in Field[K][FieldIndex]]: NonNullable<T[K]>[P] }
                                    : never
                                  : never;
                              }[number]
                            >
                          > | null
                        : Array<
                            UnionToIntersection<
                              {
                                [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends TypedMapFields
                                  ? Field[K][FieldIndex] extends keyof NonNullable<T[K]>
                                    ? { [P in Field[K][FieldIndex]]: NonNullable<T[K]>[P] }
                                    : never
                                  : never;
                              }[number]
                            >
                          >
                      : never
                    : Field[K] extends any[]
                      ? null extends T[K]
                        ? UnionToIntersection<
                            {
                              [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends TypedMapFields
                                ? Field[K][FieldIndex] extends keyof NonNullable<T[K]>
                                  ? { [P in Field[K][FieldIndex]]: NonNullable<T[K]>[P] }
                                  : never
                                : never;
                            }[number]
                          > | null
                        : UnionToIntersection<
                            {
                              [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends TypedMapFields
                                ? Field[K][FieldIndex] extends keyof T[K]
                                  ? { [P in Field[K][FieldIndex]]: T[K][P] }
                                  : never
                                : never;
                            }[number]
                          >
                      : never
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
      SelectedFields extends UnifiedFieldSelection<T>[] | undefined,
    > = SelectedFields extends undefined
      ? {}
      : SelectedFields extends []
      ? {}
      : SelectedFields extends UnifiedFieldSelection<T>[]
      ? UnionToIntersection<
          {
            [K in keyof SelectedFields]: InferFieldValue<T, SelectedFields[K]>;
          }[number]
        >
      : {};

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
     * Represents an error from an unsuccessful RPC call.
     *
     * This type matches the error structure defined in the AshTypescript.Rpc.Error protocol.
     *
     * @example
     * const error: AshRpcError = {
     *   type: "invalid_changes",
     *   message: "Invalid value for field %{field}",
     *   shortMessage: "Invalid changes",
     *   vars: { field: "email" },
     *   fields: ["email"],
     *   path: ["user", "email"],
     *   details: { suggestion: "Provide a valid email address" }
     * }
     */
    export type AshRpcError = {
      /** Machine-readable error type (e.g., "invalid_changes", "not_found") */
      type: string;
      /** Full error message (may contain template variables like %{key}) */
      message: string;
      /** Concise version of the message */
      shortMessage: string;
      /** Variables to interpolate into the message template */
      vars: Record<string, any>;
      /** List of affected field names (for field-level errors) */
      fields: string[];
      /** Path to the error location in the data structure */
      path: string[];
      /** Optional map with extra details (e.g., suggestions, hints) */
      details?: Record<string, any>;
    }

    /**
     * Represents the result of a validation RPC call.
     *
     * All validation actions return this same structure, indicating either
     * successful validation or a list of validation errors.
     *
     * @example
     * // Successful validation
     * const result: ValidationResult = { success: true };
     *
     * // Failed validation
     * const result: ValidationResult = {
     *   success: false,
     *   errors: [
     *     {
     *       type: "required",
     *       message: "is required",
     *       shortMessage: "Required field",
     *       vars: { field: "email" },
     *       fields: ["email"],
     *       path: []
     *     }
     *   ]
     * };
     */
    export type ValidationResult =
      | { #{format_output_field(:success)}: true }
      | { #{format_output_field(:success)}: false; #{format_output_field(:errors)}: AshRpcError[]; };



    """
  end

  @doc """
  Generates TypeScript helper functions and configuration interfaces.

  Includes:
  - Configuration interfaces (ActionConfig, ValidationConfig, etc.)
  - CSRF token helpers
  - RPC request execution functions
  - Channel push execution functions
  """
  def generate_helper_functions(hook_config, endpoint_process, endpoint_validate) do
    action_before_hook = Map.get(hook_config, :rpc_action_before_request_hook)
    action_after_hook = Map.get(hook_config, :rpc_action_after_request_hook)
    validation_before_hook = Map.get(hook_config, :rpc_validation_before_request_hook)
    validation_after_hook = Map.get(hook_config, :rpc_validation_after_request_hook)
    action_channel_before_hook = Map.get(hook_config, :rpc_action_before_channel_push_hook)
    action_channel_after_hook = Map.get(hook_config, :rpc_action_after_channel_response_hook)

    validation_channel_before_hook =
      Map.get(hook_config, :rpc_validation_before_channel_push_hook)

    validation_channel_after_hook =
      Map.get(hook_config, :rpc_validation_after_channel_response_hook)

    action_hook_context_type =
      Map.get(hook_config, :rpc_action_hook_context_type, "Record<string, any>")

    validation_hook_context_type =
      Map.get(hook_config, :rpc_validation_hook_context_type, "Record<string, any>")

    action_channel_hook_context_type =
      Map.get(hook_config, :rpc_action_channel_hook_context_type, "Record<string, any>")

    validation_channel_hook_context_type =
      Map.get(hook_config, :rpc_validation_channel_hook_context_type, "Record<string, any>")

    action_helper =
      generate_action_rpc_request_helper(
        endpoint_process,
        action_before_hook,
        action_after_hook
      )

    validation_helper =
      if AshTypescript.Rpc.generate_validation_functions?() do
        generate_validation_rpc_request_helper(
          endpoint_validate,
          validation_before_hook,
          validation_after_hook
        )
      else
        ""
      end

    action_channel_helper =
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        generate_action_channel_push_helper(
          "run",
          action_channel_before_hook,
          action_channel_after_hook
        )
      else
        ""
      end

    validation_channel_helper =
      if AshTypescript.Rpc.generate_validation_functions?() and
           AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        generate_validation_channel_push_helper(
          "validate",
          validation_channel_before_hook,
          validation_channel_after_hook
        )
      else
        ""
      end

    validation_config_interface =
      if AshTypescript.Rpc.generate_validation_functions?() do
        """

        /**
         * Configuration options for validation RPC requests
         */
        export interface ValidationConfig {
          // Request data
          input?: Record<string, any>;

          // HTTP customization
          headers?: Record<string, string>;
          fetchOptions?: RequestInit;
          customFetch?: (
            input: RequestInfo | URL,
            init?: RequestInit,
          ) => Promise<Response>;

          // Hook context
          hookCtx?: #{validation_hook_context_type};
        }
        """
      else
        ""
      end

    action_channel_config_interface =
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        """

        /**
         * Configuration options for action channel RPC requests
         */
        export interface ActionChannelConfig {
          // Request data
          input?: Record<string, any>;
          primaryKey?: any;
          fields?: ReadonlyArray<string | Record<string, any>>;
          filter?: Record<string, any>;
          sort?: string;
          page?:
            | {
                limit?: number;
                offset?: number;
                count?: boolean;
              }
            | {
                limit?: number;
                after?: string;
                before?: string;
              };

          // Metadata
          metadataFields?: ReadonlyArray<string>;

          // Channel-specific
          channel: any; // Phoenix Channel
          resultHandler: (result: any) => void;
          errorHandler?: (error: any) => void;
          timeoutHandler?: () => void;
          timeout?: number;

          // Multitenancy
          tenant?: string;

          // Hook context
          hookCtx?: #{action_channel_hook_context_type};
        }
        """
      else
        ""
      end

    validation_channel_config_interface =
      if AshTypescript.Rpc.generate_validation_functions?() and
           AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        """

        /**
         * Configuration options for validation channel RPC requests
         */
        export interface ValidationChannelConfig {
          // Request data
          input?: Record<string, any>;
          primaryKey?: any;

          // Channel-specific
          channel: any; // Phoenix Channel
          resultHandler: (result: any) => void;
          errorHandler?: (error: any) => void;
          timeoutHandler?: () => void;
          timeout?: number;

          // Multitenancy
          tenant?: string;

          // Hook context
          hookCtx?: #{validation_channel_hook_context_type};
        }
        """
      else
        ""
      end

    """
    // Helper Functions

    /**
     * Configuration options for action RPC requests
     */
    export interface ActionConfig {
      // Request data
      input?: Record<string, any>;
      primaryKey?: any;
      fields?: Array<string | Record<string, any>>; // Field selection
      filter?: Record<string, any>; // Filter options (for reads)
      sort?: string; // Sort options
      page?:
        | {
            // Offset-based pagination
            limit?: number;
            offset?: number;
            count?: boolean;
          }
        | {
            // Keyset pagination
            limit?: number;
            after?: string;
            before?: string;
          };

      // Metadata
      metadataFields?: ReadonlyArray<string>;

      // HTTP customization
      headers?: Record<string, string>; // Custom headers
      fetchOptions?: RequestInit; // Fetch options (signal, cache, etc.)
      customFetch?: (
        input: RequestInfo | URL,
        init?: RequestInit,
      ) => Promise<Response>;

      // Multitenancy
      tenant?: string; // Tenant parameter

      // Hook context
      hookCtx?: #{action_hook_context_type};
    }
    #{validation_config_interface}
    #{action_channel_config_interface}
    #{validation_channel_config_interface}

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

    #{action_helper}

    #{validation_helper}

    #{action_channel_helper}

    #{validation_channel_helper}
    """
  end

  defp generate_action_rpc_request_helper(endpoint, before_hook, after_hook) do
    generate_rpc_request_helper_impl(
      "executeActionRpcRequest",
      "action RPC request",
      "ActionConfig",
      endpoint,
      before_hook,
      after_hook
    )
  end

  defp generate_validation_rpc_request_helper(endpoint, before_hook, after_hook) do
    generate_rpc_request_helper_impl(
      "executeValidationRpcRequest",
      "validation RPC request",
      "ValidationConfig",
      endpoint,
      before_hook,
      after_hook
    )
  end

  defp generate_rpc_request_helper_impl(
         function_name,
         description,
         config_type,
         endpoint,
         before_hook,
         after_hook
       ) do
    success_field = format_output_field(:success)
    errors_field = format_output_field(:errors)
    type_field = formatted_error_type_field()
    message_field = formatted_error_message_field()
    short_message_field = formatted_error_short_message_field()
    vars_field = formatted_error_vars_field()
    fields_field = formatted_error_fields_field()
    path_field = formatted_error_path_field()
    details_field = formatted_error_details_field()

    before_hook_code =
      if before_hook do
        """
            let processedConfig = config;
            if (#{before_hook}) {
              processedConfig = await #{before_hook}(payload.action, config);
            }
        """
      else
        """
            const processedConfig = config;
        """
      end

    after_hook_code =
      if after_hook do
        """
            if (#{after_hook}) {
              await #{after_hook}(payload.action, response, result, processedConfig);
            }
        """
      else
        ""
      end

    """
    /**
     * Internal helper function for making #{description}s
     * Handles hooks, request configuration, fetch execution, and error handling
     * @param config Configuration matching #{config_type}
     */
    async function #{function_name}<T>(
      payload: Record<string, any>,
      config: #{config_type}
    ): Promise<T> {
    #{before_hook_code}
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
        ...config.headers,
        ...processedConfig.headers,
      };

      const fetchFunction = config.customFetch || processedConfig.customFetch || fetch;
      const fetchOptions: RequestInit = {
        ...config.fetchOptions,
        ...processedConfig.fetchOptions,
        method: "POST",
        headers,
        body: JSON.stringify(payload),
      };

      const response = await fetchFunction(#{endpoint}, fetchOptions);
      const result = response.ok ? await response.json() : null;

    #{after_hook_code}
      if (!response.ok) {
        return {
          #{success_field}: false,
          #{errors_field}: [
            {
              #{type_field}: "network_error",
              #{message_field}: `Network request failed: ${response.statusText}`,
              #{short_message_field}: "Network error",
              #{vars_field}: { statusCode: response.status, statusText: response.statusText },
              #{fields_field}: [],
              #{path_field}: [],
              #{details_field}: { statusCode: response.status }
            }
          ],
        } as T;
      }

      return result as T;
    }
    """
  end

  defp generate_action_channel_push_helper(event, before_hook, after_hook) do
    generate_channel_push_helper_impl(
      "executeActionChannelPush",
      "action channel push",
      "ActionChannelConfig",
      event,
      before_hook,
      after_hook
    )
  end

  defp generate_validation_channel_push_helper(event, before_hook, after_hook) do
    generate_channel_push_helper_impl(
      "executeValidationChannelPush",
      "validation channel push",
      "ValidationChannelConfig",
      event,
      before_hook,
      after_hook
    )
  end

  defp generate_channel_push_helper_impl(
         function_name,
         description,
         config_type,
         event,
         before_hook,
         after_hook
       ) do
    before_hook_code =
      if before_hook do
        """
            let processedConfig = config;
            if (#{before_hook}) {
              processedConfig = await #{before_hook}(payload.action, config);
            }
        """
      else
        """
            const processedConfig = config;
        """
      end

    after_ok_hook_code =
      if after_hook do
        """
              if (#{after_hook}) {
                await #{after_hook}(payload.action, "ok", result, processedConfig);
              }
        """
      else
        ""
      end

    after_error_hook_code =
      if after_hook do
        """
              if (#{after_hook}) {
                await #{after_hook}(payload.action, "error", error, processedConfig);
              }
        """
      else
        ""
      end

    after_timeout_hook_code =
      if after_hook do
        """
              if (#{after_hook}) {
                await #{after_hook}(payload.action, "timeout", undefined, processedConfig);
              }
        """
      else
        ""
      end

    """
    /**
     * Internal helper function for making #{description} requests
     * Handles hooks and channel push with receive handlers
     * @param config Configuration matching #{config_type}
     */
    async function #{function_name}<T>(
      channel: any,
      payload: Record<string, any>,
      timeout: number | undefined,
      config: #{config_type}
    ) {
    #{before_hook_code}
      const effectiveTimeout = timeout;

      channel
        .push("#{event}", payload, effectiveTimeout)
        .receive("ok", async (result: T) => {
    #{after_ok_hook_code}
          config.resultHandler(result);
        })
        .receive("error", async (error: any) => {
    #{after_error_hook_code}
          (config.errorHandler
            ? config.errorHandler
            : (error: any) => {
                console.error(
                  \`An error occurred while running action \${payload.action}:\`,
                  error
                );
              })(error);
        })
        .receive("timeout", async () => {
    #{after_timeout_hook_code}
          (config.timeoutHandler
            ? config.timeoutHandler
            : () => {
                console.error(\`Timeout occurred while running action \${payload.action}\`);
              })();
        });
    }
    """
  end
end
