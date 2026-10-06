import { useMutation } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogTitle from "@mui/material/DialogTitle";
import Stack from "@mui/material/Stack";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useState, type ChangeEvent } from "react";
import { ANALYZE_IMPORT, IMPORT_REGISTRATIONS, type AnalyzeImportResult, type ImportCategory, type ImportSummary } from "../queries";
import { RaceDialog } from "./RaceDialog";

type Props = {
  eventId: string;
  races: { id: string; name: string }[];
  refetchRaces: () => Promise<unknown>;
  onClose: (changed: boolean) => void;
};

const FIELDS: [string, string][] = [
  ["first_name", "First name"],
  ["last_name", "Last name"],
  ["gender", "Gender"],
  ["category", "Category"],
  ["bib", "Bib"],
  ["age", "Age"],
  ["birth_date", "Birth date"],
  ["team", "Team"],
  ["license_number", "License"],
  ["city", "City"],
  ["state", "State"],
];

const summaryLine = (s: ImportSummary) => `${s.created} new · ${s.updated} updated · ${s.skipped} skipped · ${s.rowErrors.length} errors`;

// File → columns and categories → preview (dry run) → import → summary.
export function ImportDialog({ eventId, races, refetchRaces, onClose }: Props) {
  const [analyze] = useMutation<AnalyzeImportResult>(ANALYZE_IMPORT);
  const [runImport] = useMutation<{ importRegistrations: ImportSummary }>(IMPORT_REGISTRATIONS);
  const [csv, setCsv] = useState<string | null>(null);
  const [headers, setHeaders] = useState<string[]>([]);
  const [mapping, setMapping] = useState<Record<string, string>>({});
  const [categories, setCategories] = useState<ImportCategory[]>([]);
  const [choices, setChoices] = useState<Record<string, string>>({}); // value => race id | "skip" | ""
  const [creatingFor, setCreatingFor] = useState<string | null>(null);
  const [preview, setPreview] = useState<ImportSummary | null>(null);
  const [done, setDone] = useState<ImportSummary | null>(null);
  const [errors, setErrors] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);

  async function pickFile(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const text = await file.text();
    setErrors([]);
    setPreview(null);
    const result = (await analyze({ variables: { eventId, csv: text } })).data?.analyzeImport;
    if (!result || result.errors.length) return setErrors(result?.errors ?? ["Couldn't read the file"]);
    setCsv(text);
    setHeaders(result.headers);
    setMapping(result.mapping);
    setCategories(result.categories);
    setChoices(Object.fromEntries(result.categories.map((c) => [c.value, c.skip ? "skip" : (c.raceId ?? "")])));
  }

  function choose(value: string, choice: string) {
    setPreview(null);
    if (choice === "create") setCreatingFor(value);
    else setChoices({ ...choices, [value]: choice });
  }

  const categoryPayload = () =>
    Object.fromEntries(
      Object.entries(choices)
        .filter(([, choice]) => choice)
        .map(([value, choice]) => [value, choice === "skip" ? { skip: true } : { raceId: choice }]),
    );

  async function run(dryRun: boolean) {
    if (!csv) return;
    setBusy(true);
    setErrors([]);
    try {
      const result = (await runImport({ variables: { eventId, csv, mapping, categories: categoryPayload(), dryRun } })).data?.importRegistrations;
      if (!result || result.errors.length) setErrors(result?.errors ?? ["Import failed"]);
      else if (dryRun) setPreview(result);
      else setDone(result);
    } catch (e) {
      setErrors([(e as Error).message]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onClose={() => onClose(done != null)} maxWidth="md" fullWidth>
      <DialogTitle>Import registrations</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ pt: 1 }}>
          {errors.map((e) => (
            <Alert key={e} severity="error">{e}</Alert>
          ))}
          {done ? (
            <Summary result={done} />
          ) : (
            <>
              <Button component="label" variant="outlined" sx={{ alignSelf: "start" }}>
                {csv ? "Choose a different file" : "Choose CSV file"}
                <input hidden type="file" accept=".csv,text/csv" aria-label="CSV file" onChange={pickFile} />
              </Button>
              {csv && (
                <>
                  <Typography variant="subtitle1">Columns</Typography>
                  <Stack direction="row" sx={{ flexWrap: "wrap", gap: 2 }}>
                    {FIELDS.map(([field, label]) => (
                      <TextField key={field} select label={`${label} column`} value={mapping[field] ?? ""} sx={{ width: 220 }}
                        onChange={(e) => { setPreview(null); setMapping({ ...mapping, [field]: e.target.value }); }}
                        slotProps={{ select: { native: true }, inputLabel: { shrink: true } }}>
                        <option value="">—</option>
                        {headers.map((h) => <option key={h} value={h}>{h}</option>)}
                      </TextField>
                    ))}
                  </Stack>
                  <Typography variant="subtitle1">Categories</Typography>
                  <Table size="small">
                    <TableHead>
                      <TableRow>
                        <TableCell>In the file</TableCell>
                        <TableCell>Rows</TableCell>
                        <TableCell>Race</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {categories.map((c) => (
                        <TableRow key={c.value}>
                          <TableCell>{c.value}</TableCell>
                          <TableCell>{c.count}</TableCell>
                          <TableCell>
                            <TextField select size="small" value={choices[c.value] ?? ""} onChange={(e) => choose(c.value, e.target.value)}
                              slotProps={{ select: { native: true }, htmlInput: { "aria-label": `Race for ${c.value}` } }} sx={{ minWidth: 240 }}>
                              <option value="">Choose…</option>
                              {races.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                              <option value="skip">Skip (not a race)</option>
                              <option value="create">Create race…</option>
                            </TextField>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  {preview && (
                    <Alert severity={preview.rowErrors.length ? "warning" : "info"}>
                      <Typography>{summaryLine(preview)}</Typography>
                      <Messages result={preview} />
                    </Alert>
                  )}
                </>
              )}
            </>
          )}
        </Stack>
      </DialogContent>
      <DialogActions>
        {done ? (
          <Button variant="contained" onClick={() => onClose(true)}>Done</Button>
        ) : (
          <>
            <Button onClick={() => onClose(false)}>Cancel</Button>
            <Button onClick={() => run(true)} disabled={!csv || busy}>Preview</Button>
            <Button variant="contained" onClick={() => run(false)} disabled={!preview || busy}>Import</Button>
          </>
        )}
      </DialogActions>
      {creatingFor && (
        <RaceDialog eventId={eventId} race={null} startAtMs={null} canSetStart={false} suggestedName={creatingFor}
          onClose={(saved, raceId) => {
            const value = creatingFor;
            setCreatingFor(null);
            if (saved && raceId) void refetchRaces().then(() => setChoices((current) => ({ ...current, [value]: raceId })));
          }} />
      )}
    </Dialog>
  );
}

function Messages({ result }: { result: ImportSummary }) {
  return (
    <>
      {result.rowErrors.map((m) => <Typography key={`e${m.row}${m.message}`} variant="body2">Row {m.row}: {m.message}</Typography>)}
      {result.warnings.map((m) => <Typography key={`w${m.row}${m.message}`} variant="body2" color="warning.main">Row {m.row}: {m.message}</Typography>)}
    </>
  );
}

function Summary({ result }: { result: ImportSummary }) {
  return (
    <Stack spacing={1}>
      <Alert severity="success">Imported {result.created} new · {result.updated} updated · {result.skipped} skipped</Alert>
      <Messages result={result} />
      {result.notInFile.length > 0 && (
        <Alert severity="info">
          <Typography>Registered before but not in this file (not removed):</Typography>
          {result.notInFile.map((n) => <Typography key={n} variant="body2">{n}</Typography>)}
        </Alert>
      )}
    </Stack>
  );
}
