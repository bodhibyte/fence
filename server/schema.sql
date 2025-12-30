-- Fence License Server Database Schema

-- Licenses (created on Stripe purchase, activated once)
CREATE TABLE IF NOT EXISTS licenses (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,           -- Full FENCE-xxx code
  email TEXT NOT NULL,
  type TEXT NOT NULL,                  -- 'std' or 'stu'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  activated_at TIMESTAMPTZ,            -- NULL = unused, set = used
  activated_by_device TEXT             -- Device ID that activated it
);

-- Trial devices (tracked to prevent reset)
CREATE TABLE IF NOT EXISTS trials (
  device_id TEXT PRIMARY KEY,          -- SHA256 of hardware UUID
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL      -- 3rd Sunday from created_at
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_licenses_email ON licenses(email);
CREATE INDEX IF NOT EXISTS idx_licenses_code ON licenses(code);
