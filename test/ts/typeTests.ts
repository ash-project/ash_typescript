import { listTodos, createTodo, createUser, updateTodo } from "./generated";

const listTodosResult = await listTodos({
  fields: ["id"],
  calculatedFields: ["is_overdue"],
  aggregateFields: ["comment_count"],
  load: {
    comments: {
      fields: ["id"],
      load: {
        user: { fields: ["id", "email"] },
        todo: {
          fields: ["id", "title", "status"],
          load: { comments: { fields: ["id", "content"] } },
        },
      },
    },
  },
  filter: {
    and: [
      {
        status: { eq: "finished" },
      },
    ],
  },
});

type ExpectedListTodosResultType = Array<{
  id: string;
  is_overdue?: boolean | null;
  comment_count: number;
  comments: {
    id: string;
    user: {
      id: string;
      email: string;
    };
    todo: {
      id: string;
      title: string;
      status: string;
      comments: {
        id: string;
        content: string;
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
  load: {
    user: { fields: ["id", "email"] },
    comments: { fields: ["id", "content"] },
  },
  fields: ["id", "title", "status", "user_id"],
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
});
