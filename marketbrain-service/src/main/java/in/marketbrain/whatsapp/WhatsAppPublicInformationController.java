package in.marketbrain.whatsapp;

import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;

@RestController
@RequestMapping("/api/v1/whatsapp")
class WhatsAppPublicInformationController {

    private static final String CONTACT_EMAIL = "kkool.harshal+whatsapp@gmail.com";

    @GetMapping(value = "/privacy", produces = MediaType.TEXT_HTML_VALUE)
    ResponseEntity<String> privacyPolicy() {
        return publicPage("""
                <!doctype html>
                <html lang="en">
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <title>MarketBrain WhatsApp Privacy Policy</title>
                  <style>
                    body { font-family: system-ui, sans-serif; line-height: 1.55; margin: 0 auto; max-width: 760px; padding: 2rem; color: #182026; }
                    h1, h2 { line-height: 1.2; }
                    a { color: #075e54; }
                  </style>
                </head>
                <body>
                  <main>
                    <h1>MarketBrain WhatsApp Privacy Policy</h1>
                    <p><strong>Effective date:</strong> 10 September 2026</p>
                    <p>MarketBrain is a private, single-user market-research and paper-trading application. Its WhatsApp integration is an owner-operated sandbox notification mirror. It is not offered to customers and cannot place broker orders.</p>

                    <h2>Information processed</h2>
                    <p>When Meta delivers a WhatsApp webhook, MarketBrain processes the WhatsApp Business Account ID, phone-number ID, participant identifier, provider message ID, event type, delivery state, timestamp, and any supported button identifier needed to validate and deduplicate the event.</p>

                    <h2>Information retained</h2>
                    <p>MarketBrain does not retain raw webhook JSON, message text, telephone numbers, Meta access tokens, App Secrets, verify tokens, or raw button payloads. It retains only keyed hashes of selected identifiers, a payload hash, event classification, acceptance disposition, and receipt timestamp as minimal local security and idempotency evidence.</p>

                    <h2>Purpose and sharing</h2>
                    <p>The information is used only to deliver and validate the owner's personal PAPER-mode notifications, prevent duplicate processing, and maintain local security evidence. It is not sold, licensed, used for advertising, distributed to other users, or used to execute a live trade.</p>

                    <h2>Storage and retention</h2>
                    <p>Minimal hashed audit evidence is stored on the owner's self-hosted system and retained for the application's security and audit lifecycle. Raw message content is not stored. Access is limited to the owner.</p>

                    <h2>Deletion and contact</h2>
                    <p>The owner may request removal of locally retained WhatsApp integration data by emailing <a href="mailto:%1$s">%1$s</a>. Do not send passwords, access tokens, App Secrets, or message contents. See the <a href="/api/v1/whatsapp/data-deletion">data deletion instructions</a>.</p>

                    <h2>Changes</h2>
                    <p>This policy will be updated before the integration expands beyond its current private sandbox scope.</p>
                  </main>
                </body>
                </html>
                """.formatted(CONTACT_EMAIL));
    }

    @GetMapping(value = "/data-deletion", produces = MediaType.TEXT_HTML_VALUE)
    ResponseEntity<String> dataDeletionInstructions() {
        return publicPage("""
                <!doctype html>
                <html lang="en">
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <title>MarketBrain WhatsApp Data Deletion</title>
                  <style>
                    body { font-family: system-ui, sans-serif; line-height: 1.55; margin: 0 auto; max-width: 760px; padding: 2rem; color: #182026; }
                    h1, h2 { line-height: 1.2; }
                    a { color: #075e54; }
                  </style>
                </head>
                <body>
                  <main>
                    <h1>MarketBrain WhatsApp Data Deletion Instructions</h1>
                    <p>MarketBrain is a private, single-user application. To request deletion of locally retained WhatsApp integration data, email <a href="mailto:%1$s">%1$s</a> with the subject <strong>MarketBrain WhatsApp Data Deletion</strong>.</p>
                    <p>Do not include passwords, access tokens, App Secrets, verify tokens, or private message contents. The request will be verified with the application owner before local hashed audit records and associated retained artifacts are removed according to the backup lifecycle.</p>
                    <p>Requests will be acknowledged and handled within 30 days. The WhatsApp integration may be disabled while deletion is completed to prevent new events from being recorded.</p>
                    <p><a href="/api/v1/whatsapp/privacy">Return to the privacy policy</a>.</p>
                  </main>
                </body>
                </html>
                """.formatted(CONTACT_EMAIL));
    }

    private ResponseEntity<String> publicPage(String body) {
        return ResponseEntity.ok()
                .contentType(MediaType.TEXT_HTML)
                .cacheControl(CacheControl.maxAge(Duration.ofHours(1)).cachePublic())
                .header("Content-Language", "en")
                .header("Content-Security-Policy",
                        "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
                .header("Referrer-Policy", "no-referrer")
                .header("X-Content-Type-Options", "nosniff")
                .body(body);
    }
}
