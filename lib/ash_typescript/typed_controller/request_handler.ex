# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.RequestHandler do
  @moduledoc """
  Handles request lifecycle for typed controller routes.

  The route's shape comes from the decorated manifest
  (`AshTypescript.Manifest.Custom.route/3`), so the typed controller module
  must be listed in the manifest module's `typed_controllers:` option. Casting
  data (type, constraints, `default`) comes from the DSL route.

  Request keys are resolved per source, never from the merged params:

    * `conn.path_params` keys by router segment name (`path_input_names`)
    * `conn.query_params` and `conn.body_params` keys by the argument's client
      name (`client_input_names`)

  Phoenix reserved keys (`_format`, `action`, `controller`), `_`-prefixed keys
  and keys matching no argument (another casing, an undeclared name, a segment
  name outside the path) are dropped. An argument reached by more than one key
  or source is rejected as `ambiguous_param`.

  Each value is then formatted with `AshRpc.ValueFormatter.format_input/3`:
  nested keys must be client names of their decorated type, and each miss is
  an `unknown_input` error whose `path` starts with the argument's client
  name. Finally the value is cast with `Ash.Type.cast_input/3` and
  `Ash.Type.apply_constraints/3`, and `allow_nil?` / `default` are applied.

  Only declared arguments are passed to the handler (inline fn/2 or a module
  implementing `AshTypescript.TypedController.Route`). Errors are collected
  across all arguments; if there are any, a single 422 is returned without
  invoking the handler.

  ## Error Shape

  Errors use the same shape as RPC errors (`AshRpc.Error`), so a
  client can handle both with one code path. The argument is named by its
  client name:

      %{
        type: "required",
        message: "is required",
        short_message: "Required field",
        vars: %{field: "userId"},
        fields: ["userId"],
        path: []
      }

  `message` keeps its `%{var}` placeholders and `vars` carries the values, as
  in RPC — interpolation is left to the client. All keys are run through the
  configured `output_field_formatter` before being sent.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  require Logger

  alias AshRpc.ErrorFormatter
  alias AshRpc.ValueFormatter
  alias AshTypescript.FieldFormatter
  alias AshTypescript.Manifest.{Custom, Route, RouteArgument}
  alias AshTypescript.TypedController.Info

  @reserved_keys ["_format", "action", "controller"]

  @doc """
  Handles a route request by resolving, formatting, casting and validating
  arguments, then dispatching to the configured handler. `params` (Phoenix's
  merged params) is not read: keys are resolved from the conn per source.
  """
  def handle(conn, source_module, route_name, _params) do
    error_context = %{route: route_name, source_module: source_module}
    manifest = AshTypescript.manifest()
    route = fetch_route!(manifest, source_module, route_name)
    dsl_route = Enum.find(Info.typed_controller(source_module), &(&1.name == route_name))
    runtime = AshRpc.Runtime.from_manifest(manifest)

    {values, ambiguous} = resolve_inputs(conn, route)

    case cast_arguments(route, dsl_route, values, ambiguous, runtime) do
      {cast_params, []} ->
        conn
        |> put_private(:ash_typescript_route, dsl_route)
        |> put_private(:ash_typescript_manifest_route, route)
        |> dispatch(dsl_route.run, cast_params, error_context)

      {_cast_params, errors} ->
        send_errors(conn, 422, errors, error_context)
    end
  rescue
    e ->
      error_msg =
        if AshTypescript.typed_controller_show_raised_errors?(),
          do: Exception.message(e),
          else: "Internal server error"

      send_errors(conn, 500, [internal_error(error_msg)], %{
        route: route_name,
        source_module: source_module
      })
  end

  defp fetch_route!(manifest, source_module, route_name) do
    Custom.route(manifest, source_module, route_name) ||
      raise ArgumentError,
            "typed controller route #{inspect(route_name)} of #{inspect(source_module)} is not in " <>
              "the AshTypescript manifest. Add #{inspect(source_module)} to the manifest " <>
              "module's `typed_controllers:` option and recompile"
  end

  # Keys are resolved per source, never from the merged params. Path params
  # resolve by router segment name, and query and body keys by the argument's
  # client name. A key that matches nothing (another casing, an undeclared
  # name, a segment name used outside the path) is dropped. An argument hit
  # by more than one key or source is ambiguous: we can't tell which one the
  # caller meant.
  defp resolve_inputs(conn, %Route{} = route) do
    hits =
      [
        {conn.path_params, route.path_input_names},
        {query_params(conn), route.client_input_names},
        {body_params(conn), route.client_input_names}
      ]
      |> Enum.flat_map(fn {params, names} ->
        Enum.flat_map(params, fn {key, value} ->
          key = to_string(key)

          with false <- key in @reserved_keys or String.starts_with?(key, "_"),
               {:ok, name} <- Map.fetch(names, key) do
            [{name, value}]
          else
            _ -> []
          end
        end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    values = for {name, [value]} <- hits, into: %{}, do: {name, value}
    ambiguous = for {name, [_, _ | _]} <- hits, into: MapSet.new(), do: name
    {values, ambiguous}
  end

  defp query_params(%Plug.Conn{query_params: %Plug.Conn.Unfetched{}} = conn),
    do: conn |> Plug.Conn.fetch_query_params() |> Map.fetch!(:query_params)

  defp query_params(%Plug.Conn{query_params: params}), do: params

  defp body_params(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}}), do: %{}
  defp body_params(%Plug.Conn{body_params: params}), do: params

  # Every argument is checked, and errors are collected across all of them.
  defp cast_arguments(%Route{} = route, dsl_route, values, ambiguous, runtime) do
    dsl_args = Map.new(dsl_route.arguments, &{&1.name, &1})

    {params, errors} =
      Enum.reduce(route.inputs, {%{}, []}, fn %RouteArgument{} = input, {params, errors} ->
        if MapSet.member?(ambiguous, input.name) do
          {params, [ambiguous_param_error(input.client_name) | errors]}
        else
          dsl_arg = Map.fetch!(dsl_args, input.name)

          case cast_argument(input, dsl_arg, Map.get(values, input.name), runtime) do
            {:ok, value} -> {Map.put(params, input.name, value), errors}
            {:error, arg_errors} -> {params, Enum.reverse(arg_errors, errors)}
          end
        end
      end)

    {params, Enum.reverse(errors)}
  end

  defp cast_argument(input, dsl_arg, nil, _runtime) do
    if dsl_arg.allow_nil?,
      do: {:ok, dsl_arg.default},
      else: {:error, [required_error(input.client_name)]}
  end

  # Like Ash action arguments: map the value's client names to internal ones
  # (strict on decorated types), cast, apply constraints, then re-check
  # allow_nil? (a value constrained to nil, like "" under allow_empty?: false,
  # fails a required argument).
  defp cast_argument(input, dsl_arg, raw_value, runtime) do
    type = Ash.Type.get_type(dsl_arg.type)
    constraints = dsl_arg.constraints || []

    with {:ok, value} <- format_argument(raw_value, input, runtime),
         {:ok, cast} <- tag_cast_error(Ash.Type.cast_input(type, value, constraints), input),
         {:ok, constrained} <-
           tag_cast_error(Ash.Type.apply_constraints(type, cast, constraints), input) do
      if is_nil(constrained) and not dsl_arg.allow_nil?,
        do: {:error, [required_error(input.client_name)]},
        else: {:ok, constrained}
    end
  end

  # Nested misses become `unknown_input` errors located under the argument;
  # any other reason (an invalid union shape) makes the argument invalid.
  defp format_argument(raw_value, input, runtime) do
    case ValueFormatter.format_input(raw_value, input.type, runtime) do
      {:ok, value} ->
        {:ok, value}

      {:error, reasons} ->
        {misses, other} = Enum.split_with(reasons, &match?({:unknown_input, _, _}, &1))

        errors =
          Enum.map(misses, fn {:unknown_input, key, path} ->
            unknown_input_error(key, [input.client_name | path])
          end)

        invalid =
          if other == [],
            do: [],
            else: [invalid_argument_error(input.client_name, "is invalid", %{})]

        {:error, errors ++ invalid}
    end
  end

  # `Ash.Type.cast_input/3` may return a bare `:error`; a `nil` error falls
  # through `normalize_cast_errors/1` to "is invalid".
  defp tag_cast_error({:ok, value}, _input), do: {:ok, value}

  defp tag_cast_error({:error, error}, input),
    do: {:error, invalid_argument_errors(input.client_name, error)}

  defp tag_cast_error(:error, input),
    do: {:error, invalid_argument_errors(input.client_name, nil)}

  defp send_errors(conn, status, errors, context) do
    formatter = AshTypescript.output_field_formatter()

    body = %{
      FieldFormatter.format_field_name(:errors, formatter) =>
        errors
        |> maybe_apply_error_handler(context)
        |> Enum.map(&ErrorFormatter.format(&1, formatter))
    }

    conn
    |> put_status(status)
    |> json(body)
  end

  defp unknown_input_error(key, path) do
    %{
      type: "unknown_input",
      message: "Unknown input %{field}",
      short_message: "Unknown input",
      vars: %{field: key},
      fields: [key],
      path: path
    }
  end

  defp required_error(key) do
    %{
      type: "required",
      message: "is required",
      short_message: "Required field",
      vars: %{field: key},
      fields: [key],
      path: []
    }
  end

  # One argument hit from more than one key or source (e.g. the trusted path
  # param `provider` plus an appended `?provider=`). We cannot tell which the
  # caller meant, so we reject rather than silently pick one.
  defp ambiguous_param_error(key) do
    %{
      type: "ambiguous_param",
      message: "resolves to a duplicate parameter name",
      short_message: "Ambiguous parameter",
      vars: %{field: key},
      fields: [key],
      path: []
    }
  end

  defp internal_error(message) do
    %{
      type: "internal_error",
      message: message,
      short_message: "Internal error",
      vars: %{},
      fields: [],
      path: []
    }
  end

  # One error per constraint violation, mirroring how RPC surfaces each
  # Ash error separately rather than joining messages into one string.
  defp invalid_argument_errors(key, error) do
    case normalize_cast_errors(error) do
      [] ->
        [invalid_argument_error(key, "is invalid", %{})]

      normalized ->
        Enum.map(normalized, fn {msg, vars} -> invalid_argument_error(key, msg, vars) end)
    end
  end

  defp invalid_argument_error(key, message, vars) do
    %{
      type: "invalid_argument",
      message: message,
      short_message: "Invalid argument",
      vars: Map.put(vars, :field, key),
      fields: [key],
      path: []
    }
  end

  # Normalizes what `Ash.Type.cast_input/3` and `Ash.Type.apply_constraints/3`
  # return into `{message_template, vars}` pairs. Placeholders are left in the
  # template and the values kept in `vars`, matching RPC — the client
  # interpolates. `apply_constraints` returns a list of keyword lists, so a
  # single argument can produce several violations.
  defp normalize_cast_errors(error) when is_binary(error), do: [{error, %{}}]

  defp normalize_cast_errors(error) when is_list(error) do
    if Keyword.keyword?(error) and Keyword.has_key?(error, :message) do
      vars =
        error
        |> Keyword.drop([:message, :vars])
        |> Map.new()
        |> Map.merge(Map.new(Keyword.get(error, :vars) || []))

      [{Keyword.fetch!(error, :message), vars}]
    else
      Enum.flat_map(error, &normalize_cast_errors/1)
    end
  end

  defp normalize_cast_errors(error) when is_exception(error) do
    [{Exception.message(error), Map.new(Map.get(error, :vars) || [])}]
  end

  defp normalize_cast_errors(_error), do: [{"is invalid", %{}}]

  defp dispatch(conn, handler, input, context) when is_function(handler, 2) do
    case handler.(conn, input) do
      %Plug.Conn{} = conn -> conn
      other -> unexpected_return(conn, other, context)
    end
  end

  defp dispatch(conn, handler, input, context) when is_atom(handler) do
    case handler.run(conn, input) do
      %Plug.Conn{} = conn -> conn
      other -> unexpected_return(conn, other, context)
    end
  end

  # The detailed message is gated like raised exceptions above: the returned
  # term is internal application data (e.g. an {:error, struct} fallthrough),
  # so echoing it to the client by default would leak whatever it carries.
  defp unexpected_return(conn, value, context) do
    detail = "Route handler must return %Plug.Conn{}, got: #{inspect(value, limit: 50)}"

    Logger.error("#{inspect(context.source_module)} route #{inspect(context.route)}: #{detail}")

    error_msg =
      if AshTypescript.typed_controller_show_raised_errors?(),
        do: detail,
        else: "Internal server error"

    send_errors(conn, 500, [internal_error(error_msg)], context)
  end

  defp maybe_apply_error_handler(errors, context) do
    case AshTypescript.typed_controller_error_handler() do
      nil ->
        errors

      {module, function, extra_args} ->
        errors
        |> Enum.map(fn error -> apply(module, function, [error, context | extra_args]) end)
        |> Enum.reject(&is_nil/1)

      module when is_atom(module) ->
        errors
        |> Enum.map(fn error -> module.handle_error(error, context) end)
        |> Enum.reject(&is_nil/1)
    end
  end
end
