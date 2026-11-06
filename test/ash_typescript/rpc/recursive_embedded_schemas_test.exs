# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RecursiveEmbeddedSchemasTest do
  @moduledoc """
  Validation schemas of embedded resources on a cycle of the schema dependency
  graph (`TaskNote` contains itself, `TaskOutline` and `TaskOutlineItem` each
  other) are lazy and cast to their input type, so they can reference
  themselves and compile under `exactOptionalPropertyTypes`. Other schemas,
  `TaskNoteBoard`'s included (it holds a note but isn't on a cycle), stay
  eager.
  """
  use ExUnit.Case, async: true

  import AshTypescript.Test.CodegenTestHelper,
    only: [generate_files: 0, valibot_content: 1, zod_content: 1]

  alias AshTypescript.Codegen.{SchemaCore, ValibotSchemaGenerator, ZodSchemaGenerator}
  alias AshTypescript.Test.{TaskNote, TaskNoteBoard, TaskOutline, TaskOutlineItem}

  @resources [TaskNoteBoard, TaskOutlineItem, TaskOutline, TaskNote]

  describe "zod" do
    setup do
      %{output: SchemaCore.generate_schemas_for_resources(ZodSchemaGenerator, @resources)}
    end

    test "a self-recursive schema is lazy and cast to its input type", %{output: output} do
      assert output =~ """
             export const TaskNoteZodSchema = z.lazy(() => z.object({
               body: z.string().min(1),
               id: z.uuid().optional(),
               replies: z.array(TaskNoteZodSchema).nullable().optional(),
             })) as z.ZodType<TaskNoteInputSchema>;
             """
    end

    test "mutually recursive schemas are both lazy", %{output: output} do
      assert output =~ """
             export const TaskOutlineZodSchema = z.lazy(() => z.object({
               id: z.uuid().optional(),
               items: z.array(TaskOutlineItemZodSchema),
               title: z.string().min(1),
             })) as z.ZodType<TaskOutlineInputSchema>;
             """

      assert output =~ """
             export const TaskOutlineItemZodSchema = z.lazy(() => z.object({
               id: z.uuid().optional(),
               label: z.string().min(1),
               sublist: TaskOutlineZodSchema.nullable().optional(),
             })) as z.ZodType<TaskOutlineItemInputSchema>;
             """
    end

    test "a schema off the cycle stays eager, after the recursive schema it holds", %{
      output: output
    } do
      assert output =~ """
             export const TaskNoteBoardZodSchema = z.object({
               id: z.uuid().optional(),
               pinned: TaskNoteZodSchema,
             });
             """

      assert position(output, "export const TaskNoteZodSchema") <
               position(output, "export const TaskNoteBoardZodSchema")
    end
  end

  describe "valibot" do
    setup do
      %{output: SchemaCore.generate_schemas_for_resources(ValibotSchemaGenerator, @resources)}
    end

    test "a self-recursive schema is lazy and cast to its input type", %{output: output} do
      assert output =~ """
             export const TaskNoteValibotSchema = v.lazy(() => v.object({
               body: v.pipe(v.string(), v.minLength(1)),
               id: v.optional(v.pipe(v.string(), v.uuid())),
               replies: v.optional(v.nullable(v.array(TaskNoteValibotSchema))),
             })) as v.GenericSchema<TaskNoteInputSchema>;
             """
    end

    test "mutually recursive schemas are both lazy", %{output: output} do
      assert output =~ """
             export const TaskOutlineValibotSchema = v.lazy(() => v.object({
               id: v.optional(v.pipe(v.string(), v.uuid())),
               items: v.array(TaskOutlineItemValibotSchema),
               title: v.pipe(v.string(), v.minLength(1)),
             })) as v.GenericSchema<TaskOutlineInputSchema>;
             """

      assert output =~ """
             export const TaskOutlineItemValibotSchema = v.lazy(() => v.object({
               id: v.optional(v.pipe(v.string(), v.uuid())),
               label: v.pipe(v.string(), v.minLength(1)),
               sublist: v.optional(v.nullable(TaskOutlineValibotSchema)),
             })) as v.GenericSchema<TaskOutlineItemInputSchema>;
             """
    end

    test "a schema off the cycle stays eager, after the recursive schema it holds", %{
      output: output
    } do
      assert output =~ """
             export const TaskNoteBoardValibotSchema = v.object({
               id: v.optional(v.pipe(v.string(), v.uuid())),
               pinned: TaskNoteValibotSchema,
             });
             """

      assert position(output, "export const TaskNoteValibotSchema") <
               position(output, "export const TaskNoteBoardValibotSchema")
    end
  end

  describe "the schema files" do
    setup do
      {:ok, files} = generate_files()
      %{zod: zod_content(files), valibot: valibot_content(files)}
    end

    test "import the input types of the lazy schemas, and only those", %{
      zod: zod,
      valibot: valibot
    } do
      import_line =
        ~s(import type { TaskNoteInputSchema, TaskOutlineInputSchema, TaskOutlineItemInputSchema } from "./ash_types";\n)

      for content <- [zod, valibot] do
        assert content =~ import_line
        assert length(Regex.scan(~r/^import type /m, content)) == 1
      end
    end
  end

  defp position(output, text) do
    {pos, _} = :binary.match(output, text)
    pos
  end
end
