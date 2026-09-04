const express = require('express');

const app = express();
app.use(express.json());

app.get('/healthz', (_req, res) => res.status(200).send('ok'));

// Mock payment processing: always succeeds unless amount_cents is absurdly high,
// just so the demo has a visible failure path too.
app.post('/charge', (req, res) => {
  const { order_id, amount_cents } = req.body;
  if (!order_id || !amount_cents) {
    return res.status(400).json({ error: 'order_id and amount_cents required' });
  }

  if (amount_cents > 1000000) {
    return res.json({ order_id, status: 'declined', reason: 'amount exceeds mock limit' });
  }

  res.json({
    order_id,
    status: 'charged',
    transaction_id: `mock_txn_${Date.now()}`,
    amount_cents,
  });
});

const port = process.env.PORT || 4003;
app.listen(port, () => console.log(`payment-service listening on ${port}`));
