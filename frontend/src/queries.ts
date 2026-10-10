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
export type CheckpointInfo = { id: string; name: string; position: number; distanceKm: number | null; cutoffAtMs: number | null };
export type EventInfo = {
  id: string;
  name: string;
  date: string;
  location: string | null;
  timezone: string;
  discipline: string;
  subDiscipline: string | null;
  finishWithLeader: boolean;
  ageNextYear: boolean;
  bibFrom: number | null;
  bibTo: number | null;
  raceFormat: string;
  checkpoints: CheckpointInfo[];
  finishDistanceKm: number | null;
  finishCutoffAtMs: number | null;
  races: RaceInfo[];
};
export type EventData = { event: EventInfo };

const RACE_FIELDS = `id name defaultName nameOverride category ageGroup ageMin ageMax gender scheduledAtMs expectedDurationMs
  expectedLaps finishWithLeader finishWithLeaderOverride bibFrom bibTo`;

export const EVENT = gql`
  query Event($id: ID!) {
    event(id: $id) {
      id name date location discipline subDiscipline finishWithLeader ageNextYear timezone bibFrom bibTo
      raceFormat checkpoints { id name position distanceKm cutoffAtMs } finishDistanceKm finishCutoffAtMs
      races { ${RACE_FIELDS} }
    }
  }
`;

export type Discipline = { id: string; label: string; finishWithLeader: boolean; course: boolean; ageNextYear: boolean; subDisciplines: { id: string; label: string; finishWithLeader: boolean; course: boolean }[] };
export type DisciplinesData = { disciplines: Discipline[] };
export const DISCIPLINES = gql`
  query Disciplines { disciplines { id label finishWithLeader course ageNextYear subDisciplines { id label finishWithLeader course } } }
`;

export type EventInput = {
  name: string;
  date: string;
  location: string | null;
  discipline: string;
  subDiscipline: string | null;
  finishWithLeader: boolean;
  ageNextYear: boolean;
  timezone: string;
  raceFormat: string;
  bibFrom?: number | null;
  bibTo?: number | null;
};
export const CREATE_EVENT = gql`
  mutation CreateEvent($name: String!, $date: ISO8601Date!, $location: String, $discipline: String!, $subDiscipline: String,
                       $finishWithLeader: Boolean, $ageNextYear: Boolean, $timezone: String, $raceFormat: String) {
    createEvent(name: $name, date: $date, location: $location, discipline: $discipline, subDiscipline: $subDiscipline,
                finishWithLeader: $finishWithLeader, ageNextYear: $ageNextYear, timezone: $timezone, raceFormat: $raceFormat) {
      event { id } errors
    }
  }
`;
export const UPDATE_EVENT = gql`
  mutation UpdateEvent($id: ID!, $name: String, $date: ISO8601Date, $location: String, $discipline: String, $subDiscipline: String,
                       $finishWithLeader: Boolean, $ageNextYear: Boolean, $timezone: String, $raceFormat: String, $bibFrom: Int, $bibTo: Int) {
    updateEvent(id: $id, name: $name, date: $date, location: $location, discipline: $discipline, subDiscipline: $subDiscipline,
                finishWithLeader: $finishWithLeader, ageNextYear: $ageNextYear, timezone: $timezone, raceFormat: $raceFormat, bibFrom: $bibFrom, bibTo: $bibTo) {
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
export type CurrentWave = { scheduledAtMs: number | null; startAtMs: number; asOfMs: number; races: { id: string; name: string }[] };
export const CURRENT_WAVE = gql`
  query CurrentWave($eventId: ID!) { currentWave(eventId: $eventId) { scheduledAtMs startAtMs asOfMs races { id name } } }
`;
export const FLAG_OUT = gql`
  mutation FlagOut($raceId: ID!, $atMs: Millis) { flagOut(raceId: $raceId, atMs: $atMs) { ruling { id payload } errors } }
`;
export const SET_RACE_START = gql`
  mutation SetRaceStart($raceId: ID!, $atMs: Millis) { setRaceStart(raceId: $raceId, atMs: $atMs) { errors } }
