defmodule AshTypescript.RPC.Codegen do
  import AshTypescript.Helpers
  import AshTypescript.RPC.Helpers
  import AshTypescript.TS.Codegen

  def generate_typescript_types(otp_app, rpc_specs, opts \\ []) do
    process_endpoint = Keyword.get(opts, :process_endpoint, "/rpc/run")
    validate_endpoint = Keyword.get(opts, :validate_endpoint, "/rpc/validate")

    endpoint_process_arg = "endpoint: string = \"#{process_endpoint}\""
    endpoint_validate_arg = "endpoint: string = \"#{validate_endpoint}\""

    resources_and_actions = get_resources_and_actions(otp_app)

    generate_types_from_rpc_specs(
      rpc_specs,
      resources_and_actions,
      endpoint_process_arg,
      endpoint_validate_arg,
      otp_app
    )
  end

  def get_resources_and_actions(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      AshTypescript.RPC.Info.rpc(domain)
    end)
  end

  def generate_types_from_rpc_specs(
        rpc_specs,
        resources_and_actions,
        endpoint_process_arg,
        endpoint_validate_arg,
        otp_app
      ) do
    load_type = """
    type AshLoadList = Array<string | { [key: string]: AshLoadList }>;

    function getCSRFToken(): string | null {
      const metaElement = document.querySelector('meta[name="csrf-token"]');
      return metaElement ? metaElement.getAttribute('content') : null;
    }
    """

    rpc_specs
    |> Enum.reduce(load_type, fn rpc_spec, content ->
      process_rpc_spec(
        rpc_spec,
        resources_and_actions,
        endpoint_process_arg,
        endpoint_validate_arg,
        otp_app,
        content
      )
    end)
  end

  def process_rpc_spec(
        rpc_spec,
        resources_and_actions,
        endpoint_process_arg,
        endpoint_validate_arg,
        otp_app,
        content
      ) do
    {resource, rpc_action} = find_resource_and_action(rpc_spec, resources_and_actions)

    if rpc_action == nil do
      raise "Unable to find rpc_action #{rpc_action["name"]}"
    end

    action = Ash.Resource.Info.action(resource, rpc_action.action)
    primary_key = Ash.Resource.Info.primary_key(resource)
    select = parse_json_select_and_load(rpc_spec["select"] || [])
    load = parse_json_select_and_load(rpc_spec["load"] || [])
    input_type_name = "#{snake_to_pascal(rpc_action.name)}Input"

    input_type = generate_input_type(action, input_type_name, primary_key, resource)
    return_type_name = "#{snake_to_pascal(rpc_action.name)}Return"

    return_type =
      generate_return_type(action, return_type_name, select, load, otp_app, resource)

    validate_function =
      if action.type in [:read, :action] or not action_has_input?(action) do
        ""
      else
        build_validate_function(rpc_spec, endpoint_validate_arg)
      end

    Enum.join(
      [
        content,
        input_type,
        return_type,
        build_payload_function(rpc_spec, action),
        build_process_function(rpc_spec, action, endpoint_process_arg),
        validate_function
      ],
      "\n"
    )
  end

  def find_resource_and_action(rpc_spec, resources_and_actions) do
    Enum.find_value(resources_and_actions, fn %{
                                                resource: resource,
                                                rpc_actions: rpc_actions
                                              } ->
      rpc_action =
        Enum.find(rpc_actions, fn rpc_action ->
          if to_string(rpc_action.name) == rpc_spec["action"] do
            rpc_action.action
          end
        end)

      if rpc_action do
        {resource, rpc_action}
      end
    end)
  end

  def generate_input_type(action, input_type_name, primary_key, resource) do
    case action.type do
      :read ->
        if Enum.empty?(action.arguments) do
          ""
        else
          """
          export type #{input_type_name} = {
          #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
          }
          """
        end

      :update ->
        """
        export type #{input_type_name} = {
        #{Enum.map_join((primary_key ++ action.accept) |> Enum.uniq(), "\n", &get_action_accept_spec(&1, resource))}
        #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
        }
        """

      :action ->
        if Enum.empty?(action.arguments) do
          ""
        else
          """
          export type #{input_type_name} = {
          #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
          }
          """
        end

      _ ->
        """
        export type #{input_type_name} = {
        #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
        #{Enum.map_join(action.accept, "\n", &get_action_accept_spec(&1, resource))}
        }
        """
    end
  end

  def generate_return_type(action, return_type_name, select, load, otp_app, resource) do
    if action.type == :action do
      build_generic_action_return_type(action, return_type_name, select, load, otp_app)
    else
      fields = (select ++ load) |> Enum.uniq()

      """
      export type #{return_type_name} =
      #{build_resource_type(resource, fields)}#{if action.type == :read and not action.get?, do: "[]", else: ""}
      """
    end
  end

  def action_has_input?(action) do
    case action.type do
      :read -> not Enum.empty?(action.arguments)
      :action -> not Enum.empty?(action.arguments)
      # Update actions always have input (at minimum the primary key)
      :update -> true
      # Destroy actions always have input (at minimum the primary key)
      :destroy -> true
      _ -> not Enum.empty?(action.arguments) or not Enum.empty?(action.accept)
    end
  end

  def build_rpc_action_input_type_name(rpc_action_name),
    do: "#{snake_to_pascal(rpc_action_name)}Input"

  def build_rpc_action_return_type_name(rpc_action_name),
    do: "#{snake_to_pascal(rpc_action_name)}Return"

  def build_payload(rpc_spec, action) do
    action_payload = "action: \"#{rpc_spec["action"]}\""

    input =
      if action_has_input?(action) do
        "input"
      else
        "input: {}"
      end

    select =
      if Map.get(rpc_spec, "select", []) |> Enum.empty?() do
        "select: []"
      else
        "select: #{Jason.encode!(rpc_spec["select"])}"
      end

    load =
      if Map.get(rpc_spec, "load", []) |> Enum.empty?() do
        "load: []"
      else
        "load: #{Jason.encode!(rpc_spec["load"])}"
      end

    Enum.join([action_payload, input, select, load], ", ")
  end

  def build_payload_function(rpc_spec, action) do
    input_type = build_rpc_action_input_type_name(rpc_spec["action"])

    input_arg =
      if action_has_input?(action) do
        "input: #{input_type}"
      else
        ""
      end

    payload = build_payload(rpc_spec, action)

    return_type =
      if action_has_input?(action) do
        "{action: string, input: #{input_type}, select: string[], load: AshLoadList}"
      else
        "{action: string, input: {}, select: string[], load: AshLoadList}"
      end

    """
    export function build#{snake_to_pascal(rpc_spec["action"])}Payload(#{input_arg}): #{return_type} {
      return {#{payload}}
    }
    """
  end

  def build_process_function(rpc_spec, action, endpoint_process_arg) do
    input_type = build_rpc_action_input_type_name(rpc_spec["action"])

    function_args =
      if action_has_input?(action) do
        "input: #{input_type}, #{endpoint_process_arg}"
      else
        endpoint_process_arg
      end

    payload = build_payload(rpc_spec, action)

    return_type = build_rpc_action_return_type_name(rpc_spec["action"])

    """
    export async function #{snake_to_camel(rpc_spec["action"])}(#{function_args}): Promise<{success: true, data: #{return_type}, error: null} | {success: false, data: null, error: Record<string, string>}> {
      const csrfToken = getCSRFToken();
      const headers: Record<string, string> = {
        'Content-Type': 'application/json'
      };

      if (csrfToken) {
        headers['X-CSRF-Token'] = csrfToken;
      }

      return await fetch(endpoint, {
        method: 'POST',
        headers,
        body: JSON.stringify({#{payload}})
      }).then(async (response) => {
        if (response.ok) {
          return response.json();
        } else {
          let errorMessage = `HTTP error ${response.status}`;
          try {
            const errorData = await response.json();
            errorMessage = errorData.message || JSON.stringify(errorData);
          } catch {
            // fallback if response is not JSON
            const text = await response.text();
            if (text) errorMessage = text;
          }
          throw new Error(errorMessage);
        }
      })
    }
    """
  end

  def build_validate_function(rpc_spec, endpoint_validate_arg) do
    input_type = build_rpc_action_input_type_name(rpc_spec["action"])

    function_args = "input: #{input_type}, #{endpoint_validate_arg}"

    """
    export async function validate#{snake_to_pascal(rpc_spec["action"])}(#{function_args}): Promise<{success: true, errors: Record<string, string>}> {
      const csrfToken = getCSRFToken();
      const headers: Record<string, string> = {
        'Content-Type': 'application/json'
      };

      if (csrfToken) {
        headers['X-CSRF-Token'] = csrfToken;
      }

      return await fetch(endpoint, {
        method: 'POST',
        headers,
        body: JSON.stringify({action: "#{rpc_spec["action"]}", input})
      }).then(async (response) => {
        if (response.ok) {
          return response.json();
        } else {
          let errorMessage = `HTTP error ${response.status}`;
          try {
            const errorData = await response.json();
            errorMessage = errorData.message || JSON.stringify(errorData);
          } catch {
            // fallback if response is not JSON
            const text = await response.text();
            if (text) errorMessage = text;
          }
          throw new Error(errorMessage);
        }
      })
    }
    """
  end

  def get_action_accept_spec(attr, resource) do
    attribute = Ash.Resource.Info.attribute(resource, attr)

    if attribute.allow_nil? or attribute.default != nil do
      "  #{attr}?: #{get_ts_type(attribute)} | null;"
    else
      "  #{attr}: #{get_ts_type(attribute)};"
    end
  end

  def get_action_argument_spec(argument) do
    if argument.allow_nil? or argument.default != nil do
      "  #{argument.name}?: #{get_ts_type(argument)} | null;"
    else
      "  #{argument.name}: #{get_ts_type(argument)};"
    end
  end

  def validate_and_filter_fields(fields, select, action_name) do
    if select != [] do
      available_fields = Keyword.keys(fields)
      invalid_fields = select -- available_fields

      if invalid_fields != [] do
        raise "Cannot select fields #{inspect(invalid_fields)} from generic action #{action_name}. Available fields are: #{inspect(available_fields)}"
      end

      Keyword.take(fields, select)
    else
      fields
    end
  end

  def build_generic_action_return_type(action, return_type_name, select, load, otp_app) do
    cond do
      action.returns in [Ash.Type.Struct, {:array, Ash.Type.Struct}] ->
        instance_of = action.constraints[:instance_of]
        fields = action.constraints[:fields]

        is_array = is_tuple(action.returns)

        cond do
          # If we have fields constraints, use them to build the type
          fields && is_list(fields) ->
            fields_to_include = validate_and_filter_fields(fields, select, action.name)

            field_types =
              fields_to_include
              |> Enum.map(fn {field_name, field_spec} ->
                ts_type =
                  get_ts_type(%{
                    type: field_spec[:type],
                    constraints: field_spec[:constraints] || []
                  })

                optional = if field_spec[:allow_nil?] != false, do: "?", else: ""

                "  #{field_name}#{optional}: #{ts_type};"
              end)
              |> Enum.join("\n")

            """
            export type #{return_type_name} = {
            #{field_types}
            }#{if is_array, do: "[]", else: ""}
            """

          # If we have instance_of, use the resource
          instance_of ->
            app_resources =
              otp_app
              |> Ash.Info.domains()
              |> Enum.flat_map(fn d -> Ash.Domain.Info.resources(d) end)

            resource = Enum.find(app_resources, &(&1 == instance_of))

            if resource do
              """
              export type #{return_type_name} =
              #{build_resource_type(resource, select ++ load)}#{if is_array, do: "[]", else: ""}
              """
            else
              if load != [] do
                raise "Cannot use load with generic action #{action.name}, since it does not return a resource."
              end

              """
              export type #{return_type_name} = {
              #{Enum.map_join(select,
              "\n",
              &"#{&1}?: any")}
              }#{if is_array, do: "[]", else: ""}
              """
            end

          # Default case
          true ->
            if load != [] do
              raise "Cannot use load with generic action #{action.name}, since it does not return a resource."
            end

            """
            export type #{return_type_name} = {
            #{Enum.map_join(select,
            "\n",
            &"#{&1}?: any")}
            }#{if is_array, do: "[]", else: ""}
            """
        end

      action.returns in [:map, Ash.Type.Map, {:array, :map}, {:array, Ash.Type.Map}] ->
        fields = action.constraints[:fields] || action.constraints[:items][:fields]
        is_array = is_tuple(action.returns)

        if fields && is_list(fields) do
          fields_to_include = validate_and_filter_fields(fields, select, action.name)

          field_types =
            fields_to_include
            |> Enum.map(fn {field_name, field_spec} ->
              ts_type =
                get_ts_type(%{
                  type: field_spec[:type],
                  constraints: field_spec[:constraints] || []
                })

              optional = if field_spec[:allow_nil?] != false, do: "?", else: ""

              "  #{field_name}#{optional}: #{ts_type};"
            end)
            |> Enum.join("\n")

          """
          export type #{return_type_name} = {
          #{field_types}
          }#{if is_array, do: "[]", else: ""}
          """
        else
          if load != [] do
            raise "Cannot use load with generic action #{action.name}, since it does not return a resource."
          end

          """
          export type #{return_type_name} = {
            #{Enum.map_join(select,
          "\n",
          &"#{&1}?: any")}
          }#{if is_array, do: "[]", else: ""}
          """
        end

      is_tuple(action.returns) and elem(action.returns, 0) == :array ->
        if select != [] do
          raise "select-list for generic action #{action.name} must be empty, since it does not return a resource, struct or a map."
        end

        if load != [] do
          raise "load-list for generic action #{action.name} must be empty, since it does not return a resource, struct or a map."
        end

        "export type #{return_type_name} = Array<#{get_ts_type(%{type: elem(action.returns, 1), constraints: action.constraints})}>;\n"

      true ->
        if select != [] do
          raise "select-list for generic action #{action.name} must be empty, since it does not return a resource, struct or a map."
        end

        if load != [] do
          raise "load-list for generic action #{action.name} must be empty, since it does not return a resource, struct or a map."
        end

        get_ts_type(%{type: action.returns, constraints: action.constraints})
    end
  end
end
