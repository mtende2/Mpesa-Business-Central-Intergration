// Callback relay: Safaricom Daraja -> Business Central API
//
// Daraja posts unauthenticated JSON to a public URL. Business Central APIs
// require an Entra ID (OAuth 2.0) token. This small Azure Function receives
// the Daraja callbacks, maps them, and calls the M-Pesa API page in BC
// using the client-credentials flow.
//
// App settings required:
//   TENANT_ID, CLIENT_ID, CLIENT_SECRET   Entra app registered in BC (Microsoft Entra Applications page)
//   BC_ENVIRONMENT                        e.g. Production or Sandbox
//   BC_COMPANY_ID                         company GUID
//   RELAY_SHARED_KEY                      random value appended to the callback URL (?key=...)

const { app } = require('@azure/functions');

const api = () =>
  `https://api.businesscentral.dynamics.com/v2.0/${process.env.TENANT_ID}/${process.env.BC_ENVIRONMENT}` +
  `/api/mtende/mpesa/v1.0/companies(${process.env.BC_COMPANY_ID})/mpesaTransactions`;

async function getToken() {
  const res = await fetch(`https://login.microsoftonline.com/${process.env.TENANT_ID}/oauth2/v2.0/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: process.env.CLIENT_ID,
      client_secret: process.env.CLIENT_SECRET,
      scope: 'https://api.businesscentral.dynamics.com/.default',
    }),
  });
  if (!res.ok) throw new Error(`Token request failed: ${res.status}`);
  return (await res.json()).access_token;
}

async function bc(path, method, body, token) {
  const res = await fetch(api() + path, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`BC ${method} ${path} failed: ${res.status} ${text}`);
  return text ? JSON.parse(text) : {};
}

function authorised(request) {
  return request.query.get('key') === process.env.RELAY_SHARED_KEY;
}

// Lipa Na M-Pesa Online (STK Push) result
app.http('stkCallback', {
  methods: ['POST'],
  authLevel: 'anonymous',
  handler: async (request, context) => {
    if (!authorised(request)) return { status: 401 };
    const cb = (await request.json()).Body.stkCallback;
    const items = Object.fromEntries((cb.CallbackMetadata?.Item ?? []).map(i => [i.Name, i.Value]));

    const token = await getToken();
    const found = await bc(`?$filter=checkoutRequestId eq '${cb.CheckoutRequestID}'`, 'GET', null, token);
    if (!found.value?.length) {
      context.warn(`No BC transaction for ${cb.CheckoutRequestID}`);
      return { status: 200, jsonBody: { ResultCode: 0, ResultDesc: 'Accepted' } };
    }

    await bc(`(${found.value[0].id})/Microsoft.NAV.completeStkPush`, 'POST', {
      resultCode: cb.ResultCode,
      resultDescription: cb.ResultDesc,
      receiptNo: items.MpesaReceiptNumber ?? '',
      transactionDate: String(items.TransactionDate ?? ''),
    }, token);

    return { status: 200, jsonBody: { ResultCode: 0, ResultDesc: 'Accepted' } };
  },
});

// C2B PayBill confirmation (customer paid directly to the PayBill)
app.http('c2bConfirmation', {
  methods: ['POST'],
  authLevel: 'anonymous',
  handler: async (request) => {
    if (!authorised(request)) return { status: 401 };
    const c = await request.json();
    const token = await getToken();

    try {
      await bc('', 'POST', {
        receiptNo: c.TransID,
        amount: Number(c.TransAmount),
        accountReference: (c.BillRefNumber ?? '').toUpperCase().slice(0, 20),
        phoneNo: String(c.MSISDN ?? '').slice(0, 20),
        payerName: [c.FirstName, c.MiddleName, c.LastName].filter(Boolean).join(' ').slice(0, 100),
        transactionDate: toIso(c.TransTime),
      }, token);
    } catch (err) {
      // Duplicate receipts are rejected by BC; acknowledge so Daraja stops retrying.
      if (!String(err.message).includes('already been recorded')) throw err;
    }
    return { status: 200, jsonBody: { ResultCode: 0, ResultDesc: 'Accepted' } };
  },
});

// Daraja time 20261023104512 is East Africa Time (UTC+3).
function toIso(t) {
  const s = String(t ?? '');
  if (s.length !== 14) return new Date().toISOString();
  return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}T${s.slice(8, 10)}:${s.slice(10, 12)}:${s.slice(12, 14)}+03:00`;
}
