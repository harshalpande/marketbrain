package in.marketbrain.whatsapp;

record WhatsAppWebhookEvent(
        String eventKeyHash,
        String eventKind,
        String disposition,
        String wabaIdHash,
        String phoneNumberIdHash,
        String participantWaIdHash,
        String providerMessageIdHash,
        String actionPayloadHash,
        String payloadHash
) {
}
