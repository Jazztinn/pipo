const MAX_MESSAGE_LENGTH = 4000;
const DEFAULT_RECIPIENT = "legaspijazztinnkyle@gmail.com";

export default async function handler(request, response) {
  if (request.method !== "POST") {
    response.setHeader("Allow", "POST");
    return response.status(405).json({ ok: false, error: "Method not allowed" });
  }

  let payload;
  try {
    payload = typeof request.body === "string" ? JSON.parse(request.body) : request.body;
  } catch {
    return response.status(400).json({ ok: false, error: "Invalid request" });
  }

  const message = typeof payload?.message === "string" ? payload.message.trim() : "";
  if (!message || message.length > MAX_MESSAGE_LENGTH) {
    return response.status(400).json({ ok: false, error: "Invalid message" });
  }

  const apiKey = process.env.RESEND_API_KEY;
  const sender = process.env.FEEDBACK_FROM_EMAIL;
  if (!apiKey || !sender) {
    console.error("Feedback email configuration is incomplete");
    return response.status(503).json({ ok: false, error: "Feedback is not configured" });
  }

  try {
    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: sender,
        to: [process.env.FEEDBACK_TO_EMAIL || DEFAULT_RECIPIENT],
        subject: "Anonymous Pipo feedback",
        text: message,
      }),
    });

    if (!resendResponse.ok) {
      console.error("Feedback email provider rejected request", resendResponse.status);
      return response.status(502).json({ ok: false, error: "Feedback delivery failed" });
    }

    return response.status(200).json({ ok: true });
  } catch (error) {
    console.error("Feedback email delivery failed", error);
    return response.status(502).json({ ok: false, error: "Feedback delivery failed" });
  }
}
