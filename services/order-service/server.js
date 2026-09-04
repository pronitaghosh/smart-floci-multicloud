const express = require('express');
const { Pool } = require('pg');
const { createClient } = require('redis');

const app = express();
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  max: 5,
  connectionTimeoutMillis: 3000,
});

// Caching is optional: floci's free edition can't emulate ElastiCache, so
// REDIS_HOST is empty for local runs and the service runs without a cache
// rather than failing every request.
const cacheEnabled = Boolean(process.env.REDIS_HOST);

const redis = cacheEnabled
  ? createClient({
      socket: {
        host: process.env.REDIS_HOST,
        port: process.env.REDIS_PORT || 6379,
        connectTimeout: 3000,
      },
    })
  : null;

if (redis) redis.on('error', (err) => console.error('redis error:', err.message));

// Wrappers so the request handlers don't need to branch on cacheEnabled. A
// closed client rejects (and older node-redis throws synchronously), so both
// paths are guarded.
async function cacheGet(key) {
  if (!redis?.isOpen) return null;
  try {
    return await redis.get(key);
  } catch {
    return null;
  }
}

async function cacheSet(key, ttlSeconds, value) {
  if (!redis?.isOpen) return;
  try {
    await redis.setEx(key, ttlSeconds, value);
  } catch {
    /* cache writes are best-effort */
  }
}

async function ensureSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS orders (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL,
      item TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TIMESTAMPTZ DEFAULT now()
    )
  `);
}

app.get('/healthz', (_req, res) => res.status(200).send('ok'));

app.get('/orders/:id', async (req, res) => {
  const cacheKey = `order:${req.params.id}`;
  try {
    const cached = await cacheGet(cacheKey);
    if (cached) return res.json({ ...JSON.parse(cached), cached: true });

    const { rows } = await pool.query('SELECT * FROM orders WHERE id = $1', [req.params.id]);
    if (!rows.length) return res.status(404).json({ error: 'not found' });

    await cacheSet(cacheKey, 30, JSON.stringify(rows[0]));
    res.json({ ...rows[0], cached: false });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/orders', async (req, res) => {
  const { user_id, item, amount_cents } = req.body;
  if (!user_id || !item || !amount_cents) {
    return res.status(400).json({ error: 'user_id, item, amount_cents required' });
  }
  try {
    const { rows } = await pool.query(
      'INSERT INTO orders (user_id, item, amount_cents) VALUES ($1, $2, $3) RETURNING *',
      [user_id, item, amount_cents]
    );
    const order = rows[0];

    // Call payment-service to process this order
    const paymentUrl = `${process.env.PAYMENT_SERVICE_URL}/charge`;
    const paymentRes = await fetch(paymentUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ order_id: order.id, amount_cents }),
    });
    const paymentResult = await paymentRes.json();

    const finalStatus = paymentResult.status === 'charged' ? 'paid' : 'payment_failed';
    await pool.query('UPDATE orders SET status = $1 WHERE id = $2', [finalStatus, order.id]);

    res.status(201).json({ ...order, status: finalStatus, payment: paymentResult });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const port = process.env.PORT || 4002;
app.listen(port, async () => {
  if (redis) {
    try {
      await redis.connect();
    } catch (err) {
      console.error('redis connect failed, running without cache:', err.message);
    }
  } else {
    console.log('REDIS_HOST unset -- caching disabled');
  }
  try {
    await ensureSchema();
    console.log(`order-service listening on ${port}, schema ready`);
  } catch (err) {
    console.error('schema init failed, will retry on first query:', err.message);
    console.log(`order-service listening on ${port}`);
  }
});
