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
  bibFrom: number | null;
  bibTo: number | null;
};
export type EventInfo = {
  id: string;
  name: string;
  date: string;
  location: string | null;
  discipline: string;
  subDiscipline: string | null;
  finishWithLeader: boolean;
  bibFrom: number | null;
  bibTo: number | null;
  races: RaceInfo[];
};
export type EventData = { event: EventInfo };

const RACE_FIELDS = `id name defaultName nameOverride category ageGroup ageMin ageMax gender scheduledAtMs expectedDurationMs
  expectedLaps finishWithLeader finishWithLeaderOverride bibFrom bibTo`;

export const EVENT = gql`
  query Event($id: ID!) {
    event(id: $id) {
      id name date location discipline subDiscipline finishWithLeader bibFrom bibTo
      races { ${RACE_FIELDS} }
    }
  }
`;

export type Discipline = { id: string; label: string; finishWithLeader: boolean; subDisciplines: { id: string; label: string; finishWithLeader: boolean }[] };
export type DisciplinesData = { disciplines: Discipline[] };
export const DISCIPLINES = gql`
  query Disciplines { disciplines { id label finishWithLeader subDisciplines { id label finishWithLeader } } }
`;

export type EventInput = {
  name: string;
  date: string;
  location: string | null;
  discipline: string;
  subDiscipline: string | null;
  finishWithLeader: boolean;
  bibFrom?: number | null;
  bibTo?: number | null;
};
export const CREATE_EVENT = gql`
  mutation CreateEvent($name: String!, $date: ISO8601Date!, $location: String, $discipline: String!, $subDiscipline: String, $finishWithLeader: Boolean) {
    createEvent(name: $name, date: $date, location: $location, discipline: $discipline, subDiscipline: $subDiscipline, finishWithLeader: $finishWithLeader) {
      event { id } errors
    }
  }
`;
export const UPDATE_EVENT = gql`
  mutation UpdateEvent($id: ID!, $name: String, $date: ISO8601Date, $location: String, $discipline: String, $subDiscipline: String,
                       $finishWithLeader: Boolean, $bibFrom: Int, $bibTo: Int) {
    updateEvent(id: $id, name: $name, date: $date, location: $location, discipline: $discipline, subDiscipline: $subDiscipline,
                finishWithLeader: $finishWithLeader, bibFrom: $bibFrom, bibTo: $bibTo) {
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
  bibFrom: number | null;
  bibTo: number | null;
};
const RACE_ARGS = `$category: String, $ageGroup: String, $ageMin: Int, $ageMax: Int, $nameOverride: String, $expectedDurationMs: Millis,
  $expectedLaps: Int, $finishWithLeader: Boolean, $bibFrom: Int, $bibTo: Int`;
const RACE_VALUES = `category: $category, ageGroup: $ageGroup, ageMin: $ageMin, ageMax: $ageMax, nameOverride: $nameOverride,
  expectedDurationMs: $expectedDurationMs, expectedLaps: $expectedLaps, finishWithLeader: $finishWithLeader, bibFrom: $bibFrom, bibTo: $bibTo`;
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
export type Unassigned = { captureId: string; atMs: number; bib: string | null };
export type StandingsData = {
  standings: { stale: boolean; error: string | null; races: RaceStandings[]; suggestions: Suggestion[]; unassigned: Unassigned[] };
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
      unassigned { captureId atMs bib }
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

export type LapFlag = "missed" | "long" | "short";
export type CaptureRow = { id: string; bib: string | null; capturedAtMs: number; lap: number | null; lapMs: number | null; typicalLapMs: number | null; lapFlag: LapFlag | null };
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
      myCaptures { id bib capturedAtMs lap lapMs typicalLapMs lapFlag }
    }
  }
`;
export type RecordCaptureResult = { recordCapture: MutationResult & { capture: CaptureRow | null } };
export const RECORD_CAPTURE = gql`
  mutation RecordCapture($eventId: ID!, $bib: String) {
    recordCapture(eventId: $eventId, bib: $bib) {
      capture { id bib capturedAtMs lap lapMs typicalLapMs lapFlag } errors
    }
  }
`;
export const DELETE_CAPTURE = gql`
  mutation DeleteCapture($captureId: ID!) { deleteCapture(captureId: $captureId) { errors } }
`;

