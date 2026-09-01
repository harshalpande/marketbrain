package in.marketbrain.telegram;

record TelegramBinding(long userId, long chatId, String displayName) {

    boolean matches(long candidateUserId, long candidateChatId) {
        return userId == candidateUserId && chatId == candidateChatId;
    }
}