`;

export type Split = { checkpointId: string | null; atMs: number | null; elapsedMs: number | null; segmentMs: number | null; inserted: boolean };
export type Row = {
  place: number | null;
  bib: string;
  name: string;
  status: string;
  laps: number;
  elapsedMs: number | null;
  gapLapsDown: number | null;
  gapMs: number | null;
  splits: Split[];
};
export type RaceStandings = {
  race: { id: string; name: string };
  state: string;
  lapCount: number | null;
  startAtMs: number | null;
  flagOutAtMs: number | null;
  flagOutLeaderBib: string | null;
  rows: Row[];
};
export type Suggestion = { key: string; kind: string; bib: string | null; raceId: string | null; message: string; needs: string[] };
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
        flagOutAtMs
        flagOutLeaderBib
        rows { place bib name status laps elapsedMs gapLapsDown gapMs splits { checkpointId atMs elapsedMs segmentMs inserted } }
      }
      suggestions { key kind bib raceId message needs }
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
export type CaptureRow = { id: string; bib: string | null; enteredBib: string | null; bibSource: "RULING" | "DEVICE" | "ENTERED"; capturedAtMs: number; atMs: number; deviceName: string; mine: boolean; lap: number | null; lapMs: number | null; typicalLapMs: number | null; lapFlag: LapFlag | null };
export type CaptureScreenData = {
  event: {
    id: string;
    name: string;
    races: { id: string; name: string }[];
    registrations: { bib: string; raceId: string; racer: { firstName: string; lastName: string } }[];
    captures: CaptureRow[];
  };
};
export const CAPTURE_SCREEN = gql`
  query CaptureScreen($id: ID!) {
    event(id: $id) {
      id name
      races { id name }
      registrations { bib raceId racer { firstName lastName } }
      captures { id bib enteredBib bibSource capturedAtMs atMs deviceName mine lap lapMs typicalLapMs lapFlag }
    }
  }
`;
export type RecordCaptureResult = { recordCapture: MutationResult & { capture: CaptureRow | null } };
export const RECORD_CAPTURE = gql`
  mutation RecordCapture($eventId: ID!, $bib: String) {
    recordCapture(eventId: $eventId, bib: $bib) {
      capture { id bib enteredBib bibSource capturedAtMs atMs deviceName mine lap lapMs typicalLapMs lapFlag } errors
    }
  }
`;
export const DELETE_CAPTURE = gql`
  mutation DeleteCapture($captureId: ID!) { deleteCapture(captureId: $captureId) { errors } }
`;

const REGISTRATION_FIELDS = `id bib age racingAge source checkedInAtMs officialStatus eligibilityWarnings race { id name }
  racer { firstName lastName gender team licenseNumber birthDate city state }`;
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
export type RacerFields = {
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
export const REGISTER_RACER = gql`
  mutation RegisterRacer($raceId: ID!, $bib: String, $age: Int, $racer: RacerInput!) {
    registerRacer(raceId: $raceId, bib: $bib, age: $age, racer: $racer) { registration { id } warnings errors }
  }
