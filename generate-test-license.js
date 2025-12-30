#!/usr/bin/env node
// Quick script to generate a test license key
// Usage: node generate-test-license.js

const crypto = require('crypto');
const fs = require('fs');

// Read secret from Secrets.xcconfig
const xcconfig = fs.readFileSync('./Secrets.xcconfig', 'utf8');
const match = xcconfig.match(/LICENSE_SECRET_KEY\s*=\s*(.+)/);
if (!match) {
  console.error('LICENSE_SECRET_KEY not found in Secrets.xcconfig');
  process.exit(1);
}
const secretKey = match[1].trim();

// Create payload
const payload = JSON.stringify({
  e: 'test@example.com',
  t: 'std',
  c: Math.floor(Date.now() / 1000)
});

// Create HMAC-SHA256 signature
const signature = crypto
  .createHmac('sha256', secretKey)
  .update(payload)
  .digest('hex');

// Combine and encode
const combined = payload + '.' + signature;
const encoded = Buffer.from(combined).toString('base64');
const licenseCode = 'FENCE-' + encoded;

console.log('\n=== Test License Key ===\n');
console.log(licenseCode);
console.log('\nPayload:', payload);
console.log('');
