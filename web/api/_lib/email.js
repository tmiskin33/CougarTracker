// Sends the verification email.
//
// Resend's REST API over fetch, so there is no SDK dependency. With no API key
// configured the link is returned to the caller instead, which keeps local
// development working without pretending an email was sent.
'use strict';

function isConfigured() {
  return !!(process.env.RESEND_API_KEY && process.env.MAIL_FROM);
}

function verificationBody(link) {
  return {
    subject: 'Verify your email for Cougar Deadline Tracker',
    text: [
      'Confirm this address to finish setting up your account:',
      '',
      link,
      '',
      'The link is good for 24 hours.',
      '',
      "If you didn't sign up, ignore this — nothing was created that can be used without it."
    ].join('\n')
  };
}

async function sendVerification(to, link) {
  const body = verificationBody(link);

  if (!isConfigured()) {
    // Not an error: it means nobody has set RESEND_API_KEY yet. Say so loudly
    // in the log rather than failing the sign-up.
    console.log('[email] not configured; verification link for ' + to + ': ' + link);
    return { sent: false, link: link };
  }

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + process.env.RESEND_API_KEY,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: process.env.MAIL_FROM,
      to: [to],
      subject: body.subject,
      text: body.text
    })
  });

  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error('Could not send the verification email. ' + detail.slice(0, 200));
  }
  return { sent: true };
}

module.exports = { sendVerification, isConfigured, verificationBody };
