# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.UtilityTypes do
  @moduledoc """
  Generates TypeScript utility types for field selection and type inference.

  These types are shared between RPC and typed controller code generation,
  including TypedSchema, UnionToIntersection, InferResult, pagination helpers,
  and error types.
  """

  import AshTypescript.Helpers

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
    fmt = fn field -> AshTypescript.FieldFormatter.format_field_name(field, AshTypescript.Rpc.output_field_formatter()) end

    """
    // Utility Types

    // Sort string type — allows optional direction prefix on sort field names
    // Prefixes per Ash.Query.sort/3: + (asc), - (desc), ++ (asc_nils_first), -- (desc_nils_last)
    export type SortString<T extends string> = T | `+${T}` | `-${T}` | `++${T}` | `--${T}`;

    // Resource schema constraint
    export type TypedSchema = {
      __type: "Resource" | "TypedMap" | "Union";
      __primitiveFields: string;
    };

    // Clean public mapping
    export type Clean<T> = T extends null | undefined ? T :
      T extends { __type: "Relationship", __array: true, __resource: infer R } ? Array<Clean<R>> :
      T extends { __type: "Relationship", __resource: infer R } ? Clean<R> :
      T extends { __type: "ComplexCalculation", __returnType: infer R } ? Clean<R> :
      T extends { __type: "Union" } ? Omit<T, "__type" | "__primitiveFields"> :
      T extends { __type: "Resource" | "TypedMap" } ? { [K in keyof Omit<T, "__type" | "__primitiveFields">]: Clean<T[K]> } :
      T extends Array<infer E> ? Array<Clean<E>> :
      T;

    // Generic Filter operations
    export type GenericFilter<T> = { 
      #{fmt.("eq")}?: T; 
      #{fmt.("not_eq")}?: T; 
      #{fmt.("in")}?: T[]; 
      #{fmt.("is_nil")}?: boolean; 
    };

    export type StringFilter = GenericFilter<string> & { 
      #{fmt.("contains")}?: string; 
      #{fmt.("icontains")}?: string; 
      #{fmt.("like")}?: string; 
      #{fmt.("ilike")}?: string;
    };

    export type NumberFilter<T> = GenericFilter<T> & { 
      #{fmt.("gt")}?: T; 
      #{fmt.("greater_than")}?: T; 
      #{fmt.("gte")}?: T; 
      #{fmt.("greater_than_or_equal")}?: T; 
      #{fmt.("lt")}?: T; 
      #{fmt.("less_than")}?: T; 
      #{fmt.("lte")}?: T; 
      #{fmt.("less_than_or_equal")}?: T; 
    };

    export type DateFilter<T> = GenericFilter<T> & { 
      #{fmt.("gt")}?: T; 
      #{fmt.("greater_than")}?: T; 
      #{fmt.("gte")}?: T; 
      #{fmt.("greater_than_or_equal")}?: T; 
      #{fmt.("lt")}?: T; 
      #{fmt.("less_than")}?: T; 
      #{fmt.("lte")}?: T; 
      #{fmt.("less_than_or_equal")}?: T; 
    };

    export type BooleanFilter = GenericFilter<boolean>;
    
    export type AtomFilter = GenericFilter<string>;

    // Utility type to convert union to intersection
    export type UnionToIntersection<U> = (U extends any ? (k: U) => void : never) extends (
      k: infer I,
    ) => void
      ? I
      : never;

    // Helper type to infer union field values, avoiding duplication between array and non-array unions
    export type InferUnionFieldValue<
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
                  ? NonNullable<UnionSchema[UnionKey]> extends { __array: true; __type: "TypedMap"; __primitiveFields: infer TypedMapFields }
                    ? FieldSelection[FieldIndex][UnionKey] extends any[]
                      ? Array<
                          UnionToIntersection<
                            {
                              [FieldIdx in keyof FieldSelection[FieldIndex][UnionKey]]: FieldSelection[FieldIndex][UnionKey][FieldIdx] extends TypedMapFields
                                ? FieldSelection[FieldIndex][UnionKey][FieldIdx] extends keyof NonNullable<UnionSchema[UnionKey]>
                                  ? { [P in FieldSelection[FieldIndex][UnionKey][FieldIdx]]: NonNullable<UnionSchema[UnionKey]>[P] }
                                  : never
                                : never;
                            }[number]
                          >
                        > | null
                      : never
                    : NonNullable<UnionSchema[UnionKey]> extends { __type: "TypedMap"; __primitiveFields: infer TypedMapFields }
                      ? FieldSelection[FieldIndex][UnionKey] extends any[]
                        ? UnionToIntersection<
                            {
                              [FieldIdx in keyof FieldSelection[FieldIndex][UnionKey]]: FieldSelection[FieldIndex][UnionKey][FieldIdx] extends TypedMapFields
                                ? FieldSelection[FieldIndex][UnionKey][FieldIdx] extends keyof NonNullable<UnionSchema[UnionKey]>
                                  ? { [P in FieldSelection[FieldIndex][UnionKey][FieldIdx]]: NonNullable<UnionSchema[UnionKey]>[P] }
                                  : never
                                : never;
                            }[number]
                          > | null
                        : never
                      : NonNullable<UnionSchema[UnionKey]> extends TypedSchema
                        ? InferResult<NonNullable<UnionSchema[UnionKey]>, FieldSelection[FieldIndex][UnionKey]>
                        : never
                  : never;
              }
            : never;
      }[number]
    >;

    export type HasComplexFields<T extends TypedSchema> = keyof Omit<
      T,
      "__primitiveFields" | "__type" | T["__primitiveFields"]
    > extends never
      ? false
      : true;

    export type ComplexFieldKeys<T extends TypedSchema> = keyof Omit<
      T,
      "__primitiveFields" | "__type" | T["__primitiveFields"]
    >;

    export type LeafFieldSelection<T extends TypedSchema> = T["__primitiveFields"];

    export type ComplexFieldSelection<T extends TypedSchema> = {
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
          : T[K] extends { __type: "TypedMap" }
            ? NonNullable<T[K]> extends TypedSchema
              ? UnifiedFieldSelection<NonNullable<T[K]>>[]
              : never
            : T[K] extends { __type: "Union"; __primitiveFields: infer PrimitiveFields }
              ? T[K] extends { __array: true }
                ? (PrimitiveFields | {
                    [UnionKey in keyof Omit<T[K], "__type" | "__primitiveFields" | "__array">]?: NonNullable<T[K][UnionKey]> extends { __type: "TypedMap"; __primitiveFields: any }
                      ? NonNullable<T[K][UnionKey]>["__primitiveFields"][]
                      : NonNullable<T[K][UnionKey]> extends TypedSchema
                        ? UnifiedFieldSelection<NonNullable<T[K][UnionKey]>>[]
                        : never;
                  })[]
                : (PrimitiveFields | {
                    [UnionKey in keyof Omit<T[K], "__type" | "__primitiveFields">]?: NonNullable<T[K][UnionKey]> extends { __type: "TypedMap"; __primitiveFields: any }
                      ? NonNullable<T[K][UnionKey]>["__primitiveFields"][]
                      : NonNullable<T[K][UnionKey]> extends TypedSchema
                        ? UnifiedFieldSelection<NonNullable<T[K][UnionKey]>>[]
                        : never;
                  })[]
                : NonNullable<T[K]> extends TypedSchema
                  ? UnifiedFieldSelection<NonNullable<T[K]>>[]
                  : never;
    };

    // Main type: Use explicit base case detection to prevent infinite recursion
    export type UnifiedFieldSelection<T extends TypedSchema> =
      HasComplexFields<T> extends false
        ? LeafFieldSelection<T> // Base case: only primitives, no recursion
        : LeafFieldSelection<T> | ComplexFieldSelection<T>; // Recursive case

    export type InferFieldValue<
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
                                [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends infer E
                                  ? E extends TypedMapFields
                                    ? E extends keyof NonNullable<T[K]>
                                      ? { [P in E]: NonNullable<T[K]>[P] }
                                      : never
                                    : E extends Record<string, any>
                                      ? {
                                          [NestedKey in keyof E]: NestedKey extends keyof NonNullable<T[K]>
                                            ? NonNullable<NonNullable<T[K]>[NestedKey]> extends TypedSchema
                                              ? null extends NonNullable<T[K]>[NestedKey]
                                                ? InferResult<NonNullable<NonNullable<T[K]>[NestedKey]>, E[NestedKey]> | null
                                                : InferResult<NonNullable<NonNullable<T[K]>[NestedKey]>, E[NestedKey]>
                                              : never
                                            : never;
                                        }
                                      : E extends keyof NonNullable<T[K]>
                                        ? { [P in E]: NonNullable<T[K]>[P] }
                                        : never
                                  : never;
                              }[number]
                            >
                          > | null
                        : Array<
                            UnionToIntersection<
                              {
                                [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends infer E
                                  ? E extends TypedMapFields
                                    ? E extends keyof NonNullable<T[K]>
                                      ? { [P in E]: NonNullable<T[K]>[P] }
                                      : never
                                    : E extends Record<string, any>
                                      ? {
                                          [NestedKey in keyof E]: NestedKey extends keyof NonNullable<T[K]>
                                            ? NonNullable<NonNullable<T[K]>[NestedKey]> extends TypedSchema
                                              ? null extends NonNullable<T[K]>[NestedKey]
                                                ? InferResult<NonNullable<NonNullable<T[K]>[NestedKey]>, E[NestedKey]> | null
                                                : InferResult<NonNullable<NonNullable<T[K]>[NestedKey]>, E[NestedKey]>
                                              : never
                                            : never;
                                        }
                                      : E extends keyof NonNullable<T[K]>
                                        ? { [P in E]: NonNullable<T[K]>[P] }
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
                              [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends infer E
                                ? E extends TypedMapFields
                                  ? E extends keyof NonNullable<T[K]>
                                    ? { [P in E]: NonNullable<T[K]>[P] }
                                    : never
                                  : E extends Record<string, any>
                                    ? {
                                        [NestedKey in keyof E]: NestedKey extends keyof NonNullable<T[K]>
                                          ? NonNullable<NonNullable<T[K]>[NestedKey]> extends TypedSchema
                                            ? null extends NonNullable<T[K]>[NestedKey]
                                              ? InferResult<NonNullable<NonNullable<T[K]>[NestedKey]>, E[NestedKey]> | null
                                              : InferResult<NonNullable<NonNullable<T[K]>[NestedKey]>, E[NestedKey]>
                                            : never
                                          : never;
                                      }
                                    : E extends keyof NonNullable<T[K]>
                                      ? { [P in E]: NonNullable<T[K]>[P] }
                                      : never
                                : never;
                            }[number]
                          > | null
                        : UnionToIntersection<
                            {
                              [FieldIndex in keyof Field[K]]: Field[K][FieldIndex] extends infer E
                                ? E extends TypedMapFields
                                  ? E extends keyof T[K]
                                    ? { [P in E]: T[K][P] }
                                    : never
                                  : E extends Record<string, any>
                                    ? {
                                        [NestedKey in keyof E]: NestedKey extends keyof NonNullable<T[K]>
                                          ? NonNullable<NonNullable<T[K]>[NestedKey]> extends TypedSchema
                                            ? null extends NonNullable<T[K]>[NestedKey]
                                              ? InferResult<NonNullable<NonNullable<T[K]>[NestedKey]>, E[NestedKey]> | null
                                              : InferResult<NonNullable<NonNullable<T[K]>[NestedKey]>, E[NestedKey]>
                                            : never
                                          : never;
                                      }
                                    : E extends keyof NonNullable<T[K]>
                                      ? { [P in E]: NonNullable<T[K]>[P] }
                                      : never
                                : never;
                            }[number]
                          >
                      : never
                  : T[K] extends { __type: "Union"; __primitiveFields: any }
                    ? T[K] extends { __array: true }
                      ? Field[K] extends any[]
                        ? null extends T[K]
                          ? Array<InferUnionFieldValue<T[K], Field[K]>> | null
                          : Array<InferUnionFieldValue<T[K], Field[K]>>
                        : never
                      : Field[K] extends any[]
                        ? null extends T[K]
                          ? InferUnionFieldValue<T[K], Field[K]> | null
                          : InferUnionFieldValue<T[K], Field[K]>
                        : never
                      : NonNullable<T[K]> extends TypedSchema
                        ? null extends T[K]
                          ? InferResult<NonNullable<T[K]>, Field[K]> | null
                          : InferResult<NonNullable<T[K]>, Field[K]>
                        : never
              : never;
          }
        : never;

    export type InferResult<
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
    export type HasPaginationParams<Page> =
      Page extends { offset: any } ? true :
      Page extends { after: any } ? true :
      Page extends { before: any } ? true :
      false;

    // Infer which pagination type is being used from the page config
    export type InferPaginationType<Page> =
      Page extends { offset: any } ? "offset" :
      Page extends { after: any } | { before: any } ? "keyset" :
      never;

    // Returns either non-paginated (array) or paginated result based on page params
    // For single pagination type support (offset-only or keyset-only)
    // @ts-ignore
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    export type ConditionalPaginatedResult<
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
    export type ConditionalPaginatedResultMixed<
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
      { #{formatted_success_field()}: true }
    >["#{formatted_data_field()}"];


    export type ErrorData<T extends (...args: any[]) => Promise<any>> = Extract<
      Awaited<ReturnType<T>>,
      { #{formatted_success_field()}: false }
    >["#{formatted_errors_field()}"];

    /**
     * Represents an error from an unsuccessful RPC call.
     *
     * This type matches the error structure defined in the AshTypescript.Rpc.Error protocol.
     *
     * @example
     * const error: AshRpcError = {
     *   #{formatted_error_type_field()}: "invalid_changes",
     *   #{formatted_error_message_field()}: "Invalid value for field %{field}",
     *   #{formatted_error_short_message_field()}: "Invalid changes",
     *   #{formatted_error_vars_field()}: { field: "email" },
     *   #{formatted_error_fields_field()}: ["email"],
     *   #{formatted_error_path_field()}: ["user", "email"],
     *   #{formatted_error_details_field()}: { suggestion: "Provide a valid email address" }
     * }
     */
    export type AshRpcError = {
      /** Machine-readable error type (e.g., "invalid_changes", "not_found") */
      #{formatted_error_type_field()}: string;
      /** Full error message (may contain template variables like %{key}) */
      #{formatted_error_message_field()}: string;
      /** Concise version of the message */
      #{formatted_error_short_message_field()}: string;
      /** Variables to interpolate into the message template */
      #{formatted_error_vars_field()}: Record<string, any>;
      /** List of affected field names (for field-level errors) */
      #{formatted_error_fields_field()}: string[];
      /** Path to the error location in the data structure */
      #{formatted_error_path_field()}: string[];
      /** Optional map with extra details (e.g., suggestions, hints) */
      #{formatted_error_details_field()}?: Record<string, any>;
    }

    /**
     * Represents the result of a validation RPC call.
     *
     * All validation actions return this same structure, indicating either
     * successful validation or a list of validation errors.
     *
     * @example
     * // Successful validation
     * const result: ValidationResult = { #{formatted_success_field()}: true };
     *
     * // Failed validation
     * const result: ValidationResult = {
     *   #{formatted_success_field()}: false,
     *   #{formatted_errors_field()}: [
     *     {
     *       #{formatted_error_type_field()}: "required",
     *       #{formatted_error_message_field()}: "is required",
     *       #{formatted_error_short_message_field()}: "Required field",
     *       #{formatted_error_vars_field()}: { field: "email" },
     *       #{formatted_error_fields_field()}: ["email"],
     *       #{formatted_error_path_field()}: []
     *     }
     *   ]
     * };
     */
    export type ValidationResult =
      | { #{formatted_success_field()}: true }
      | { #{formatted_success_field()}: false; #{formatted_errors_field()}: AshRpcError[]; };



    """
  end
end
