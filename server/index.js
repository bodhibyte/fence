// Fence License Server
// Handles license activation and trial tracking

const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// PostgreSQL connection (Railway provides DATABASE_URL)
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

// Calculate trial expiry: 3rd Sunday from now (same logic as client)
function calculateTrialExpiry() {
  const now = new Date();
  const dayOfWeek = now.getDay(); // 0 = Sunday

  // Days until next Sunday (if today is Sunday, next Sunday is 7 days)
  let daysUntilSunday = (7 - dayOfWeek) % 7;
  if (daysUntilSunday === 0) daysUntilSunday = 7;

  // Trial expires Saturday 23:59:59 before the "3rd Sunday"
  // so user CANNOT commit on the 3rd Sunday (they're blocked)
  const totalDays = daysUntilSunday + 13;

  const expiry = new Date(now);
  expiry.setDate(expiry.getDate() + totalDays);
  expiry.setHours(23, 59, 59, 999);

  return expiry;
}

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// POST /api/activate - Activate a license key (one-time only)
app.post('/api/activate', async (req, res) => {
  const { licenseCode, deviceId } = req.body;

  if (!licenseCode || !deviceId) {
    return res.status(400).json({
      success: false,
      error: 'missing_params',
      message: 'License code and device ID are required'
    });
  }

  try {
    // Check if license exists
    const licenseResult = await pool.query(
      'SELECT * FROM licenses WHERE code = $1',
      [licenseCode]
    );

    if (licenseResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'invalid_key',
        message: 'License key not found'
      });
    }

    const license = licenseResult.rows[0];

    // Check if already activated
    if (license.activated_at) {
      return res.status(409).json({
        success: false,
        error: 'already_activated',
        message: 'This license key has already been activated'
      });
    }

    // Activate the license (one-time)
    await pool.query(
      'UPDATE licenses SET activated_at = NOW(), activated_by_device = $1 WHERE code = $2',
      [deviceId, licenseCode]
    );

    return res.json({
      success: true,
      email: license.email,
      type: license.type
    });

  } catch (err) {
    console.error('Activation error:', err);
    return res.status(500).json({
      success: false,
      error: 'server_error',
      message: 'Server error during activation'
    });
  }
});

// POST /api/trial/check - Check or register trial for a device
app.post('/api/trial/check', async (req, res) => {
  const { deviceId } = req.body;

  if (!deviceId) {
    return res.status(400).json({
      success: false,
      error: 'missing_device_id',
      message: 'Device ID is required'
    });
  }

  try {
    // Check if device already has a trial
    const trialResult = await pool.query(
      'SELECT * FROM trials WHERE device_id = $1',
      [deviceId]
    );

    if (trialResult.rows.length > 0) {
      // Existing trial - return same expiry
      const trial = trialResult.rows[0];
      const expiresAt = new Date(trial.expires_at);
      const now = new Date();
      const daysRemaining = Math.max(0, Math.floor((expiresAt - now) / (1000 * 60 * 60 * 24)));

      return res.json({
        success: true,
        daysRemaining,
        expiresAt: expiresAt.toISOString(),
        isNew: false
      });
    }

    // New device - create trial
    const expiresAt = calculateTrialExpiry();

    await pool.query(
      'INSERT INTO trials (device_id, expires_at) VALUES ($1, $2)',
      [deviceId, expiresAt]
    );

    const now = new Date();
    const daysRemaining = Math.floor((expiresAt - now) / (1000 * 60 * 60 * 24));

    return res.json({
      success: true,
      daysRemaining,
      expiresAt: expiresAt.toISOString(),
      isNew: true
    });

  } catch (err) {
    console.error('Trial check error:', err);
    return res.status(500).json({
      success: false,
      error: 'server_error',
      message: 'Server error during trial check'
    });
  }
});

// GET /api/recover - Recover license for a device (if keychain storage failed)
app.get('/api/recover', async (req, res) => {
  const { deviceId } = req.query;

  if (!deviceId) {
    return res.status(400).json({
      success: false,
      error: 'missing_device_id',
      message: 'Device ID is required'
    });
  }

  try {
    // Find license activated by this device
    const result = await pool.query(
      'SELECT code, email, type FROM licenses WHERE activated_by_device = $1',
      [deviceId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'no_license',
        message: 'No license found for this device'
      });
    }

    const license = result.rows[0];
    return res.json({
      success: true,
      code: license.code,
      email: license.email,
      type: license.type
    });

  } catch (err) {
    console.error('Recovery error:', err);
    return res.status(500).json({
      success: false,
      error: 'server_error',
      message: 'Server error during recovery'
    });
  }
});

// POST /api/license/store - Store a new license (called by Stripe webhook)
app.post('/api/license/store', async (req, res) => {
  const { code, email, type, webhookSecret } = req.body;

  // Verify webhook secret to prevent unauthorized inserts
  if (webhookSecret !== process.env.WEBHOOK_SECRET) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  if (!code || !email || !type) {
    return res.status(400).json({ error: 'missing_params' });
  }

  try {
    await pool.query(
      'INSERT INTO licenses (code, email, type) VALUES ($1, $2, $3) ON CONFLICT (code) DO NOTHING',
      [code, email, type]
    );

    return res.json({ success: true });

  } catch (err) {
    console.error('License store error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Fence License Server running on port ${PORT}`);
});
