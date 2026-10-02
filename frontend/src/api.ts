import { ApolloClient, HttpLink, InMemoryCache } from "@apollo/client";

export const client = new ApolloClient({
  link: new HttpLink({ uri: "/graphql", credentials: "same-origin" }),
  cache: new InMemoryCache(),
});
