require('dotenv').config();
const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.PROJECT_URL.replace(/\/$/, ''),
  process.env.SERVICE_ROLE_KEY
);

const VALID_STATUSES = ['reported', 'verified', 'in_progress', 'fixed', 'rejected'];

// GET /api/potholes?page=1&status=reported
router.get('/', async (req, res) => {
  const { page = 1, limit = 20, status } = req.query;
  const from = (page - 1) * limit;
  const to = from + Number(limit) - 1;

  let query = supabase
    .from('potholes')
    .select(`
      *,
      reported_by_profile:profiles!reported_by(full_name, avatar_url),
      pothole_media(file_path, is_primary, media_type)
    `)
    .order('created_at', { ascending: false })
    .range(from, to);

  if (status) query = query.eq('status', status);

  const { data, error } = await query;
  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// GET /api/potholes/:id
router.get('/:id', async (req, res) => {
  const { data, error } = await supabase
    .from('potholes')
    .select(`
      *,
      reported_by_profile:profiles!reported_by(full_name, avatar_url),
      pothole_media(file_path, is_primary, media_type),
      comments(id, content, created_at, user_id, profiles(full_name))
    `)
    .eq('id', req.params.id)
    .single();

  if (error) return res.status(404).json({ error: 'Not found' });
  res.json(data);
});

// PATCH /api/potholes/:id/status  (government only — validated server-side via service role)
router.patch('/:id/status', async (req, res) => {
  const { status } = req.body;
  if (!VALID_STATUSES.includes(status)) {
    return res.status(400).json({ error: `status must be one of: ${VALID_STATUSES.join(', ')}` });
  }

  const { data, error } = await supabase
    .from('potholes')
    .update({ status, updated_at: new Date().toISOString() })
    .eq('id', req.params.id)
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

module.exports = router;
