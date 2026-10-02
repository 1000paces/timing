import { gql } from "@apollo/client";

export type EventSummary = { id: string; name: string; date: string; location: string | null };
export type EventsData = { events: EventSummary[] };

export const EVENTS = gql`
  query Events {
    events { id name date location }
  }
`;

export type RaceInfo = {
  id: string;
  name: string;
  defaultName: string;
  nameOverride: string | null;
  category: string | null;
  ageGroup: string | null;
  ageMin: number | null;
  ageMax: number | null;
  gender: string;
  scheduledAtMs: number;
  expectedDurationMs: number | null;
  expectedLaps: number | null;
  finishWithLeader: boolean;
  finishWithLeaderOverride: boolean | null;
};
export type EventInfo = {
  id: string;
  name: string;
  date: string;
  location: string | null;
  discipline: string;
  subDiscipline: string | null;
  finishWithLeader: boolean;
  races: RaceInfo[];
};
export type EventData = { event: EventInfo };

const RACE_FIELDS = `id name defaultName nameOverride category ageGroup ageMin ageMax gender scheduledAtMs expectedDurationMs
  expectedLaps finishWithLeader finishWithLeaderOverride`;

export const EVENT = gql`
  query Event($id: ID!) {
    event(id: $id) {
      id name date location discipline subDiscipline finishWithLeader
      races { ${RACE_FIELDS} }
    }
  }
`;

export type Discipline = { id: string; label: string; finishWithLeader: boolean; subDisciplines: { id: string; label: string; finishWithLeader: boolean }[] };
export type DisciplinesData = { disciplines: Discipline[] };
export const DISCIPLINES = gql`
  query Disciplines { disciplines { id label finishWithLeader subDisciplines { id label finishWithLeader } } }
`;

export type EventInput = { name: string; date: string; location: string | null; discipline: string; subDiscipline: string | null; finishWithLeader: boolean };
export const CREATE_EVENT = gql`
  mutation CreateEvent($name: String!, $date: ISO8601Date!, $location: String, $discipline: String!, $subDiscipline: String, $finishWithLeader: Boolean) {
    createEvent(name: $name, date: $date, location: $location, discipline: $discipline, subDiscipline: $subDiscipline, finishWithLeader: $finishWithLeader) {
      event { id } errors
    }
  }
`;
export const UPDATE_EVENT = gql`
  mutation UpdateEvent($id: ID!, $name: String, $date: ISO8601Date, $location: String, $discipline: String, $subDiscipline: String, $finishWithLeader: Boolean) {
    updateEvent(id: $id, name: $name, date: $date, location: $location, discipline: $discipline, subDiscipline: $subDiscipline, finishWithLeader: $finishWithLeader) {
      event { id } errors
    }
  }
`;

export type RaceInput = {
  category: string | null;
  ageGroup: string | null;
  ageMin: number | null;
  ageMax: number | null;
  gender: string;
  nameOverride: string | null;
  scheduledAtMs: number;
  expectedDurationMs: number | null;
  expectedLaps: number | null;
  finishWithLeader: boolean | null;
};
const RACE_ARGS = `$category: String, $ageGroup: String, $ageMin: Int, $ageMax: Int, $nameOverride: String, $expectedDurationMs: Millis,
  $expectedLaps: Int, $finishWithLeader: Boolean`;
const RACE_VALUES = `category: $category, ageGroup: $ageGroup, ageMin: $ageMin, ageMax: $ageMax, nameOverride: $nameOverride,
  expectedDurationMs: $expectedDurationMs, expectedLaps: $expectedLaps, finishWithLeader: $finishWithLeader`;
export const CREATE_RACE = gql`
  mutation CreateRace($eventId: ID!, $gender: String!, $scheduledAtMs: Millis!, ${RACE_ARGS}) {
    createRace(eventId: $eventId, gender: $gender, scheduledAtMs: $scheduledAtMs, ${RACE_VALUES}) { race { id } errors }
  }
`;
export const UPDATE_RACE = gql`
  mutation UpdateRace($id: ID!, $gender: String, $scheduledAtMs: Millis, ${RACE_ARGS}) {
    updateRace(id: $id, gender: $gender, scheduledAtMs: $scheduledAtMs, ${RACE_VALUES}) { race { id } errors }
  }
`;
export const DELETE_RACE = gql`
  mutation DeleteRace($id: ID!) { deleteRace(id: $id) { errors } }
`;
export const SET_RACE_START = gql`
  mutation SetRaceStart($raceId: ID!, $atMs: Millis) { setRaceStart(raceId: $raceId, atMs: $atMs) { errors } }
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
export type RaceStandings = {
  race: { id: string; name: string };
  state: string;
  lapCount: number | null;
  startAtMs: number | null;
  rows: Row[];
};
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
        startAtMs
        rows { place bib name status laps elapsedMs gapLapsDown gapMs }
      }
      suggestions { key kind bib message needs }
    }
  }
`;

export type MutationResult = { errors: string[] };

export const SET_LAP_COUNT = gql`
  mutation SetLapCount($raceId: ID!, $laps: Int!) { setLapCount(raceId: $raceId, laps: $laps) { errors } }
`;
export const ACCEPT_SUGGESTION = gql`
  mutation AcceptSuggestion($eventId: ID!, $key: String!, $bib: String) {
    acceptSuggestion(eventId: $eventId, key: $key, bib: $bib) { errors }
  }
`;
export const DISMISS_SUGGESTION = gql`
  mutation DismissSuggestion($eventId: ID!, $key: String!) { dismissSuggestion(eventId: $eventId, key: $key) { errors } }
`;

export type StartRacesResult = { startRaces: MutationResult };
export const START_RACES = gql`
  mutation StartRaces($raceIds: [ID!]!) { startRaces(raceIds: $raceIds) { errors } }
`;
export type UnstartRaceResult = { unstartRace: MutationResult };
export const UNSTART_RACE = gql`
  mutation UnstartRace($raceId: ID!) { unstartRace(raceId: $raceId) { errors } }
`;

export type CaptureRow = { id: string; bib: string | null; capturedAtMs: number };
export type CaptureScreenData = {
  event: {
    id: string;
    name: string;
    races: { id: string; name: string }[];
    registrations: { bib: string; raceId: string; rider: { firstName: string; lastName: string } }[];
    myCaptures: CaptureRow[];
  };
};
export const CAPTURE_SCREEN = gql`
  query CaptureScreen($id: ID!) {
    event(id: $id) {
      id name
      races { id name }
      registrations { bib raceId rider { firstName lastName } }
      myCaptures { id bib capturedAtMs }
    }
  }
`;
export type RecordCaptureResult = { recordCapture: MutationResult & { capture: CaptureRow | null } };
export const RECORD_CAPTURE = gql`
  mutation RecordCapture($eventId: ID!, $bib: String) {
    recordCapture(eventId: $eventId, bib: $bib) {
      capture { id bib capturedAtMs } errors
    }
  }
`;