const REGISTRATION_FIELDS = `id bib age source checkedInAtMs eligibilityWarnings race { id name }
  rider { firstName lastName gender team licenseNumber birthDate city state }`;
export type RegistrationScreenData = {
  event: {
    id: string;
    name: string;
    races: { id: string; name: string; gender: string }[];
    registrations: import("./registration").RegistrationRow[];
    registrationCounts: { registered: number; checkedIn: number; needsBib: number };
  };
};
export const REGISTRATION_SCREEN = gql`
  query RegistrationScreen($id: ID!) {
    event(id: $id) {
      id name
      races { id name gender }
      registrations { ${REGISTRATION_FIELDS} }
      registrationCounts { registered checkedIn needsBib }
    }
  }
`;
export type RiderFields = {
  firstName: string;
  lastName: string;
  gender: string;
  birthDate: string | null;
  team: string | null;
  licenseNumber: string | null;
  city: string | null;
  state: string | null;
};
export type RegistrationResult = { registration: { id: string } | null; warnings: string[]; errors: string[] };
export const REGISTER_RIDER = gql`
  mutation RegisterRider($raceId: ID!, $bib: String, $age: Int, $rider: RiderInput!) {
    registerRider(raceId: $raceId, bib: $bib, age: $age, rider: $rider) { registration { id } warnings errors }
  }
`;
export const UPDATE_REGISTRATION = gql`
  mutation UpdateRegistration($id: ID!, $raceId: ID, $bib: String, $age: Int, $rider: RiderInput) {
    updateRegistration(id: $id, raceId: $raceId, bib: $bib, age: $age, rider: $rider) { registration { id } warnings errors }
  }
`;
export const UPDATE_BIB = gql`
  mutation UpdateBib($id: ID!, $bib: String) {
    updateRegistration(id: $id, bib: $bib) { registration { id } warnings errors }
  }
`;
export const SET_CHECKED_IN = gql`
  mutation SetCheckedIn($id: ID!, $checkedIn: Boolean!) {
    setCheckedIn(registrationId: $id, checkedIn: $checkedIn) { registration { id checkedInAtMs } errors }
  }
`;
export const REMOVE_REGISTRATION = gql`
  mutation RemoveRegistration($id: ID!) { removeRegistration(id: $id) { errors } }
`;
export type AssignBibsResult = { assignBibs: { assigned: { bib: string; name: string; raceName: string }[]; unfilled: string[]; errors: string[] } };
export const ASSIGN_BIBS = gql`
  mutation AssignBibs($eventId: ID!) { assignBibs(eventId: $eventId) { assigned { bib name raceName } unfilled errors } }
`;
export type ImportCategory = { value: string; count: number; raceId: string | null; skip: boolean };
export type AnalyzeImportResult = {
  analyzeImport: { headers: string[]; mapping: Record<string, string>; categories: ImportCategory[]; errors: string[] };
};
export const ANALYZE_IMPORT = gql`
  mutation AnalyzeImport($eventId: ID!, $csv: String!) {
    analyzeImport(eventId: $eventId, csv: $csv) { headers mapping categories { value count raceId skip } errors }
  }
`;
export type ImportSummary = {
  created: number;
  updated: number;
  skipped: number;
  rowErrors: { row: number; message: string }[];
  warnings: { row: number; message: string }[];
  notInFile: string[];
  errors: string[];
};
export const IMPORT_REGISTRATIONS = gql`
  mutation ImportRegistrations($eventId: ID!, $csv: String!, $mapping: JSON, $categories: JSON, $dryRun: Boolean) {
    importRegistrations(eventId: $eventId, csv: $csv, mapping: $mapping, categories: $categories, dryRun: $dryRun) {
      created updated skipped rowErrors { row message } warnings { row message } notInFile errors
    }
  }
`;
