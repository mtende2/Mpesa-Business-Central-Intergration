# M-Pesa Payments for Business Central

An AL extension for Microsoft Dynamics 365 Business Central that collects **M-Pesa** payments through the Safaricom **Daraja API**, matches them to customers and invoices, and posts them as applied customer payments. The posting runs either on demand or automatically from the job queue.

## What it does

| Flow | How it works |
|---|---|
| **STK Push (Lipa Na M-Pesa Online)** | From a posted sales invoice, **Request M-Pesa Payment** sends a payment prompt to the customer's phone for the remaining amount. The result comes back through the callback relay. |
| **C2B PayBill confirmations** | When a customer pays the PayBill directly, the confirmation is registered and matched using the account reference: an invoice number applies the payment to that invoice, and a customer number posts it on account. |
| **Matching & exceptions** | Payments that can't be matched are marked **Unmatched**. Assigning a customer on the transaction list releases them for posting. |
| **Posting** | Each payment posts through `Gen. Jnl.-Post Line` as a customer payment against the M-Pesa bank account, applied to the invoice, with the M-Pesa receipt as External Document No. |
| **Automation** | A recurring job queue entry posts every matched payment. Each one posts in its own transaction, so a single failure is logged on that row and never blocks the batch. |

## Architecture

```
 Business Central                          Azure Function relay                Safaricom Daraja
 ─────────────────                         ────────────────────                ────────────────
 Posted Sales Invoice ── STK Push ───────────────────────────────────────────▶ /stkpush/v1/processrequest
 (MPESA API Mgt.)       OAuth token (cached)                                    customer approves on phone
                                                                                        │
 MPESA Transaction API ◀── completeStkPush ── stkCallback  ◀──── callback ──────────────┘
   (API page, Entra ID)  ◀── POST (C2B)    ── c2bConfirmation ◀── PayBill confirmation
          │
 MPESA Posting Mgt. ── Gen. Jnl.-Post Line ──▶ Customer & Bank ledger entries
          ▲
 Job Queue (MPESA Auto Post Job, every 5 min)
```

Daraja posts unauthenticated JSON to a public URL, while Business Central APIs need an Entra ID token. The relay in `/relay` bridges the two. It validates a shared key on the callback URL, gets a client-credentials token, and calls the extension's API page.

## Objects

| ID | Type | Name | Purpose |
|---|---|---|---|
| 50100 | Table / Page | MPESA Setup | Environment, short code, callback URL, posting setup, credentials |
| 50101 | Table / Page | MPESA Transaction(s) | Transaction log with status, matching and posting actions |
| 50102 | API Page | MPESA Transaction API | `mtende/mpesa/v1.0` endpoint with the `completeStkPush` bound action |
| 50100 | Codeunit | MPESA API Mgt. | OAuth, STK Push, callbacks, account matching, phone/time helpers |
| 50101 | Codeunit | MPESA Posting Mgt. | Payment posting, batch posting, job queue setup |
| 50102 | Codeunit | MPESA Post Transaction | `Codeunit.Run` wrapper for isolated, error-capturing posting |
| 50103 | Codeunit | MPESA Auto Post Job | Job queue entry point |
| 50100 | Page Ext. | MPESA Posted Sales Invoice | **Request M-Pesa Payment** action |
| 50100–50102 | Enums | Status, Type, Environment | Extensible status and type enums |
| 50100 | Permission Set | MPESA ALL | Assignable permissions |

## Design decisions

- **Secrets never touch a table.** The consumer key, consumer secret and passkey live in `IsolatedStorage` and flow as `SecretText`. The STK password, Base64(shortcode + passkey + timestamp), is built as `SecretText` and injected into the request body without ever becoming plain text.
- **Token caching.** The Daraja OAuth token is cached in isolated storage and refreshed a minute before it expires, and the cache is cleared on a 401.
- **Idempotency.** Duplicate M-Pesa receipts are rejected, and repeat STK callbacks are ignored once a transaction has left Pending. Daraja retries callbacks, so both of these matter.
- **Correct timestamps.** Daraja expects `yyyyMMddHHmmss` in East Africa Time, so the timestamp is built from UTC + 3h. That keeps it independent of the server's time zone.
- **Phone normalisation.** `07…`, `01…`, `+2547…` and `2547…` all normalise to `2547…/2541…`, and anything else is rejected before calling Safaricom.
- **Extensibility.** Integration events (`OnBeforeResolveAccountReference`, `OnBeforePostMpesaPayment`, `OnAfterPostMpesaPayment` and others) let partners change matching or posting without modifying this app.
- **Safe batch posting.** IDs are collected first, then each payment posts inside `Codeunit.Run` after a `Commit`, so a failure rolls back only that payment and records `GetLastErrorText()`.


## Testing in a sandbox

1. Post a sales invoice for a customer whose **Mobile Phone No.** is your Safaricom test number.
2. On the posted invoice, choose **Request M-Pesa Payment** and approve the prompt on the phone.
3. Open **M-Pesa Transactions**. The entry moves from Pending to Completed and then Posted.
4. Check the customer ledger: the invoice should now be closed by an applied payment, with the M-Pesa receipt as External Document No.
5. Send a duplicate C2B callback and confirm it's rejected. Send one with an unknown reference and confirm it shows as **Unmatched**.

## Roadmap

- Automated test app (phone normalisation, timestamp, matching, posting, duplicates)
- Transaction Status Query API for STK requests that never received a callback
- B2C disbursements (refunds, supplier payouts)
- Daily reconciliation against the PayBill statement
