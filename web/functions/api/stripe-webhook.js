// Cloudflare Pages Function - Stripe Webhook Handler
// Handles checkout.session.completed events to generate and email license keys

import { generateLicenseCode } from './generate-license.js';

/**
 * Verify Stripe webhook signature
 * @param {string} payload - Raw request body
 * @param {string} signature - Stripe-Signature header
 * @param {string} secret - Webhook signing secret
 * @returns {Promise<boolean>}
 */
async function verifyStripeSignature(payload, signature, secret) {
  try {
    // Parse the signature header
    const sigParts = {};
    signature.split(',').forEach(part => {
      const [key, value] = part.split('=');
      sigParts[key] = value;
    });

    const timestamp = sigParts['t'];
    const expectedSig = sigParts['v1'];

    if (!timestamp || !expectedSig) {
      console.error('Missing timestamp or signature in header');
      return false;
    }

    // Check timestamp is within tolerance (5 minutes)
    const now = Math.floor(Date.now() / 1000);
    if (Math.abs(now - parseInt(timestamp)) > 300) {
      console.error('Webhook timestamp too old');
      return false;
    }

    // Compute expected signature
    const signedPayload = `${timestamp}.${payload}`;
    const encoder = new TextEncoder();
    const keyData = encoder.encode(secret);
    const payloadData = encoder.encode(signedPayload);

    const key = await crypto.subtle.importKey(
      'raw',
      keyData,
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );

    const sig = await crypto.subtle.sign('HMAC', key, payloadData);
    const computedSig = Array.from(new Uint8Array(sig))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');

    return computedSig === expectedSig;
  } catch (err) {
    console.error('Signature verification error:', err);
    return false;
  }
}

export async function onRequestPost(context) {
  const { request, env } = context;

  try {
    // Get the raw body for signature verification
    const body = await request.text();

    // Verify Stripe signature
    const signature = request.headers.get('stripe-signature');
    if (!signature) {
      console.error('Missing Stripe signature');
      return new Response(JSON.stringify({ error: 'Missing signature' }), { status: 400 });
    }

    const isValid = await verifyStripeSignature(body, signature, env.STRIPE_WEBHOOK_SECRET);
    if (!isValid) {
      console.error('Invalid Stripe signature');
      return new Response(JSON.stringify({ error: 'Invalid signature' }), { status: 400 });
    }

    // Parse the event
    const event = JSON.parse(body);

    // Only handle checkout.session.completed
    if (event.type !== 'checkout.session.completed') {
      return new Response(JSON.stringify({ received: true }), { status: 200 });
    }

    const session = event.data.object;
    const customerEmail = session.customer_details?.email;

    if (!customerEmail) {
      console.error('No customer email in checkout session');
      return new Response(JSON.stringify({ error: 'No customer email' }), { status: 400 });
    }

    // Determine license type based on amount
    // amount_total is in cents
    const amount = session.amount_total || 0;
    const licenseType = amount <= 500 ? 'stu' : 'std';  // $5 or less = student

    console.log(`Generating ${licenseType} license for ${customerEmail}, amount: $${amount/100}`);

    // Generate license code
    const licenseCode = await generateLicenseCode(
      customerEmail,
      licenseType,
      env.LICENSE_SECRET_KEY
    );

    // Store license in database (Railway server)
    try {
      const storeResponse = await fetch(`${env.LICENSE_API_URL}/api/license/store`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          code: licenseCode,
          email: customerEmail,
          type: licenseType,
          webhookSecret: env.LICENSE_WEBHOOK_SECRET
        })
      });
      if (!storeResponse.ok) {
        console.error('Failed to store license in DB:', await storeResponse.text());
      }
    } catch (dbErr) {
      console.error('Error storing license in DB:', dbErr);
      // Continue anyway - license was generated, customer will receive email
    }

    // Send email via Resend
    const emailResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'Fence <noreply@usefence.app>',
        to: customerEmail,
        subject: 'Your Fence License Key',
        html: `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px 20px;">
            <h1 style="font-size: 24px; font-weight: normal; color: #1a1a1a; margin-bottom: 24px;">Thanks for purchasing Fence!</h1>

            <p style="color: #5c5c5c; font-size: 16px; line-height: 1.6; margin-bottom: 24px;">
              Here's your license key. Enter it in the app when prompted:
            </p>

            <div style="background: #f5f5f5; padding: 20px; border-radius: 8px; margin-bottom: 24px;">
              <code style="font-size: 14px; word-break: break-all; color: #1a1a1a;">${licenseCode}</code>
            </div>

            <p style="color: #5c5c5c; font-size: 14px; line-height: 1.6;">
              <strong>Note:</strong> If you have iCloud Keychain enabled, this license will automatically sync to your other Macs.
              If not, and you need to activate on another Mac, email support@usefence.app.
            </p>

            <p style="color: #999; font-size: 13px; margin-top: 40px;">
              Questions? Reply to this email or reach out at support@usefence.app
            </p>
          </div>
        `,
      }),
    });

    if (!emailResponse.ok) {
      const error = await emailResponse.text();
      console.error('Failed to send license email:', error);
      // Still return 200 to Stripe - we received the webhook
      // The license was generated, customer can contact support
    } else {
      console.log(`License email sent to ${customerEmail}`);
    }

    return new Response(JSON.stringify({ received: true }), { status: 200 });

  } catch (error) {
    console.error('Webhook error:', error);
    return new Response(
      JSON.stringify({ error: 'Webhook processing failed' }),
      { status: 500 }
    );
  }
}
