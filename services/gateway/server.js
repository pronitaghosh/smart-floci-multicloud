const express = require('express');

const app = express();
app.use(express.json());

const USER_SERVICE_URL = process.env.USER_SERVICE_URL;
const ORDER_SERVICE_URL = process.env.ORDER_SERVICE_URL;

app.get('/healthz', (_req, res) => res.status(200).send('ok'));

async function proxy(res, url, options) {
  try {
    const upstream = await fetch(url, options);
    const body = await upstream.json().catch(() => ({}));
    res.status(upstream.status).json(body);
  } catch (err) {
    res.status(502).json({ error: `upstream unreachable: ${err.message}` });
  }
}

app.get('/api/users/:id', (req, res) =>
  proxy(res, `${USER_SERVICE_URL}/users/${req.params.id}`)
);

app.post('/api/users', (req, res) =>
  proxy(res, `${USER_SERVICE_URL}/users`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(req.body),
  })
);

app.get('/api/orders/:id', (req, res) =>
  proxy(res, `${ORDER_SERVICE_URL}/orders/${req.params.id}`)
);

app.post('/api/orders', (req, res) =>
  proxy(res, `${ORDER_SERVICE_URL}/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(req.body),
  })
);

const port = process.env.PORT || 4000;
app.listen(port, () => console.log(`gateway listening on ${port}`));
