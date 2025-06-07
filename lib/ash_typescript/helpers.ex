defmodule AshTypescript.Helpers do
  def snake_to_pascal_case(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_pascal_case()
  end

  def snake_to_pascal_case(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn {part, _} -> String.capitalize(part) end)
    |> Enum.join()
  end

  def snake_to_camel_case(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_camel_case()
  end

  def snake_to_camel_case(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn
      {part, 0} -> String.downcase(part)
      {part, _} -> String.capitalize(part)
    end)
    |> Enum.join()
  end
end
