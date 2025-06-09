import {
  listTodos,
  createTodo,
  createUser,
  updateTodo,
  validateUpdateTodo,
} from "./generated";

const listTodosResult = await listTodos({
  fields: [
    "id",
    "comment_count",
    "is_overdue",
    {
      comments: [
        "id",
        "content",
        {
          user: [
            "id",
            "email",
            {
              todos: [
                "id",
                "title",
                "status",
                {
                  comments: ["id", "content"],
                },
              ],
            },
          ],
        },
      ],
    },
  ],
});

type ExpectedListTodosResultType = Array<{
  id: string;
  is_overdue?: boolean | null;
  comment_count: number;
  comments: {
    id: string;
    content: string;
    user: {
      id: string;
      email: string;
      todos: {
        id: string;
        title: string;
        status?: string | null;
        comments?: {
          id: string;
          content: string;
        }[];
      }[];
    };
  }[];
}>;

const listTodosResultTest: ExpectedListTodosResultType = listTodosResult;

const createUserResult = await createUser({
  input: {
    name: "User",
    email: "email@example.com",
  },
  fields: ["id", "email", "name"],
});

type ExpectedCreateUserResultType = {
  id: string;
  name: string;
  email: string;
};

const createUserResultTodo: ExpectedCreateUserResultType = createUserResult;

const createTodoResult = await createTodo({
  input: {
    title: "New Todo",
    status: "finished",
    user_id: createUserResultTodo.id,
  },
  fields: [
    "id",
    "title",
    "status",
    "user_id",
    { user: ["id", "email"], comments: ["id", "content"] },
  ],
});

type ExpectedCreateTodoResultType = {
  id: string;
  title: string;
  status?: string | null;
  user_id: string;
  user: {
    id: string;
    email: string;
  };
  comments: {
    id: string;
    content: string;
  }[];
};

const createTodoResultTest: ExpectedCreateTodoResultType = createTodoResult;

const updateTodoResult = await updateTodo({
  primaryKey: createTodoResult.id,
  input: {
    title: "Updated Todo",
    tags: ["tag1", "tag2"],
  },
  fields: [],
});

const validateUpdateTodoResult = await validateUpdateTodo(createTodoResult.id, {
  title: "Updated Todo",
  tags: ["tag1", "tag2"],
});
