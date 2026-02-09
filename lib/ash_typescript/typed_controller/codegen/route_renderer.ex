# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Codegen.RouteRenderer do
  @moduledoc """
  Generates TypeScript functions for typed controller routes.

  - GET routes generate path helper functions.
  - Mutation routes (POST/PATCH/PUT/DELETE) generate typed action functions
    with input types derived from route arguments.
  """

  import AshTypescript.Helpers, only: [format_output_field: 1]
  import AshTypescript.Codegen.TypeMapper, only: [get_ts_input_type: 1]

  @mutation_methods [:post, :patch, :put, :delete]

  @doc """
  Renders TypeScript code for a single route.

  GET routes produce path helpers. Mutation routes produce typed async
  functions that call `fetch` with the correct method and typed input.
  """
  def render(route_info) do
    if route_info.method in @mutation_methods do
      render_action_function(route_info)
    else
      render_path_helper(route_info)
    end
  end

  defp render_path_helper(route_info) do
    %{
      route: route,
      path: path,
      path_params: path_params,
      scope_prefix: scope_prefix
    } = route_info

    function_name = build_function_name(route.name, scope_prefix, :path)

    path_param_args =
      Enum.map(path_params, fn param ->
        "#{format_output_field(param)}: string"
      end)

    params = Enum.join(path_param_args, ", ")
    url_expr = build_url_template(path, path_params)
    jsdoc = build_jsdoc(route, path)

    """
    #{jsdoc}
    export function #{function_name}(#{params}): string {
      return #{url_expr};
    }
    """
  end

  defp render_action_function(route_info) do
    %{
      route: route,
      path: path,
      method: method,
      path_params: path_params,
      scope_prefix: scope_prefix
    } = route_info

    function_name = build_function_name(route.name, scope_prefix, :action)
    method_upper = method |> to_string() |> String.upcase()

    input_fields = build_input_fields(route)
    has_input = input_fields != []
    has_path_params = path_params != []

    input_type_def =
      if has_input do
        type_name = build_input_type_name(route.name, scope_prefix)
        build_input_type_definition(type_name, input_fields) <> "\n"
      else
        ""
      end

    path_param =
      if has_path_params do
        path_fields =
          Enum.map_join(path_params, ", ", fn param ->
            "#{format_output_field(param)}: string"
          end)

        [format_output_field(:path) <> ": { " <> path_fields <> " }"]
      else
        []
      end

    input_param =
      if has_input do
        type_name = build_input_type_name(route.name, scope_prefix)
        [format_output_field(:input) <> ": " <> type_name]
      else
        []
      end

    config_param = [
      format_output_field(:config) <>
        "?: { " <> format_output_field(:headers) <> "?: Record<string, string> }"
    ]

    all_params = path_param ++ input_param ++ config_param
    params = Enum.join(all_params, ", ")

    url_expr = build_action_url_template(path, path_params)
    jsdoc = build_action_jsdoc(route, method_upper, path)

    body_line =
      if has_input do
        "\n    body: JSON.stringify(#{format_output_field(:input)}),"
      else
        ""
      end

    config_var = format_output_field(:config)
    headers_field = format_output_field(:headers)

    input_type_def <>
      """
      #{jsdoc}
      export async function #{function_name}(#{params}): Promise<Response> {
        return fetch(#{url_expr}, {
          method: "#{method_upper}",
          headers: {
            "Content-Type": "application/json",
            ...#{config_var}?.#{headers_field},
          },#{body_line}
        });
      }
      """
  end

  defp build_input_fields(route) do
    route.arguments
    |> Enum.map(fn arg ->
      optional = arg.allow_nil? || arg.default != nil
      ts_type = get_ts_input_type(%{type: arg.type, constraints: arg.constraints || []})
      {format_output_field(arg.name), ts_type, optional}
    end)
  end

  defp build_input_type_name(action_name, nil) do
    Macro.camelize("#{action_name}_input")
  end

  defp build_input_type_name(action_name, scope_prefix) do
    Macro.camelize("#{scope_prefix}_#{action_name}_input")
  end

  defp build_input_type_definition(type_name, fields) do
    field_defs =
      Enum.map_join(fields, "\n", fn {name, ts_type, optional} ->
        opt = if optional, do: "?", else: ""
        "  #{name}#{opt}: #{ts_type};"
      end)

    "export type #{type_name} = {\n#{field_defs}\n};"
  end

  defp build_function_name(action_name, nil, :path) do
    format_output_field(:"#{action_name}_path")
  end

  defp build_function_name(action_name, scope_prefix, :path) do
    format_output_field(:"#{scope_prefix}_#{action_name}_path")
  end

  defp build_function_name(action_name, nil, :action) do
    format_output_field(action_name)
  end

  defp build_function_name(action_name, scope_prefix, :action) do
    format_output_field(:"#{scope_prefix}_#{action_name}")
  end

  defp build_url_template(nil, _path_params), do: "\"\""
  defp build_url_template(path, []), do: "\"#{path}\""

  defp build_url_template(path, path_params) do
    template =
      Enum.reduce(path_params, path, fn param, acc ->
        String.replace(acc, ":#{param}", "${#{format_output_field(param)}}")
      end)

    "`#{template}`"
  end

  defp build_action_url_template(nil, _path_params), do: "\"\""
  defp build_action_url_template(path, []), do: "\"#{path}\""

  defp build_action_url_template(path, path_params) do
    path_var = format_output_field(:path)

    template =
      Enum.reduce(path_params, path, fn param, acc ->
        String.replace(acc, ":#{param}", "${#{path_var}.#{format_output_field(param)}}")
      end)

    "`#{template}`"
  end

  defp build_jsdoc(route, path) do
    lines = ["/**"]

    lines =
      if route.description do
        lines ++ [" * #{route.description}"]
      else
        lines ++ [" * Path helper for #{path || ""}"]
      end

    lines = maybe_add_deprecated(lines, route)
    lines = lines ++ [" */"]
    Enum.join(lines, "\n")
  end

  defp build_action_jsdoc(route, method_upper, path) do
    lines = ["/**"]

    lines =
      if route.description do
        lines ++ [" * #{route.description}"]
      else
        lines ++ [" * #{method_upper} #{path || ""}"]
      end

    lines = maybe_add_deprecated(lines, route)
    lines = lines ++ [" */"]
    Enum.join(lines, "\n")
  end

  defp maybe_add_deprecated(lines, route) do
    if route.deprecated do
      deprecation_msg =
        if is_binary(route.deprecated),
          do: route.deprecated,
          else: "This route is deprecated"

      lines ++ [" * @deprecated #{deprecation_msg}"]
    else
      lines
    end
  end
end
