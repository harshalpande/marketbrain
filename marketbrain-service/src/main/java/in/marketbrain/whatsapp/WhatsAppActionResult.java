package in.marketbrain.whatsapp;

record WhatsAppActionResult(
        String action,
        String result,
        String acknowledgement,
        boolean notifyRecipient
) {
}
