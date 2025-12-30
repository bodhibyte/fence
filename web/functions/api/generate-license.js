// generate-license.js
// Internal function - called by stripe-webhook, not exposed directly
// Generates FENCE- license codes using HMAC-SHA256 signature

/**
 * Generate a license code for a customer
 * @param {string} email - Customer email from Stripe
 * @param {string} type - License type: "std" (standard $49) or "stu" (student $5)
 * @param {string} secretKey - The LICENSE_SECRET_KEY
 * @returns {Promise<string>} The generated license code
 */
export async function generateLicenseCode(email, type, secretKey) {
  // Create the payload
  const payload = JSON.stringify({
    e: email,           // Customer email
    t: type,            // License type: "std" or "stu"
    c: Math.floor(Date.now() / 1000)  // Created timestamp (Unix seconds)
  });

  // Create HMAC-SHA256 signature using Web Crypto API
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secretKey);
  const payloadData = encoder.encode(payload);

  // Import the key for HMAC
  const key = await crypto.subtle.importKey(
    'raw',
    keyData,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  // Sign the payload
  const signature = await crypto.subtle.sign('HMAC', key, payloadData);

  // Convert signature to hex string
  const sigHex = Array.from(new Uint8Array(signature))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');

  // Combine payload and signature: payload.signature
  const combined = payload + '.' + sigHex;

  // Base64 encode (standard base64, the app handles both standard and url-safe)
  const encoded = btoa(combined);

  // Return the full license code
  return 'FENCE-' + encoded;
}

/**
 * Verify a license code (for testing/debugging)
 * @param {string} code - The full license code (FENCE-xxx...)
 * @param {string} secretKey - The LICENSE_SECRET_KEY
 * @returns {Promise<{valid: boolean, payload?: object, error?: string}>}
 */
export async function verifyLicenseCode(code, secretKey) {
  try {
    // Must start with FENCE-
    if (!code.startsWith('FENCE-')) {
      return { valid: false, error: 'Invalid license format' };
    }

    // Extract the encoded part
    const encoded = code.substring(6);

    // Decode from base64
    const decoded = atob(encoded);

    // Split by last dot to get payload and signature
    const lastDotIndex = decoded.lastIndexOf('.');
    if (lastDotIndex === -1) {
      return { valid: false, error: 'Invalid license structure' };
    }

    const payloadStr = decoded.substring(0, lastDotIndex);
    const providedSig = decoded.substring(lastDotIndex + 1);

    // Compute expected signature
    const encoder = new TextEncoder();
    const keyData = encoder.encode(secretKey);
    const payloadData = encoder.encode(payloadStr);

    const key = await crypto.subtle.importKey(
      'raw',
      keyData,
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );

    const signature = await crypto.subtle.sign('HMAC', key, payloadData);
    const expectedSig = Array.from(new Uint8Array(signature))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');

    // Compare signatures (case-insensitive)
    if (expectedSig.toLowerCase() !== providedSig.toLowerCase()) {
      return { valid: false, error: 'Invalid signature' };
    }

    // Parse and return the payload
    const payload = JSON.parse(payloadStr);
    return { valid: true, payload };

  } catch (err) {
    return { valid: false, error: err.message };
  }
}
