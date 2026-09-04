const express = require('express');
const { Pool } = require('pg');

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

async function ensureSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT now()
    )
  `);
}

app.get('/healthz', (_req, res) => res.status(200).send('ok'));

app.get('/users/:id', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT id, email, name FROM users WHERE id = $1', [req.params.id]);
    if (!rows.length) return res.status(404).json({ error: 'not found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/users', async (req, res) => {
  const { email, name } = req.body;
  if (!email || !name) return res.status(400).json({ error: 'email and name required' });
  try {
    const { rows } = await pool.query(
      'INSERT INTO users (email, name) VALUES ($1, $2) RETURNING id, email, name',
      [email, name]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const port = process.env.PORT || 4001;
app.listen(port, async () => {
  try {
    await ensureSchema();
    console.log(`user-service listening on ${port}, schema ready`);
  } catch (err) {
    console.error('schema init failed, will retry on first query:', err.message);
    console.log(`user-service listening on ${port}`);
  }
});
