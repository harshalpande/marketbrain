package in.marketbrain.whatsapp;

interface WhatsAppWebhookEventStore {

    boolean save(WhatsAppWebhookEvent event);
}
