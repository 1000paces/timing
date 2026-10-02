import { gql } from "@apollo/client";

export type EventSummary = { id: string; name: string; date: string };
export type EventsData = { events: EventSummary[] };

export const EVENTS = gql`
  query Events {
    events { id name date }
  }
`;
