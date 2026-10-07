import CloudDoneIcon from "@mui/icons-material/CloudDone";
import CloudOffIcon from "@mui/icons-material/CloudOff";
import CloudUploadIcon from "@mui/icons-material/CloudUpload";
import ErrorIcon from "@mui/icons-material/Error";
import TimerIcon from "@mui/icons-material/Timer";
import TimerOffIcon from "@mui/icons-material/TimerOff";
import Chip from "@mui/material/Chip";
import Stack from "@mui/material/Stack";
import Tooltip from "@mui/material/Tooltip";
import type { SyncState } from "./sync";

export function syncLabel(s: Pick<SyncState, "pending" | "online" | "stopped" | "revoked">): string {
  if (s.revoked) return "Revoked";
  if (s.stopped) return "Sync stopped";
  if (!s.online) return s.pending ? `Offline · ${s.pending} to send` : "Offline";
  return s.pending ? `${s.pending} to send` : "Synced";
}

// Green synced, amber sending, red offline or stopped; plus the clock.
export function SyncPill({ state }: { state: SyncState }) {
  const label = syncLabel(state);
  const color = state.stopped || state.revoked || !state.online ? "error" : state.pending ? "warning" : "success";
  const icon = state.stopped || state.revoked ? <ErrorIcon /> : !state.online ? <CloudOffIcon /> : state.pending ? <CloudUploadIcon /> : <CloudDoneIcon />;
  return (
    <Stack direction="row" spacing={0.5} sx={{ alignItems: "center" }}>
      <Chip data-testid="sync-pill" size="small" color={color} icon={icon} label={label} />
      <Tooltip title={state.clockSynced ? `Clock synced (${state.offsetMs! > 0 ? "+" : ""}${state.offsetMs} ms)` : "Clock not synced yet"}>
        {state.clockSynced ? <TimerIcon color="success" fontSize="small" aria-label="Clock synced" /> : <TimerOffIcon color="warning" fontSize="small" aria-label="Clock not synced" />}
      </Tooltip>
    </Stack>
  );
}
