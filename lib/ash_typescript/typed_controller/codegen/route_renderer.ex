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
    if route_info.method in @mutation_methods and AshTypescript.typed_controller_mode() == :full do
      render_path_helper(route_info) <> "\n" <> render_action_function(route_info)
    else
      render_path_helper(route_info)
    end
  end

  defp render_path_helper(route_info) do
    %{
      route: route,
      path: path,
      method: method,
      path_params: path_params,
      scope_prefix: scope_prefix
    } = route_info

    function_name = build_function_name(route.name, scope_prefix, :path)
    style = AshTypescript.typed_controller_path_params_style()

    path_param_args = build_path_param_args(route, path_params, style)

    is_mutation = method in @mutation_methods
    query_args = if is_mutation, do: [], else: get_query_args(route, path_params)

    {query_param, query_body_lines} = build_query_param_and_body(query_args)

    all_params =
      path_param_args ++
        if(query_param, do: [query_param], else: [])

    params = Enum.join(all_params, ", ")
    jsdoc = build_jsdoc(route, path)

    use_path_prefix = style == :object and path_params != []

    if query_args == [] do
      url_expr = build_url_template(path, path_params, use_path_prefix)

      """
      #{jsdoc}
      export function #{function_name}(#{params}): string {
        return #{url_expr};
      }
      """
    else
      url_expr = build_url_template_to_variable(path, path_params, use_path_prefix)
      body = Enum.join(query_body_lines, "\n")

      """
      #{jsdoc}
      export function #{function_name}(#{params}): string {
        #{url_expr}
      #{body}
        const qs = searchParams.toString();
        return qs ? `${base}?${qs}` : base;
      }
      """
    end
  end

  defp get_path_param_type(route, param) do
    case Enum.find(route.arguments, &(&1.name == param)) do
      nil -> "string"
      arg -> get_ts_input_type(%{type: arg.type, constraints: arg.constraints || []})
    end
  end

  defp get_query_args(route, path_params) do
    path_param_set = MapSet.new(path_params)

    route.arguments
    |> Enum.reject(fn arg -> MapSet.member?(path_param_set, arg.name) end)
  end

  defp build_query_param_and_body([]), do: {nil, []}

  defp build_query_param_and_body(query_args) do
    any_required = Enum.any?(query_args, fn arg -> !arg.allow_nil? && arg.default == nil end)
    optional_marker = if any_required, do: "", else: "?"

    fields =
      Enum.map_join(query_args, "; ", fn arg ->
        ts_type = get_ts_input_type(%{type: arg.type, constraints: arg.constraints || []})
        opt = if arg.allow_nil? || arg.default != nil, do: "?", else: ""
        "#{format_output_field(arg.name)}#{opt}: #{ts_type}"
      end)

    param = "query#{optional_marker}: { #{fields} }"

    body_lines =
      ["  const searchParams = new URLSearchParams();"] ++
        Enum.map(query_args, fn arg ->
          field = format_output_field(arg.name)
          required = !arg.allow_nil? && arg.default == nil

          if required do
            "  searchParams.set(\"#{field}\", String(query.#{field}));"
          else
            "  if (query?.#{field} !== undefined) searchParams.set(\"#{field}\", String(query.#{field}));"
          end
        end)

    {param, body_lines}
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

    input_fields = build_input_fields(route, path_params)
    has_input = input_fields != []
    style = AshTypescript.typed_controller_path_params_style()

    input_type_def =
      if has_input do
        type_name = build_input_type_name(route.name, scope_prefix)
        build_input_type_definition(type_name, input_fields) <> "\n"
      else
        ""
      end

    path_param = build_path_param_args(route, path_params, style)

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

    use_path_prefix = style == :object and path_params != []
    url_expr = build_url_template(path, path_params, use_path_prefix)
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

  defp build_input_fields(route, path_params) do
    path_param_set = MapSet.new(path_params)

    route.arguments
    |> Enum.reject(fn arg -> MapSet.member?(path_param_set, arg.name) end)
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

  defp build_path_param_args(_route, [], _style), do: []

  defp build_path_param_args(route, path_params, :object) do
    path_fields =
      Enum.map_join(path_params, ", ", fn param ->
        ts_type = get_path_param_type(route, param)
        "#{format_output_field(param)}: #{ts_type}"
      end)

    [format_output_field(:path) <> ": { " <> path_fields <> " }"]
  end

  defp build_path_param_args(route, path_params, :args) do
    Enum.map(path_params, fn param ->
      ts_type = get_path_param_type(route, param)
      "#{format_output_field(param)}: #{ts_type}"
    end)
  end

  defp build_url_template(nil, _path_params, _use_path_prefix), do: "\"\""
  defp build_url_template(path, [], _use_path_prefix), do: "\"#{path}\""

  defp build_url_template(path, path_params, use_path_prefix) do
    template =
      Enum.reduce(path_params, path, fn param, acc ->
        interpolation =
          if use_path_prefix do
            "${#{format_output_field(:path)}.#{format_output_field(param)}}"
          else
            "${#{format_output_field(param)}}"
          end

        String.replace(acc, ":#{param}", interpolation)
      end)

    "`#{template}`"
  end

  defp build_url_template_to_variable(nil, _path_params, _use_path_prefix),
    do: "const base = \"\";"

  defp build_url_template_to_variable(path, [], _use_path_prefix), do: "const base = \"#{path}\";"

  defp build_url_template_to_variable(path, path_params, use_path_prefix) do
    template =
      Enum.reduce(path_params, path, fn param, acc ->
        interpolation =
          if use_path_prefix do
            "${#{format_output_field(:path)}.#{format_output_field(param)}}"
          else
            "${#{format_output_field(param)}}"
          end

        String.replace(acc, ":#{param}", interpolation)
      end)

    "const base = `#{template}`;"
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
