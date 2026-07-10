require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { createClient } = require('@supabase/supabase-js');

const app = express();
const PORT = process.env.PORT || 3000;

const supabase = createClient(
  process.env.PROJECT_URL.replace(/\/$/, ''),
  process.env.SERVICE_ROLE_KEY
);

app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.json({ status: 'RADAR backend running' });
});

app.use('/api/potholes', require('./routes/potholes'));

app.listen(PORT, () => {
  console.log(`RADAR backend running at http://localhost:${PORT}`);
});
