import { useMutation } from "@apollo/client/react";
import MoreVertIcon from "@mui/icons-material/MoreVert";
import IconButton from "@mui/material/IconButton";
import Menu from "@mui/material/Menu";
import MenuItem from "@mui/material/MenuItem";
import Tooltip from "@mui/material/Tooltip";
import { useState } from "react";
import { SET_RACER_STATUS, type MutationResult, type Row } from "../queries";

const OFFICIAL = ["DNF", "DNS", "DSQ"];

// Mark a racer DNF, DNS or DSQ, or clear it (the hub records a ruling either way).
export function RacerStatusMenu({ eventId, row, onChanged }: { eventId: string; row: Row; onChanged: () => void }) {
  const [setStatus] = useMutation<{ setRacerStatus: MutationResult }>(SET_RACER_STATUS);
  const [anchor, setAnchor] = useState<HTMLElement | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function choose(status: "DNF" | "DNS" | "DSQ" | "NONE") {
    setAnchor(null);
    try {
      const errors = (await setStatus({ variables: { eventId, bib: row.bib, status } })).data?.setRacerStatus.errors ?? [];
      setError(errors.length ? errors.join("; ") : null);
    } catch (e) {
      setError((e as Error).message);
    }
    onChanged();
  }

  return (
    <>
      <Tooltip title={error ?? ""} open={error != null} onClose={() => setError(null)}>
        <IconButton size="small" color={error ? "error" : "default"} aria-label={`Status actions for ${row.name}`} onClick={(e) => setAnchor(e.currentTarget)}>
          <MoreVertIcon fontSize="small" />
        </IconButton>
      </Tooltip>
      <Menu anchorEl={anchor} open={anchor != null} onClose={() => setAnchor(null)}>
        {row.status !== "DNF" && <MenuItem onClick={() => void choose("DNF")}>Mark DNF</MenuItem>}
        {row.status !== "DNS" && <MenuItem onClick={() => void choose("DNS")}>Mark DNS</MenuItem>}
        {row.status !== "DSQ" && <MenuItem onClick={() => void choose("DSQ")}>Mark DSQ</MenuItem>}
        {OFFICIAL.includes(row.status) && <MenuItem onClick={() => void choose("NONE")}>Clear {row.status}</MenuItem>}
      </Menu>
    </>
  );
}
