// Cloudflare Pages Function - Student Email Verification
// Sends student payment link to verified .edu emails

const STUDENT_PAYMENT_LINK = 'https://buy.stripe.com/test_9B69AS440c8c6ZTc37afS01';

const VALID_DOMAINS = [
  '.edu',
  '.edu.au',
  '.ac.uk',
  '.edu.cn',
  '.edu.in',
  '.ac.in',
  '.edu.sg',
  '.edu.hk',
  '.ac.nz',
  '.edu.br',
  '.edu.mx',
  '.ac.jp',
  '.edu.tw',
  '.ac.kr',
  '.edu.pl',
  '.edu.es',
  '.edu.fr',
  '.edu.de',
  '.edu.it',
  '.ac.za',
  '.edu.co',
  '.edu.ar',
  '.edu.pe',
  '.edu.cl',
  '.edu.ng',
  '.edu.pk',
  '.edu.ph',
  '.edu.my',
  '.edu.vn',
  '.edu.eg',
  '.ac.il'
];

function isStudentEmail(email) {
  const lowerEmail = email.toLowerCase().trim();
  return VALID_DOMAINS.some(domain => lowerEmail.endsWith(domain));
}

export async function onRequestPost(context) {
  const { request, env } = context;

  // CORS headers
  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };

  try {
    const { email } = await request.json();

    if (!email || !email.includes('@')) {
      return new Response(
        JSON.stringify({ error: 'Please enter a valid email address.' }),
        { status: 400, headers }
      );
    }

    if (!isStudentEmail(email)) {
      return new Response(
        JSON.stringify({ error: 'Please use a university email address (.edu, .ac.uk, etc.)' }),
        { status: 400, headers }
      );
    }

    // Send email via Resend
    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'Fence <noreply@usefence.app>',
        to: email,
        subject: 'Your Fence Student Discount Link',
        html: `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 500px; margin: 0 auto; padding: 40px 20px;">
            <h1 style="font-size: 24px; font-weight: normal; color: #1a1a1a; margin-bottom: 24px;">Your student discount is ready</h1>

            <p style="color: #5c5c5c; font-size: 16px; line-height: 1.6; margin-bottom: 24px;">
              Thanks for verifying your student status. Here's your exclusive link to get Fence for $5 (instead of $49):
            </p>

            <a href="${STUDENT_PAYMENT_LINK}" style="display: inline-block; background: #2D5A3D; color: white; padding: 16px 32px; font-size: 16px; font-weight: 500; text-decoration: none; border-radius: 6px;">
              Get Fence for $5
            </a>

            <p style="color: #5c5c5c; font-size: 14px; line-height: 1.6; margin-top: 32px;">
              This link is just for you. One-time purchase, lifetime access, no subscription.
            </p>

            <p style="color: #999; font-size: 13px; margin-top: 40px;">
              Questions? Reply to this email or reach out at vishal@usefence.app
            </p>
          </div>
        `,
      }),
    });

    if (!resendResponse.ok) {
      const error = await resendResponse.text();
      console.error('Resend error:', error);
      return new Response(
        JSON.stringify({ error: 'Failed to send email. Please try again.' }),
        { status: 500, headers }
      );
    }

    return new Response(
      JSON.stringify({ success: true, message: 'Check your inbox!' }),
      { status: 200, headers }
    );

  } catch (error) {
    console.error('Error:', error);
    return new Response(
      JSON.stringify({ error: 'Something went wrong. Please try again.' }),
      { status: 500, headers }
    );
  }
}

// Handle CORS preflight
export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    },
  });
}
