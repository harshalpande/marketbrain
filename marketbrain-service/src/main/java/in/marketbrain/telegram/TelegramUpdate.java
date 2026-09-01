package in.marketbrain.telegram;

record TelegramUpdate(
        long updateId,
        TelegramMessage message,
        TelegramCallback callback
) {
}

record TelegramMessage(
        long chatId,
        String chatType,
        long userId,
        String displayName,
        String text
) {
}

record TelegramCallback(
        String callbackId,
        long chatId,
        String chatType,
        long userId,
        String data
) {
}