`;
export const UPDATE_REGISTRATION = gql`
  mutation UpdateRegistration($id: ID!, $raceId: ID, $bib: String, $age: Int, $racer: RacerInput) {
    updateRegistration(id: $id, raceId: $raceId, bib: $bib, age: $age, racer: $racer) { registration { id } warnings errors }
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
  mutation AssignBibs($eventId: ID!, $raceId: ID) { assignBibs(eventId: $eventId, raceId: $raceId) { assigned { bib name raceName } unfilled errors } }
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
export const SET_RACER_STATUS = gql`
  mutation SetRacerStatus($eventId: ID!, $bib: String!, $status: RacerStatusChange!) {
    setRacerStatus(eventId: $eventId, bib: $bib, status: $status) { errors }
  }
`;
export const PROBLEM_COUNT = gql`
  query ProblemCount($eventId: ID!) { standings(eventId: $eventId) { suggestions { key } } }
`;
export const CORRECT_CAPTURE_BIB = gql`
  mutation CorrectCaptureBib($captureId: ID!, $bib: String!) { correctCaptureBib(captureId: $captureId, bib: $bib) { capture { id } errors } }
`;
export type PhoneRow = {
  id: string;
  name: string;
  pairedAtMs: number;
  revokedAtMs: number | null;
  lastSeenAtMs: number | null;
  lastSyncAtMs: number | null;
  syncStoppedAtMs: number | null;
  clockOffsetMs: number | null;
  checkpointId: string | null;
};
export const DEVICES = gql`
  query Devices($eventId: ID!) {
    devices(eventId: $eventId) { id name pairedAtMs revokedAtMs lastSeenAtMs lastSyncAtMs syncStoppedAtMs clockOffsetMs checkpointId }
  }
`;
export const CREATE_PAIRING_TOKEN = gql`
  mutation CreatePairingToken($eventId: ID!, $checkpointId: ID) { createPairingToken(eventId: $eventId, checkpointId: $checkpointId) { token pairingUrl expiresAtMs errors } }
`;
export const REVOKE_DEVICE = gql`
  mutation RevokeDevice($id: ID!) { revokeDevice(deviceId: $id) { errors } }
`;
export type RacerCrossing = { ref: string; checkpointId: string | null; atMs: number; inserted: boolean; kind: string; lap: number | null; lapMs: number | null; source: string };
export type RacerFix = { id: string; kind: string; description: string; officialName: string | null; createdAtMs: number; undone: boolean; undoneBy: string | null };
export type RacerDetail = {
  bib: string;
  name: string;
  race: { id: string; name: string };
  status: string;
  place: number | null;
  laps: number;
  elapsedMs: number | null;
  gapLapsDown: number | null;
  gapMs: number | null;
  startAtMs: number | null;
  pullAtMs: number | null;
  finishRef: string | null;
  lapPositions: number[];
  splits: Split[];
  crossings: RacerCrossing[];
  rulings: RacerFix[];
};
export const RACER = gql`
  query Racer($eventId: ID!, $bib: String!) {
    racer(eventId: $eventId, bib: $bib) {
      bib name race { id name } status place laps elapsedMs gapLapsDown gapMs startAtMs pullAtMs finishRef lapPositions
      splits { checkpointId atMs elapsedMs segmentMs inserted }
      crossings { ref checkpointId atMs inserted kind lap lapMs source }
      rulings { id kind description officialName createdAtMs undone undoneBy }
    }
  }
`;
type FixResult = { ruling: { id: string } | null; errors: string[] };
export type FixResults = {
  voidCrossing?: FixResult;
  moveCrossing?: FixResult;
  insertCrossing?: FixResult;
  pullRacer?: FixResult;
  flagFinish?: FixResult;
  revertRuling?: FixResult;
};
export const VOID_CROSSING = gql`mutation VoidCrossing($eventId: ID!, $ref: String!) { voidCrossing(eventId: $eventId, ref: $ref) { ruling { id } errors } }`;
export const MOVE_CROSSING = gql`mutation MoveCrossing($eventId: ID!, $captureId: ID!, $bib: String!) { moveCrossing(eventId: $eventId, captureId: $captureId, bib: $bib) { ruling { id } errors } }`;
export const INSERT_CROSSING = gql`mutation InsertCrossing($eventId: ID!, $bib: String!, $atMs: Millis!) { insertCrossing(eventId: $eventId, bib: $bib, atMs: $atMs) { ruling { id } errors } }`;
export const PULL_RACER = gql`mutation PullRacer($eventId: ID!, $bib: String!, $atMs: Millis!) { pullRacer(eventId: $eventId, bib: $bib, atMs: $atMs) { ruling { id } errors } }`;
export const FLAG_FINISH = gql`mutation FlagFinish($eventId: ID!, $bib: String!, $ref: String!) { flagFinish(eventId: $eventId, bib: $bib, ref: $ref) { ruling { id } errors } }`;
export const REVERT_RULING = gql`mutation RevertRuling($id: ID!) { revertRuling(rulingId: $id) { ruling { id } errors } }`;
export type HistoryEntry = { id: string; kind: string; description: string; bib: string | null; officialName: string | null; createdAtMs: number; undone: boolean; undoneBy: string | null; undoneAtMs: number | null };
export const RULINGS = gql`
  query Rulings($eventId: ID!, $search: String, $limit: Int) {
    rulings(eventId: $eventId, search: $search, limit: $limit) { id kind description bib officialName createdAtMs undone undoneBy undoneAtMs }
  }
`;

export const SET_CHECKPOINTS = gql`
  mutation SetCheckpoints($eventId: ID!, $checkpoints: [CheckpointInput!]!, $finishDistanceKm: Float, $finishCutoffAtMs: Millis) {
    setCheckpoints(eventId: $eventId, checkpoints: $checkpoints, finishDistanceKm: $finishDistanceKm, finishCutoffAtMs: $finishCutoffAtMs) { errors }
  }
`;
export const SET_DEVICE_CHECKPOINT = gql`
  mutation SetDeviceCheckpoint($deviceId: ID!, $checkpointId: ID) { setDeviceCheckpoint(deviceId: $deviceId, checkpointId: $checkpointId) { errors } }
`;
