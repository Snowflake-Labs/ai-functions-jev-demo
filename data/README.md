# Dataset files

Copy the existing synthetic CSV into this folder. Use these exact filename, or update the `FILES` clauses in
[00_setup.sql](../sql/00_setup.sql) to match your actual names.

| File | Destination table | Tutorial use |
|---|---|---|
| `returns_tickets.csv` | `RETURNS_TICKETS` | Required input to the decision and optional LLM steps. |

## CSV contract

Use UTF-8, comma delimiters, one header row, and the exact column order below.
The loader skips the header and maps fields by position, not by header name.
Quote fields containing commas, quotation marks, or newlines with double
quotes; represent a quote inside a quoted field as two double quotes.

Empty fields load as SQL NULL. Dates use `YYYY-MM-DD`; booleans use `true` or
`false`; counts and urgency labels use integers. Keep intentional missing-text
cases: the tutorial counts them separately and does not send them to inference.

### returns_tickets.csv

```csv
TICKET_ID,ORDER_ID,REQUEST_DATE,CHANNEL,TICKET_TEXT
```

`REQUEST_DATE` is a date; all other fields are text. Ticket IDs must be non-empty
and unique. The prior contract allows missing order IDs and includes email,
chat, and call-transcript channels.