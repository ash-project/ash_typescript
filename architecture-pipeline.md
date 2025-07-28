# Architecture for parsing requested fields in RPC Pipeline

## Overview

Our RPC pipeline should have this high-level architecture:

1. Parse/analyze input parameters - Which action to run, which fields to return, action input, filtering, sorting and pagination.
2. Execute the action - Call the appropriate function or method with the parsed parameters.
3. Extract the requested fields from the result.
4. Format the result into the desired output format.

### Parse/analyze input parameters
Our current design with building a AshTypescript.Rpc.Request struct based on the input parameters is good, and should be generally kept as-is.

However, I want to make some adjustments:

When examining the requested fields to be returned, we should ensure that they are valid and exist in the data model. If a field is not valid or does not exist, we should return an error. We should be able to handle also nested fields, which means we should have a recursive function that can traverse the nested fields and validate them.

If an action returns a primitive value, like a string or an integer, or a map without any field constraints, or any type of complex data structure what we don't know the exact shape of, we should return the value as is. In these cases, the client should not be allowed to request any fields, meaning that they have to send us an empty list in the fields parameter.

If the action is a create, read or update action, we know that the response will be a singular or a list of records of the given resource type. If the action is a generic action, we have to examine its return type, and validate the fields requested based on that type.

Also, our current logic for creating an extraction template is more complex than it needs to be. If the action returns a struct or a map with field constraints, or a list of structs or maps with field constraints, the resulting structure of the extraction template such be:

```elixir
input_params = %{
  "action" => "list_todos",
  "fields" => ["id", "title", "priority", %{"user" => ["id", "email"]}]
}

# The extraction template for the response should be of this keyword list format:
[:id, :title, :priority, [user: [:id, :email]]]
```

We should create a new module that should contain all this functionality with us, let's call it `AshTypescript.Rpc.RequestedFieldsParser`. This module should have a function called `parse_requested_fields` that will be used as the entry point for parsing requested fields, and takes care of all the concerns mentioned above. `parse_requested_fields` should accept the resource, the action, and the requested fields as parameters.

It should return the fields to select, the load statements, and the extraction template.

If we are executing a generic action, both the select and load lists should be empty, but if the action returns a data structure that we know the shape of, it should build a proper extraction template.

The Ash framework provides powerful introspection that can be used on both resources and its actions, attributes, relationships, calculations and aggregates. Consult the ash documentation when needed in order to build this functionality in an idiomatically Ash way.
