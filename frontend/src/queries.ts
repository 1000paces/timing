import { gql } from "@apollo/client";

export type EventSummary = { id: string; name: string; date: string };
export type EventsData = { events: EventSummary[] };

export const EVENTS = gql`
  query Events {
    events { id name date }
  }
`;

export type RaceInfo = { id: string; name: string };
export type StartGroupInfo = { id: string; name: string; finishRule: { type: string }; races: RaceInfo[] };
export type EventData = { event: { id: string; name: string; startGroups: StartGroupInfo[] } };

export const EVENT = gql`
  query Event($id: ID!) {
    event(id: $id) {
      id
      name
      startGroups { id name finishRule races { id name } }
    }
  }
`;

export type Row = {
  place: number | null;
  bib: string;
  name: string;
  status: string;
  laps: number;
  elapsedMs: number | null;
  gapLapsDown: number | null;
  gapMs: number | null;
};
export type RaceStandings = { race: { id: string; name: string }; state: string; lapCount: number | null; rows: Row[] };
export type Suggestion = { key: string; kind: string; bib: string | null; message: string; needs: string[] };
export type StandingsData = {
  standings: { stale: boolean; error: string | null; races: RaceStandings[]; suggestions: Suggestion[] };
};

export const STANDINGS = gql`
  query Standings($eventId: ID!) {
    standings(eventId: $eventId) {
      stale
      error
      races {
        race { id name }
        state
        lapCount
        rows { place bib name status laps elapsedMs gapLapsDown gapMs }
      }
      suggestions { key kind bib message needs }
    }
  }
`;

export type RulingsData = { rulings: { id: string; kind: string; payload: Record<string, unknown>; reverted: boolean }[] };

export const RULINGS = gql`
  query Rulings($eventId: ID!) {
    rulings(eventId: $eventId) { id kind payload reverted }
  }
`;

export type MutationResult = { errors: string[] };

export const FIRE_START = gql`
  mutation FireStart($startGroupId: ID!) { fireStart(startGroupId: $startGroupId) { errors } }
`;
export const SET_LAP_COUNT = gql`
  mutation SetLapCount($startGroupId: ID!, $laps: Int!) { setLapCount(startGroupId: $startGroupId, laps: $laps) { errors } }
`;
export const ACCEPT_SUGGESTION = gql`
  mutation AcceptSuggestion($eventId: ID!, $key: String!, $bib: String) {
    acceptSuggestion(eventId: $eventId, key: $key, bib: $bib) { errors }
  }
`;
export const DISMISS_SUGGESTION = gql`
  mutation DismissSuggestion($eventId: ID!, $key: String!) { dismissSuggestion(eventId: $eventId, key: $key) { errors } }
`;
